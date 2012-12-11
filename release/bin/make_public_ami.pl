#!/usr/bin/perl

# Make a clean functional AMI of the currently running
# instance without shutting it down.
use strict;
use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;
use Filesys::Df 'df';

@ARGV == 2 or die "Usage: clean_ami.pl <release number in format 'v3'> <data date in format 'dd Mon YYYY>";
my $release   = shift;
my $data_date = shift;

$release    =~ /^v\d+$/                    or die "Please provide version in format 'v3'";
$data_date  =~ /\d+ [a-zA-Z]{3} \d{4}$/    or die "Please provide data date in format 'dd Mon YYY'";

my $ImageName                         = "modENCODE Data Image $release ($data_date)";
my $ImageDescription                  = "modENCODE project (www.modencode.org) data server image, preloaded with data from $data_date";
my $ModENCODERootSnapshotDescription  = "modENCODE public data root, $release (data from $data_date)";
my $RootSnapshotDescription           = "modENCODE data server root volume, $release";

setup_credentials();
my $ec2 = VM::EC2->new();

# collect all the information we'll need to create the ami

print STDERR "Gathering information about current instance....\n";
my $metadata = $ec2->instance_metadata;
my $image    = $ec2->describe_images($metadata->imageId) or die;
my $instance = $ec2->describe_instances($metadata->instanceId) or die;
my $kernel   = $metadata->kernelId;
my $ramdisk  = $metadata->ramdiskId;
my $architecture = $image->architecture;

my @block_devices = $instance->blockDeviceMapping;
my @block_device_mapping = grep {defined $_} map {to_block_string($_)} @block_devices;

# make clean copies of the /modencode root as well as the root volume
print STDERR "Copying / and /modencode....\n";
my $modencode_root_vol = clean_copy('/modencode','/mnt/modencode_root',[]);
my $root_vol           = clean_copy('/',         '/mnt/root',          ['/home/*','/root/.ssh','/var/log/apache2/*',
									'/var/log/vsftpd.log','/var/log/debug',
									'/var/log/lastlog','/var/log/wtmp',
									'/var/log/syslog','/var/log/faillog','/var/log/dmesg',
									'/var/log/user.log','/var/log/news/*',
									'/var/log/mail.*','/var/log/messages',
									'/var/log/kern.log','/var/log/auth.log','/var/log/daemon.log',
									'/var/log/*.[0-9]','/var/log/*gz',
									'/var/mail/*','/var/backups/*',
									'/var/run/*','/var/lock/*','/var/cache/*/*',
									'/var/mail/*','/var/spool/*','/var/backups/*',
									'/tmp/*','/var/tmp/*',
									'/etc/modencode_firsttime',
									'/etc/passwd*','/etc/group*','/etc/shadow*']);
# create a home directory for ubuntu
system 'sudo','rsync','-xavzC','/etc/skel/','/mnt/root/home/ubuntu/';
system 'sudo','mkdir',                      '/mnt/root/home/ubuntu/.ssh';
system 'sudo','chmod','u+rwx,go-rwx',       '/mnt/root/home/ubuntu/.ssh';
system 'sudo','chown','-R','ubuntu.ubuntu', '/mnt/root/home/ubuntu/';

# scrub users and groups in the new root that are greater than 1000
copy_password('/etc/passwd','/mnt/root/etc/passwd');
copy_group   ('/etc/group','/mnt/root/etc/group');
copy_shadow  ('/etc/shadow','/mnt/root/etc/shadow');

# create snapshots
print STDERR "Snapshotting / and /modencode....\n";
my $modencode_root_snap       = create_snapshot($modencode_root_vol,'/mnt/modencode_root',$ModENCODERootSnapshotDescription);
my $root_snap                 = create_snapshot($root_vol,          '/mnt/root',          $RootSnapshotDescription);

# wait for the two snapshots
$ec2->wait_for_snapshots($modencode_root_snap,$root_snap);
$modencode_root_snap->make_public('true');

