#!/usr/bin/perl

# print out most recent public data snapshot, genome browser AMI and data site AMI

use strict;
use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

setup_credentials();
my $ec2 = VM::EC2->new();
 
# get the most recent snapshot named "modENCODE public data root*"
my @snaps = sort {$a->start_time cmp $b->start_time}
         $ec2->describe_snapshots(-filter => {'tag:Name'=>'modENCODE public data root*'},
				  -restorable_by => 'all');
my $snapshot = $snaps[-1];

# get the most recent data server AMI
my $data_ami  = get_ami('modENCODE Data Image*');
my $browse_ami= get_ami('modENCODE Browser Image*');

print <<END;
snapshot = $snapshot
image = $data_ami
browse_image = $browse_ami
END
1;

exit 0;

sub get_ami {
    my $description = shift;
    my @data_amis =  $ec2->describe_images(-filter        => {'tag:Name'=>$description},
					   -executable_by => 'all');
    my %timestamps = map {$_=> get_root_snapshot_start($_)} @data_amis;
    my @sorted     = sort {$timestamps{$a} cmp $timestamps{$b}} keys %timestamps;
    return $sorted[-1];
}

sub get_root_snapshot_start {
    my $ami  = shift;
    my $root    = $ami->rootDeviceName;
    my ($block) = grep {$_->deviceName eq $root} $ami->blockDeviceMapping;
    my $snap    = $ec2->describe_snapshots($block->snapshotId);
    return $snap->start_time;
}

exit 0;

1;
