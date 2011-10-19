#!/usr/bin/perl

# this creates a file suitable for use as /modencode/DATA_SNAPSHOTS.txt
use strict;

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

setup_credentials();
my $ec2         = VM::EC2->new();
my @snapshots   = sort {$a->description cmp $b->description} $ec2->describe_snapshots(-owner=>296402249238,-filter=>{description=>'modENCODE*data from*'});
for my $s (@snapshots) {
    print $s,"\t",$s->description,"\n";
}
