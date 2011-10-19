#!/usr/bin/perl

# use contents of master_copy_list.txt to create and populate volumes

use strict;
use lib '/modencode/perl/share/perl','/modencode/lib';
use FindBin '$Bin';
use constant GB =>     1_073_741_824;

my $file = shift || "$Bin/../master_copy_list.txt";
open my $fh,$file or die "$file: $!";

my $compression_tracker  = CompressionTracker->new;
my $volume_manager       = VolumeManager->new($compression_tracker);

my (%Operation,%Volumes);
while (<$fh>) {
    chomp;
    my ($species,$type,$source,$dest,$size_needed,$compress) = split "\t";
    next unless $species;
    my $vol = $volume_manager->get_volume($species,$type);
    $Volumes{$vol} = $vol;
    $vol->add_bytes($size_needed,$compress);
    push @{$Operation{$vol}},{source   => $source,
			      dest     => $dest,
			      species  => $species,
			      type     => $type,
			      size     => $size_needed,
			      compress => $compress};
}
close $fh;

for my $vol (sort {$Volumes{$a}->bytes_needed <=> $Volumes{$b}->bytes_needed} 
	     keys %Operation) {
    my $volume = $Volumes{$vol};
    for my $op (@{$Operation{$vol}}) {
	my ($source,$dest,$size_needed,$compress) = @{$op}{'source','dest','size','compress'};
	$volume->copy($source,$dest,$size_needed,$compress)
    }
    $volume->close_and_snapshot;
}

exit 0;

package CompressionTracker;

sub new {
    my $self = shift;
    return bless {
	uncompressed_total => 0,
	compressed_total   => 0,
    },ref $self || $self;
}

sub tally_compression {
    my $self = shift;
    my ($uncompressed_bytes,$compressed_bytes) = @_;
    $self->{uncompressed_total} += $uncompressed_bytes;
    $self->{compressed_total}   += $compressed_bytes;
}

sub compression_ratio {
    my $self = shift;
    return 1.5 unless $self->{compressed_total} > 0;
    return $self->{uncompressed_total}/$self->{compressed_total};
}

package VolumeManager;

use EC2Utils;
use VM::EC2;

use constant GB           =>     1_073_741_824;
use constant TB           => 1_099_511_627_776;
use constant MAX_VOL_SIZE => 1 * TB; #max for AWS EBS volumes

sub new {
    my $class  = shift;
    my $compression_tracker = shift;
    my $maxvol              = shift || MAX_VOL_SIZE;

    setup_credentials();
    my $ec2 = VM::EC2->new;
    return bless {
	ec2              =>   $ec2,
	virtual_volumes  => {},
	volbase          => {},
	maxvol           => $maxvol,
	tracker          => $compression_tracker
    },ref $class || $class;
}

sub ec2            { shift->{ec2}              }
sub maxvol         { shift->{maxvol}           }
sub compression_tracker { shift->{tracker}     }

sub get_volume {
    my $self = shift;
    my ($species,$format) = @_;
    return $self->{virtual_volumes}{$species,$format} 
           ||= VirtualVolume->new($self->ec2,$species,$format,$self->maxvol,$self->compression_tracker);
}

sub volumes {
    my $self = shift;
    return values %{$self->{virtual_volumes}};
}

sub close_and_snapshot_volumes {
    my $self = shift;
    my @volumes = $self->volumes;
    $_->close_and_snapshot foreach @volumes;
}

package RealVolume;
use Filesys::Df 'df';
use constant KB => 1024;

sub new {
    my $self = shift;
    my ($local_device,$ebs_device,$mnt_pt,$ebs) = @_;
    return bless {
	local_device => $local_device,
	ebs_device    => $ebs_device,
	mnt_pt        => $mnt_pt,
	capacity      => df($mnt_pt)->{user_bavail}*KB,
	ebs           => $ebs,
    },ref $self || $self;
}

sub local_device {shift->{local_device}}
sub ebs_device   {shift->{ebs_device}}
sub mnt_pt       {shift->{mnt_pt}}
sub capacity     {shift->{capacity}}
sub ebs          {shift->{ebs}}
sub percent_free {
    my $self = shift;
    my $r    = df($self->mnt_pt);
    return 100-$r->{per};
}
sub bytes_total  {
    my $self = shift;
    my $r = df($self->mnt_pt);
    return KB*($r->{user_bavail}+$r->{used});
}
sub bytes_free   {
    my $self = shift;
    my $r = df($self->mnt_pt);
    return $self->{capacity} = $r->{user_bavail}*KB;
}
sub has_capacity {
    my $self = shift;
    my $wanted = shift;
    return 1 if $self->{capacity} >= $wanted;  # rough guess
    return $self->bytes_free >= $wanted;       # this also sets {capacity} as a side effect
}
sub decrement_volume_size {
    my $self = shift;
    my $size = shift;
    $self->{capacity} -= $size;
}