print STDERR "Unattaching and deleting staging volumes...\n";
$ec2->wait_for_attachments($root_vol->detach(),$modencode_root_vol->detach());
$ec2->delete_volume($root_vol);
$ec2->delete_volume($modencode_root_vol);

# Update block device list with the /modencode volume
push @block_device_mapping,"/dev/sdf1=${modencode_root_snap}::true";

my   @args;
push @args,(-kernel_id           => $kernel);
push @args,(-ramdisk_id          => $ramdisk)             if $ramdisk;
push @args,(-architecture        => $architecture)        if $architecture;
push @args,(-root_device_name    => '/dev/sda1');
push @args,(-block_device_mapping=> \@block_device_mapping);
print STDERR "Registering image...\n";

if (my $image = $ec2->describe_images({name=>$ImageName})) {
    print STDERR "WARNING: preexisting image named $ImageName: deleting...\n";
    $ec2->deregister_image($image);
}
my $public_image = $root_snap->register_image(-name        => $ImageName,
					      -description => $ImageDescription,
					      @args) or die $ec2->error_str;

print STDERR "Making image public...\n";
$public_image->add_tag(Name    => $ImageName);
$public_image->make_public('true');
print "Created new modENCODE public image $public_image\n";

print STDERR "Fixing the HTML cloud guide page...\n";
fix_cloud_guide();

1;

exit 0;

sub to_block_string {
    my $mapping  = shift;
    my $device   = $mapping->deviceName;
    my $delete   = 'true';
    my $snapshot = $mapping->volume->snapshotId;
    my $size     = $mapping->volume->size;

    # find the volume that corresponds to the device
    my $fstab    = get_fstab();
    return if $mapping->volume->tags->{Name} =~ /staging/;
    return unless $fstab->{$device};     # not mounted
    return if $fstab->{$device} eq '/';  # ignore root device
    return if $fstab->{$device} eq '/modencode';

    return "$device=$snapshot:$size:true";
}

my %Devices;
sub get_fstab {
    return \%Devices if %Devices;
    open my $mtab,'<','/etc/mtab' or die "mtab: $!";
    while (<$mtab>) {
	my ($device,$mt) = split /\s+/;
	$device =~ s/xvd/sd/;
	$Devices{$device} = $mt;
    }
    return \%Devices;
}

sub clean_copy {
    my ($mounted_volume,$staging_volume,$excluded_paths) = @_;
    $excluded_paths ||= [];
    my $volume = create_staging_volume(df($mounted_volume)->{blocks}*1024,$staging_volume,get_label($mounted_volume),get_type($mounted_volume));
    copy($mounted_volume,$staging_volume,$excluded_paths);
    return $volume;
}

# this should be in a library
sub create_staging_volume {
    my ($bytes,$mntpt,$label,$fstype) = @_;
    my $gig    = $bytes/1_073_741_824;
    my $size   = int($gig+0.5) || 1;

    my $meta        = $ec2->instance_metadata;
    my $instance_id = $meta->instanceId;
    my $zone        = $meta->availabilityZone;

    my ($ebs,$needs_filesystem);
    # use most recent snapshot if there is one -- this tag is assigned in create_snapshot()
    my @snaps      = $ec2->describe_snapshots({'tag:Role'=>"staging volume for $mntpt"});
    if (@snaps) {
	my ($most_recent) = sort {$b->startTime cmp $a->startTime} @snaps;
	print STDERR "Reusing staging volume $most_recent for $mntpt...";
	$ebs = $most_recent->create_volume(-availability_zone => $zone);
    } else {
	print STDERR "Creating $size GB staging volume for $mntpt...";
	$ebs         = $ec2->create_volume(-availability_zone => $zone,
					   -size              => $size);
	$needs_filesystem++;
    }

    $ebs or die "Could not create volume for $mntpt: ",$ec2->error_str;

    $ec2->wait_for_volumes($ebs);
    die "Could not create staging volume" unless $ebs->current_status eq 'available';

    # tag it
    my $date = localtime;
    $ebs->add_tag(Name        => "staging volume for $mntpt created by clean_ami.pl on $date");

    # find an unused block device and attach this volume to us
    my ($local_device,$ebs_device) = unused_block_device();
    print STDERR "Attaching to $ebs_device...";
    my $attach = $ebs->attach($instance_id,$ebs_device);
    $ec2->wait_for_attachments($attach);
    die "Couldn't attach $ebs" unless $attach->current_status eq 'attached';

    # will get rid of this when we are done
    $attach->deleteOnTermination('true');

    # make the filesystem
    if ($needs_filesystem) {
	print STDERR "Making filesystem...";
	my @label = $label ? ('-L'=>$label) : ();
	system 'sudo','/sbin/mke2fs','-q','-j','-t',$fstype,@label,$local_device and die "mke2fs failed with $?";
    }

    # mount it and fix permissions
    print STDERR "Mounting...";
    system 'sudo','mkdir','-p',$mntpt               and die "mkdir failed with $?";
    system 'sudo','mount',$local_device,$mntpt      and die "mount failed with $?";

    return $ebs;
}

