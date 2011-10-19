#!/usr/bin/perl

use strict;
use FindBin '$RealBin';
use lib "$RealBin/../perl/share/perl","$RealBin/../lib";
use File::Path 'make_path';
use EC2Utils;
use VM::EC2;

setup_credentials();

my $ec2  = VM::EC2->new or die "Couldn't initialize connection to Amazon EC2: $!";
my $meta = $ec2->instance_metadata;
my $instance_id = $meta->instanceId;
my $zone        = $meta->availabilityZone;

warn "Creating data volumes. This may take a while...\n";

# get list of snapshots already attached to this instance
my $instance           = $ec2->describe_instances($instance_id);
my @block_devices      = $instance->blockDeviceMapping;
my %attached_snapshots = map {eval{$_->volume->snapshotId} => 1} @block_devices;

open my $f,'<','/modencode/DATA_SNAPSHOTS.txt' or die "DATA_SNAPSHOTS.txt: $!";

my %snapshots;
while (<$f>) {
    chomp;
    next if /^\s*#/;
    my ($snapid,$description) = /^([\w-]+)\s+(.+)/;
    next if $attached_snapshots{$snapid};

    my $snap           = $ec2->describe_snapshots($snapid) or next;

    my ($local_device,$ebs_device)      = unused_block_device();
    $snapshots{$snap}{name}             = volume_name($description);
    $snapshots{$snap}{description}      = $description;
    $snapshots{$snap}{snapshot}         = $snap;
    $snapshots{$snap}{local_device}     = $local_device;
    $snapshots{$snap}{ebs_device}       = $ebs_device;
}

unless (keys %snapshots) {
    print STDERR "No snapshots need to be added at this time.\n";
    exit 0;
}

my @volumes;
for my $snap (keys %snapshots) {
    my $volume = $snapshots{$snap}{snapshot}->create_volume(-zone=>$zone);
    $volume->add_tag(Name => $snapshots{$snap}{description});
    $snapshots{$snap}{volume} = $volume;
    push @volumes,$volume;
}

# wait for all volumes to become available
my $status = $ec2->wait_for_volumes(@volumes);
my @failed = grep {$status->{$_} ne 'available'} @volumes;
warn "One or more volumes could not be created: @failed\n" if @failed;
@volumes   = grep {$status->{$_} eq 'available'} @volumes;

warn "Attaching data volumes to this instance...\n";
my @attachments;
for my $snap (keys %snapshots) {
    my $volume = $snapshots{$snap}{volume}     or die;
    my $dev    = $snapshots{$snap}{ebs_device} or die;
    warn "Attaching $snapshots{$snap}{name} to unused disk device $dev\n";
    push @attachments,$volume->attach($instance_id,$dev);
}

warn "Waiting for attachments to complete...\n";
$status = $ec2->wait_for_attachments(@attachments);
@failed = grep {$status->{$_} ne 'attached'} @attachments;
warn "One or more volumes could not be attached: @failed\n" if @failed;
@attachments = grep {$status->{$_} eq 'attached'} @attachments;

warn "Mounting data volumes on /modencode/all_files/...\n";

for my $a (@attachments) {
    my $vol    = $a->volume or die;
    $vol->delete_on_termination('true');
    my $snap   = $vol->snapshotId or die;
    my $device = $snapshots{$snap}{local_device} or die;
    my $name   = $snapshots{$snap}{name}         or die;
    my $mntpt  = "/modencode/data/all_files/$name";
    make_path($mntpt);
    system 'sudo','mount',$device,$mntpt,'-o','ro';
}

warn "Recording mount information to fstab...\n";
system 'sudo',"$RealBin/update_fstab.pl",'--ignore_bind';

exit 0;

my %Allocated;
sub unused_block_device {
    # find a device that isn't in use.
    my $base =   -e "/dev/sda1"   ? "/dev/sd"
	       : -e "/dev/xvda1"  ? "/dev/xvd"
	       : '';
    my $ebs = '/dev/sd';
    die "Don't know what kind of disk device to use; neither /dev/sda1 nor /dev/xvda1 exists" unless $base;

    for my $major ('g'..'p') {
	for my $minor (1..15) {
	    my $local_device = "${base}${major}${minor}";
	    next if -e $local_device;
	    next if $Allocated{$local_device}++;
	    my $ebs_device = "/dev/sd${major}${minor}";
	    return ($local_device,$ebs_device);
	}
    }
    return;
}

sub volume_name {
    my $description = shift;
    my ($genus,$species,$format) = $description  =~ /modENCODE ([A-Z])\. (\w+) (\w+) data/ 
	or die "failed to derive name from description";
    my ($part)      =  $description =~ /part (\d+)/;
    $part         ||= 1;
    return lc($genus).substr($species,0,3).'-'.$format.'-'.$part;
}