package VirtualVolume;

use constant KB =>             1_024;
use constant GB =>     1_073_741_824;
use constant TB => 1_099_511_627_776;

use File::Basename 'basename';

sub new {
    my $self = shift;
    my ($ec2,$species,$format,$maxsize,$compression_tracker) = @_;
    my $name = $self->make_base_name($species,$format);
    return bless {'ec2'      => $ec2,
		  'species'  => $species,
		  'format'   => $format,
		  'name'     => $name,
		  'maxsize'  => $maxsize,
		  'real_volume_cnt' => 0,
		  'active_volume' => undef,
		  'need_bytes'    => 0,
		  'need_compressed_bytes'    => 0,
		  'tracker'       => $compression_tracker,
    },ref $self || $self;
}

sub ec2 {shift->{ec2}}
sub maxsize {shift->{maxsize}}
sub name    {shift->{name}}
sub species {shift->{species}}
sub format  {shift->{format}}
sub active_volume {shift->{active_volume}}
sub compression_tracker {shift->{tracker}}

sub make_base_name {
    my $self = shift;
    my ($species,$format) = @_;
    $species       =~ /^([A-Z])\.\s*(\w{3})/;
    return lc($1).$2."-$format";
}

sub add_bytes {
    my $self = shift;
    my ($size,$compressed) = @_;
    # the compress flag means that the object will be compressed
    # before transfer. To convert to actual bytes, divide by
    # compression factor
    $self->{need_compressed_bytes} += $size if $compressed;
    $self->{need_bytes}            += $size unless $compressed;
}

sub subtract_bytes {
    my $self = shift;
    my ($size,$compressed) = @_;
    $self->{need_compressed_bytes} -= $size if $compressed;
    $self->{need_bytes}            -= $size unless $compressed;
}

sub bytes_needed {
    my $self = shift;
    my $ratio = $self->compression_tracker->compression_ratio;
    return int($self->{need_bytes} + $self->{need_compressed_bytes}/$ratio);
}

sub copy {
    my $self = shift;
    my ($source,$dest,$size,$compress) = @_;
    my $mnt    = $self->get_mount();  # return active volume
    my $target = File::Spec->catfile($mnt,$dest);
    $target    .= '.gz' if $compress && $target !~ /\.gz$/;

    if (-e $target && (-M $source <= -M $target)) {
	print STDERR "$mnt: UPTODATE $source=>$target\n";
	return;
    }

    # rename target in case the mnt changed
    $size  /= $self->compression_tracker->compression_ratio if $compress;
    $mnt    = $self->get_mount($size);
    $target = File::Spec->catfile($mnt,$dest);
    $target    .= '.gz' if $compress && $target !~ /\.gz$/;

    my $tmpname = "${target}_partial";

    print STDERR "$mnt: $source=>$dest...";
    if ($compress) {
	print STDERR "gzipping...";

	# the following saves current stdout, reopens it on the
	# destination file, and does the gzip copy, then restores
	open SAVEOUT,">&STDOUT"  or die "Can't dup STDOUT: $!";
	open STDOUT,'>',$tmpname or die "open $tmpname: $!"; # redirect to the destination file
	system 'gzip','-c','--fast','--rsyncable',$source and die "gzip failed with status $?";
	open STDOUT,">&SAVEOUT"  or die "Can't dup SAVEOUT: $!";

	# preserve atime and mtime attributes
	my @stat = stat $source;
	utime($stat[8],$stat[9],$tmpname);

	# get compression ratio
	my $original_size   = -s $source;
	my $compressed_size = -s $tmpname;
	$self->compression_tracker->tally_compression($original_size,$compressed_size);
	$self->subtract_bytes($original_size,1);
	$self->decrement_real_volume($compressed_size);
    } else {
	print STDERR "copying...";
	system 'cp','-p',$source,$target and die "cp failed with status $?";
	my $original_size   = -s $source;
	$self->subtract_bytes($original_size,0);
	$self->decrement_real_volume($original_size);
    }

    rename $tmpname,$target;  # change name when done
    chmod 0644,$target;
    print STDERR "done.\n";
}

