#!/usr/bin/perl

# this creates a file suitable for use as /modencode/DATA_SNAPSHOTS.txt
use strict;

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

setup_credentials();
my $ec2         = VM::EC2->new();
my @snapshots   = sort {$a->description cmp $b->description} $ec2->describe_snapshots(-owner=>296402249238,-filter=>{description=>'modENCODE*data, part*'});

# remove "current" tag from them all
foreach (@snapshots) {$_->delete_tags('Current')}

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
    warn "Tagging $unique{$d}\n";
    $d =~ /^modENCODE ([A-Z])\. (\w+) (\w+) data, part (\d+)/;
    my $name = lc($1).substr($2,0,3).'-'.$3.'-'.$4;
    $unique{$d}->add_tags('Current' => scalar localtime);
    $unique{$d}->add_tags('Name'    => $name);
}
