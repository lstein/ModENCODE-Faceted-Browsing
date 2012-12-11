#!/usr/bin/perl

# this creates a file suitable for use as /modencode/DATA_SNAPSHOTS.txt
use strict;

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

setup_credentials();
my $ec2         = VM::EC2->new();
my @snapshots   = sort {$a->description cmp $b->description} $ec2->describe_snapshots(-owner=>296402249238,-filter=>{description=>'modENCODE*data, part*'});

# in case of duplicates, keep most recent
my %unique;
for my $s (@snapshots) {
    my $description = $s->description;
    my $date        = $s->startTime;
    if ($unique{$description}) {
	$unique{$description} = $s if $date gt $unique{$description}->startTime;
    } else {
	$unique{$description} = $s;
    }
}

for my $d (sort keys %unique) {
    print "$unique{$d}\t$d\n";
}
