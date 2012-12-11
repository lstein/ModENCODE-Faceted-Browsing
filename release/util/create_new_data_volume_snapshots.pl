#!/usr/bin/perl

# this creates suitable snapshots for the volumes containing data for the 7 December 2011 data release (modMine v27)
use strict;

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

use constant RELEASE => '7 December 2011';
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

# initial setup
setup_credentials();
my $ec2         = VM::EC2->new();

# find all volumes that are mounted in /etc/mtab that aren't in /etc/fstab
open my $f,'/etc/fstab' or die $!;

my %FSTAB;
while (<$f>) {
    chomp;
    my ($device) = /^(\S+)/;
    $FSTAB{$device}++;
}
close $f;

my %NEW;
open $f,'/etc/mtab', or die $!;
while (<$f>) {
    chomp;
    my ($device,$volpath) = /^(\S+)\s+(\S+)/;
    next unless $device =~ m!^/dev!;
    next if $device =~ m!/dev/sda!;
    next if $FSTAB{$device};
    my ($volname) = $volpath =~ m!([^/]+)$!;

    $NEW{$device} = $volname;
}
close $f;

# now map these onto EBS volumes
my $metadata = $ec2->instance_metadata;
my $instance = $ec2->describe_instances($metadata->instanceId) or die "Couldn't get instance: ",$ec2->err_str;
my %ebs_ids  = map {$_->deviceName => $_->volumeId} $instance->blockDeviceMapping;

for my $d (keys %NEW) {
    my $ebs_id = $ebs_ids{$d} or die "no volume id for $d";
    my $volname = $NEW{$d};
    my ($sp,$dtype,$count) = split '-',$volname;
    my $species      = SPECIES->{$sp} or die "unknown species $sp";
    my $description  = "modENCODE $species $dtype data, part $count (".RELEASE.")";
    print STDERR "snapshotting ",$description,'/',$volname,' => ', $ebs_id,"...\n";
    my $volume = $ec2->describe_volumes($ebs_id) or die "Couldn't get snapshot for $ebs_id";
    my $snap   = $volume->create_snapshot($description) or die "Couldn't snapshot $ebs_id";
    $snap->add_tag(Name=>$snap);
    $snap->make_public(1);
    print STDERR "...$snap in progress\n";
}



