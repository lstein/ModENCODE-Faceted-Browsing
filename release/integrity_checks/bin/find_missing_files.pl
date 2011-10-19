#!/usr/bin/perl

# This script reads the metadata.csv file and creates a list of
# files that can not be found in the filesystem, or which are
# found only after name transformation.

use strict;
use File::Find;
use lib '/modencode/lib';
use MatchMeFile 'match_me';
use constant DATA => '/modencode/data/all_files';

my %FILES;
find(sub { return unless -f $_;
	   $FILES{$_} = $File::Find::name;},
     DATA);


my %FOUND;
my %seenit;

open my $meta,'<','/modencode/release/spreadsheet.csv' or die $!;
while (<$meta>) {
    next if /^DCC/;
    chomp;
    next if $seenit{$_}++;
    my ($id,undef,$filename) = split "\t";
    # the last argument allows match_me to return multiple hits;
    # only allowed case are the SRR files, which have the format SRR12345.fastq, SRR12345_1.fastq, SRR12345_2.fastq
    my $srr = $filename =~ /SRR\d+/;
    my ($match,$explanation) = match_me($filename,$id,\%FILES,$srr);

    my $matches;
    if (ref $match && ref $match eq 'ARRAY') {
	$matches = $match;
    } else {
	$matches = [$match];
    }

    $FOUND{$explanation}{$filename} = [$id,$_] foreach @$matches;
}

close $meta;

print "## these are files that are found in spreadsheet.csv, but not in filesystem\n\n";
for my $reason (sort keys %FOUND) {
    next if $reason eq 'FOUND';
    my $count = keys %{$FOUND{$reason}};
    print "** $reason ($count) **\n";
    for my $filename (sort {$FOUND{$reason}{$a}[0] <=> $FOUND{$reason}{$b}[0]} keys %{$FOUND{$reason}}) {
	printf "   %6d %-80s   %-80s\n",$FOUND{$reason}{$filename}[0],$filename,$FOUND{$reason}{$filename}[1];
    }
    print "\n";
}

exit 0;

