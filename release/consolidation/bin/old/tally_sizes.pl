#!/usr/bin/perl

# idiot check that file sizes listed in file don't exceed limit
use strict;

my $grand_total;
while (@ARGV) {
    my $file = shift;
    open my $fh,$file;
    my $total = 0;
    while (<$fh>) {
	chomp;
	$total += -s $_;
    }
    print "$file size = ",int(0.5+$total/1_073_741_824)," GB\n";
    $grand_total += $total;
}

print "GRAND TOTAL = ",int(0.5+$grand_total/1_073_741_824)," GB\n";