sub create_snapshot {
    my ($volume,$mntpt,$description) = @_;
    system 'sudo','umount',$mntpt and die "Can't umount $mntpt: $?";
    my $snap =  $volume->create_snapshot($description);
    $snap->add_tag('Role'=>"staging volume for $mntpt");
    $snap->add_tag('Name'=>$description);
    return $snap;
}

sub copy {
    my ($source,$dest,$exclude) = @_;

    $exclude ||= [];
    my @exclude_args = map {"--exclude=$_"} @$exclude;

    # remount $source somewhere else so that we don't end up
    # copying udev filesystems, etc
    my $bind = $source eq '/' ? '/tmp/root' : "/tmp/$source";
    system "sudo mkdir -p $bind";
    system "sudo mount --bind $source $bind" and die "mount --bind $source $bind failed with status $?";
    system 'sudo','rsync',
           '-xavz',
           '--delete',
           '--delete-excluded',
           '--exclude=lost+found/',
           '--exclude=*~',
           '--exclude=#*',
           @exclude_args,
           "$bind/",$dest and die "rsync failed with status $?";
    system "sudo umount $bind";
}

sub get_label {
    my $volume = shift;
    my $device = get_device($volume) || return;
    chomp (my $label = `sudo e2label $device`);
    return $label;
}

sub get_device {
    my $mntpt = shift;
    open my $f,'/etc/mtab' or die "Can't open /etc/mtab: $!";
    while (<$f>) {
	chomp;
	my ($device,$volume,$type) = split /\s+/;
	return $device if $volume eq $mntpt;
    }
    return;
}

sub get_type {
    my $mntpt = shift;
    open my $f,'/etc/mtab' or die "Can't open /etc/mtab: $!";
    while (<$f>) {
	chomp;
	my ($device,$volume,$type) = split /\s+/;
	return $type if $volume eq $mntpt;
    }
    return;
}

sub copy_password {
    my ($in_path,$out_path) = @_;
    open my $out,"|sudo dd of='$out_path'" or die "sudo dd failed: $!";
    open my $in,'<',$in_path or die "$in_path: $!";
    while (<$in>) {
	my ($user,$password,$uid) = split ':';
	next if $uid > 1000 && $uid < 65534; # exclude >1000 users but not "nobody" user
	print $out $_;
    }
    close $out;
}

sub copy_group {
    copy_password(@_);  # can do same thing
}

sub copy_shadow {
    my ($in_path,$out_path) = @_;
    open my $in, "sudo dd if='$in_path'|"  or die "sudo dd if=$in_path failed: $!";
    open my $out,"|sudo dd of='$out_path'" or die "sudo dd of=$out_path failed: $!";
    while (<$in>) {
	my ($name) = split ':';
	my $uid    = getpwnam($name);
	next if $uid > 1000 && $uid < 65534;
	print $out $_;
    }
    close $in;
    close $out;
    system 'sudo','chgrp','shadow',$out_path;
    system 'sudo','chmod','g=r,o=',$out_path;
}

sub fix_cloud_guide {
    system "/modencode/release/bin/update_cloud_image_page.pl";
}
