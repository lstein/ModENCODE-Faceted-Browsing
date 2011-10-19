#!/usr/bin/perl

use strict;

my $list     = shift;
my $max_size = shift || 930;   # 930 gigabytes will just fill a 1 TB ext2 volume
$max_size   *= 1_073_741_824;  # convert gigabytes into bytes

open my $fh,'<',$list or die "$list: $!";
my $listno = 1;

open my $out,'>',"$list.$listno" or die "$list.$listno: $!";
print STDERR "Creating file $list.$listno\n";

my $total = 0;
while (<$fh>) {
    chomp;
    my $size = -s $_;
    $total  += $size;
    if ($total > $max_size) {
	$listno++;
	open $out,'>',"$list.$listno" or die "$list.$listno: $!";
	print STDERR "Total size = $total. Creating file $list.$listno\n";
	$total = $size;
    }
    print $out "$_\n";
}