sub get_mount {
    my $self        = shift;
    my $size_needed = shift;
    my $real_volume;

    if ($real_volume = $self->{active_volume}) {
	if ($size_needed && !$real_volume->has_capacity($size_needed)) {
	    $self->close_and_snapshot($real_volume);
	    $real_volume = $self->{active_volume} = $self->get_real_volume();
	}
    } else {
	$real_volume = $self->{active_volume} = $self->get_real_volume();
    }
    return $real_volume->mnt_pt;
}

sub decrement_real_volume {
    my $self = shift;
    my $size = shift;
    my $vol  = $self->{active_volume} or return;
    $vol->decrement_volume_size($size);
}

sub get_real_volume {
    my $self = shift;

    # choose a unique name for this volume
    my $name = $self->name;
    my $cnt  = $self->{real_volume_cnt} += 1;
    my $volname = "$name-$cnt";
    my $mnt     = "/mnt/$volname";
    
    my $rv  = $self->find_mounted_volume($mnt);
    $rv   ||= $self->find_active_volume($volname,$mnt);
    $rv   ||= $self->create_real_volume($volname,$mnt);
    return $rv;
}

sub create_real_volume {
    my $self = shift;
    my ($volname,$mnt) = @_;

    # estimate the size that is most appropriate for the volume's contents
    my $unformatted_size = $self->bytes_needed * 1.12; # rough guess
    my $size_needed      = $unformatted_size < $self->maxsize ? $unformatted_size : $self->maxsize;

    # create the volume
    $size_needed = int($size_needed/GB+0.5); # size now in integral gigabytes for aws
    $size_needed ||= 1;
    print STDERR "Creating $size_needed GB volume named $volname...";

    my $ec2         = $self->ec2;
    my $meta        = $ec2->instance_metadata;
    my $instance_id = $meta->instanceId;
    my $zone        = $meta->availabilityZone;
    my $ebs         = $ec2->create_volume(-availability_zone => $zone,
					  -size              => $size_needed);
    $ec2->wait_for_volumes($ebs);
    die "Could not create volume for $volname" unless $ebs->current_status eq 'available';

    # tag it
    my $date = localtime;
    $ebs->add_tag(Name        => "$volname working copy");
    $ebs->add_tag(Role        => "modENCODE staging for 5 September 2011 data");
    $ebs->add_tag(Description => "Created by big_copy on $date");
    
    # find an unused block device and attach this volume to us
    my ($local_device,$ebs_device) = $self->unused_block_device;
    print STDERR "Attaching to $ebs_device...";
    my $attach = $ebs->attach($instance_id,$ebs_device);
    $ec2->wait_for_attachments($attach);
    die "Couldn't attach $ebs" unless $attach->current_status eq 'attached';

    # make the filesystem
    print STDERR "Making filesystem...";
    system 'sudo','/sbin/mke2fs','-q','-L',$volname,$local_device and die "mke2fs failed with $?";

    # mount it and fix permissions
    print STDERR "Mounting...";
    system 'sudo','mkdir','-p',$mnt               and die "mkdir failed with $?";
    system 'sudo','mount',$local_device,$mnt      and die "mount failed with $?";
    system 'sudo','chown',$<,$mnt;

    my ($group) = split(/\s+/,$();
    system 'sudo','chgrp',$group,$mnt;

    # register the volume
    my $volume = RealVolume->new($local_device,$ebs_device,$mnt,$ebs);
    
    print STDERR "Done.\n";

    return $volume;
}

# this returns a previously-mounted volume, which may happen if
# script is interrupted and resumed
sub find_mounted_volume {
    my $self = shift;
    my $mnt  = shift;

    # assuming an e2fs here...
    return unless -e "$mnt/lost+found";

    print STDERR "Found previously-mounted volume $mnt...";

    # restore the device and EBS volume information
    my $local_device;
    open my $mtab,"/etc/mtab" or die "/etc/mtab: $!";
    while (<$mtab>) {
	my ($device,$mount) = split /\s+/;
	if ($mnt eq $mount) {
	    $local_device = $device;
	    last;
	}
    }
    close $mtab;
    die "couldn't find device corresponding to $mnt" unless $local_device;
    (my $ebs_device = $local_device) =~ s!^/dev/xvd!/dev/sd!;  # kernel wackiness
    
    # identify corresponding volume
    my $ec2      = $self->ec2;
    my $instance = $ec2->describe_instances($ec2->instance_metadata->instanceId);
    my ($ebs) = map {$_->volume} grep {$_->deviceName eq $ebs_device} $instance->blockDeviceMapping;
    die "couldn't find EBS volume corresponding to $mnt" unless $ebs;
    print STDERR "reusing\n";
    return RealVolume->new($local_device,$ebs_device,$mnt,$ebs);
}

# this returns an unmounted but previously-created volume, which may happen if
# script is interrupted and resumed
sub find_active_volume {
    my $self = shift;
    my ($volname,$mnt) = @_;
    my $ec2  = $self->ec2;
    my $instance_id = $ec2->instance_metadata->instanceId;
    my $zone        = $ec2->instance_metadata->availabilityZone;

    my @volumes = $ec2->describe_volumes({'status'   => 'available',
					  'tag:Name' => "$volname working copy",
					  'availability-zone' => $zone});
    return unless @volumes;


    # find the most recent one if there are multiple
    my ($ebs) = sort {$b->createTime <=> $a->createTime} @volumes;

    print STDERR "Found unused working volume $ebs...";

    # find an unused block device and attach this volume to us
    my ($local_device,$ebs_device) = $self->unused_block_device;

    print STDERR "attaching to $ebs_device...";
    my $attach = $ebs->attach($instance_id,$ebs_device);

    $ec2->wait_for_attachments($attach);
    die "Couldn't attach $ebs" unless $attach->current_status eq 'attached';
    
    # mount it and fix permissions
    print STDERR "Mounting...";
    while (!-e $local_device) {
	print STDERR "waiting for local device to appear...";
	sleep 5;
    }
    system 'sudo','mkdir','-p',$mnt               and die "mkdir failed with $?";
    system 'sudo','mount',$local_device,$mnt      and die "mount failed with $?";
    system 'sudo','chown',$<,$mnt;
    my ($group) = split(/\s+/,$();
    system 'sudo','chgrp',$group,$mnt;

    print STDERR "Done.\n";    
    return RealVolume->new($local_device,$ebs_device,$mnt,$ebs);    
}

sub close_and_snapshot {
    my $self = shift;
    my $volume = shift || $self->active_volume;
    print STDERR $volume->mnt_pt,': ',$volume->percent_free,'% free...';
    print STDERR "Unmounting ",$volume->local_device,'...';
    system 'sudo','umount',$volume->mnt_pt and die "Could not umount ",$volume->mnt_pt,": $?";

    my $ebs         = $volume->ebs;
    print STDERR "Detaching $ebs...";
    my $attach      = $ebs->detach;
    $self->ec2->wait_for_attachments($attach);
    $ebs->current_status eq 'available' or die "Could not detach ",$volume->mnt_pt,": ",$self->ec2->error_str;
    
    if (0) {
	print STDERR "snapshots disabled\n";
	return;
    }

    my $description = $self->snapshot_description($volume);
    print STDERR "Creating snapshot $description...";
    my $snap = $ebs->create_snapshot($description);
    sleep 2;
    print STDERR "Done (snapshot continuing in background).\n";
    $snap->add_tag(Name => $self->snapshot_name($volume));
}

sub unused_block_device {
    my $self = shift;
    # find a device that isn't in use.
    my $base =   -e "/dev/sda1"   ? "/dev/sd"
	       : -e "/dev/xvda1"  ? "/dev/xvd"
	       : '';
    my $ebs = '/dev/sd';
    die "Don't know what kind of disk device to use; neither /dev/sda1 nor /dev/xvda1 exists" unless $base;

    for my $major ('f'..'p') {
	for my $minor (1..15) {
	    my $local_device = "${base}${major}${minor}";
	    next if -e $local_device;
	    my $ebs_device = "/dev/sd${major}${minor}";
	    return ($local_device,$ebs_device);
	}
    }
    return;
}

sub snapshot_description {
    my $self    = shift;
    my $volume  = shift;
    my $mnt     = $volume->mnt_pt;
    my ($count) = $mnt =~ /-(\d+)$/;
    my $species = $self->species;
    my $format  = $self->format;
    return "modENCODE $species $format data from 5 September 2011, part $count";
}

sub snapshot_name {
    my $self    = shift;
    my $volume  = shift;
    my $mnt     = basename($volume->mnt_pt);
    return "modENCODE $mnt";
}

1;

