#!/usr/bin/perl

# this creates a snapshot of the root in a safe manner

use strict;
use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;
use Filesys::Df;

use constant ROOT     => '/modencode';
use constant VERSION  => '/modencode/release/VERSION';
use constant MNT      => '/mnt/root_copy';

setup_credentials();
my $ec2         = VM::EC2->new();

my ($version,$data_date) = get_version(VERSION);
create_snapshot_staging_volume() unless -e MNT . '/lost+found';
my ($device,$volume)  = get_device_and_volume(MNT) or die "Couldn't find device for ",MNT;
system 'rsync',
    '-xavz',
    '--safe-links',
    '-C',
    '--delete',
    '--exclude=lost+found/',
    '--exclude=/data/C.*/',
    '--exclude=/data/D.*/',
    ROOT.'/',MNT and die "rsync failed with status $?";

system 'sudo','umount',MNT and die "failed to unmount: $?";
my $snap = make_snapshot($volume,$version,$data_date);
system 'sudo','mount',$device,MNT and die "failed to remount: $?";

fix_cloud_guide($snap);

print STDERR "Done\n";

exit 0;

sub get_version {
    my $path = shift;
    unless (-e $path) {
	open my $v,'>',$path or die "$path: $!";
	print $v 1,"\n";
	print $v "5 September 2011\n";
	close $v;
    }
    open my $f,$path or die "$path: $!";
    chomp (my $version = <$f>);
    chomp (my $date    = <$f>);
    close $f;

    $version++;  # next version
    open $f,'>',$path or die "$path: $!";
    print $f $version,"\n";
    print $f $date,"\n";
    close $f;

    return ($version,$date);
}

sub get_device_and_volume {
    my $mtpt = shift;
    my $dev;
    open my $mtab,'<','/etc/mtab' or die "mtab: $!";
    while (<$mtab>) {
	my ($device,$mt) = split /\s+/;
	$dev ||= $device if $mt eq $mtpt;
    }
    return unless $dev; 

    my $instance_id = $ec2->instance_metadata->instanceId;
    my $instance    = $ec2->describe_instances($instance_id) or return;
    my ($mapping)   = grep {$_->deviceName eq $dev} $instance->blockDeviceMapping;
    return unless $mapping;
    return ($dev,$mapping->volume);
}

# this should be in a library
sub create_snapshot_staging_volume {
    my $self = shift;
    my $bytes  = df(ROOT)->{blocks}*1024;
    my $gig    = $bytes/1_073_741_824;
    my $size   = int($gig+0.5) || 1;
    print STDERR "Creating $size GB staging volume...";

    my $meta        = $ec2->instance_metadata;
    my $instance_id = $meta->instanceId;
    my $zone        = $meta->availabilityZone;
    my $ebs         = $ec2->create_volume(-availability_zone => $zone,
					  -size              => $size);
    $ec2->wait_for_volumes($ebs);
    die "Could not create staging volume" unless $ebs->current_status eq 'available';

    # tag it
    my $date = localtime;
    $ebs->add_tag(Name        => "modENCODE data root for staging & snapshotting");
    
    # find an unused block device and attach this volume to us
    my ($local_device,$ebs_device) = unused_block_device();
    print STDERR "Attaching to $ebs_device...";
    my $attach = $ebs->attach($instance_id,$ebs_device);
    $ec2->wait_for_attachments($attach);
    die "Couldn't attach $ebs" unless $attach->current_status eq 'attached';

    # will get rid of this when we are done
    $attach->deleteOnTermination('true');

    # make the filesystem
    print STDERR "Making filesystem...";
    system 'sudo','/sbin/mke2fs','-q','-j','-L','snapshot-root',$local_device and die "mke2fs failed with $?";

    # mount it and fix permissions
    print STDERR "Mounting...";
    system 'sudo','mkdir','-p',MNT                and die "mkdir failed with $?";
    system 'sudo','mount',$local_device,MNT      and die "mount failed with $?";
    system 'sudo','chown',$<,MNT;

    my ($group) = split(/\s+/,$();
    system 'sudo','chgrp',$group,MNT;
}

# this should be in a library
sub unused_block_device {
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

sub make_snapshot {
    my ($volume,$version,$data_date) = @_;
    my $description = "modENCODE public data root, version $version, data release $data_date";
    print STDERR "Snapshotting $description...";
    my $snapshot = $volume->create_snapshot($description);
    $snapshot->make_public(1);
    $snapshot->add_tag(Name=>'modENCODE public data root');
    print STDERR "$snapshot\n";
    return $snapshot;
}

sub fix_cloud_guide {
    my $snapshot = shift;
    my $src = '/modencode/htdocs/modencode-cloud.html';
    my $dest = $src.'.new';
    open my $f,'<', $src or die "$src: $!";
    open my $o,'>',$dest or die "$dest: $!";
    while (<$f>) {
	s!<b>snap-[a-f0-9]+</b>!<b>$snapshot</b>!;
    } continue {
        print $o $_;
    }
    close $o;
    rename $dest,$src;
}

1;





