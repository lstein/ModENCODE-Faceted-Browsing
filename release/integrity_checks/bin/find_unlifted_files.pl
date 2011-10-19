#!/usr/bin/perl

# this script finds unlifted C. elegans GFF3 and SAM files
use strict;

use constant MANIFEST => '/modencode/data/MANIFEST.txt';
open my $fh,MANIFEST or die MANIFEST,": $!";
while (<$fh>) {
    chomp;
    next if /^#/;
    my ($id,$original,$symbolic) = split /\s+/;
    next unless $symbolic =~ /elegans/;
    next unless $original =~ /\.(gff|sam)/i;
    my $path = "/modencode/data/$original";
    test($id,$path);
}

exit 0;

sub test {
    my ($id,$path) = @_;
    my $head       = $path =~ /\.gz$/ ? "zcat '$path' | head -20"
	                              : "head -20 '$path'";
    my $result = system "$head | grep -q WS220";
    if ($result) {
	my $match = `$head | grep WS`;
	my ($b) = $match =~ /(WS\d+)/;
	printf "%-8d %50s %6s\n",$id,$path,$b;
    }
}
