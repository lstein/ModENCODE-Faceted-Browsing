#!/usr/bin/perl

# this renames the old volumes from 5 september 2011 to match the new naming scheme
# e.g. :
#    "C. elegans interpreted data from 5 September 2011, part 1" -> "C. elegans interpreted data, part 1 (5 September 2011)"
use strict;

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

use constant SNAPSHOT_LIST => '/modencode/DATA_SNAPSHOTS.txt';
use constant SPECIES => {
    cele => 'C. elegans',
    dmel => 'D. melanogaster',
    dsim => 'D. simulans',
    dpse => 'D. pseudoobscura',
    dvir => 'D. viridans',
    dyak => 'D. yakuba',
    dmoj => 'D. mojavensis',
    dana => 'D. ananassae',
};

my %VOLUMES;

# initial setup
setup_credentials();
my $ec2         = VM::EC2->new();

# get devices for all mounts
my %MOUNTS;
open my $f,'/etc/mtab', or die $!;
while (<$f>) {
    chomp;
    my ($device,$volpath) = /^(\S+)\s+(\S+)/;
    next unless $device =~ m!^/dev!;
    next if $device =~ m!/dev/sda!;
    $MOUNTS{$volpath} = $device;
}
close $f;


# find all volumes that need to be re-snapshotted
open $f,SNAPSHOT_LIST or die $!;
while (<$f>) {
    chomp;
    my ($snapid,$description) = split "\t";
    my ($genus,$species,$type,$date,$part) = $description =~ /^modENCODE ([A-Z])\. (\w+) (\w+) data from (\d+ \w+ \d+)(?:, part (\d+))?/;
    my $short_name    = lc($genus).substr($species,0,3);
    $part            ||=1;
    my $mount_name = "/modencode/data/all_files/$short_name-$type-$part";
    -d $mount_name or die "$mount_name not mounted";
    my $device = $MOUNTS{$mount_name} or die "no device for $mount_name";
    $VOLUMES{$device}{description} = "modENCODE $genus. $species $type data, part $part ($date)";
    $VOLUMES{$device}{mount_name}  = $mount_name;
}
close $f;


# map these onto EBS volumes
my $metadata = $ec2->instance_metadata;
my $instance = $ec2->describe_instances($metadata->instanceId) or die "Couldn't get instance: ",$ec2->err_str;
my %ebs_ids  = map {$_->deviceName => $_->volumeId} $instance->blockDeviceMapping;

for my $d (keys %VOLUMES) {
    my $ebs_id = $ebs_ids{$d} or die "no volume id for $d";
    my $description  = $VOLUMES{$d}{description};
    my $volume = $ec2->describe_volumes($ebs_id) or die "Couldn't get volume for $ebs_id";
    print STDERR "snapshotting ",$description,' ',$VOLUMES{$d}{mount_name},' => ', $ebs_id,"...\n";
    my $snap   = $volume->create_snapshot($description) or die "Couldn't snapshot $ebs_id";
    $snap->add_tag(Name=>$snap);
    $snap->make_public(1);
    print STDERR "...$snap in progress\n";
}




exit 0;

__END__


