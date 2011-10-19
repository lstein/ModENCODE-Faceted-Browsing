#!/usr/bin/perl

use strict;
use File::Find;
my %FILES;

my @directories = </modencode/data/all_files/volume*>;
find(\&tabulate,@directories);

for my $fname (sort keys %FILES) {
    # ignore compressed versions if uncompressed version exists
    next if $fname =~ /^(.+)\.gz$/ && $FILES{$1};
    print join("\t",$fname,$FILES{$fname}{size},$FILES{$fname}{mtime},$FILES{$fname}{dir}),"\n";
}

exit 0;

sub tabulate {
    return unless -f $_;
    my $mtime = (stat(_))[9];
    my $size  = (stat(_))[7];
    if (!exists $FILES{$_} or ($FILES{$_}{mtime} < $mtime)) {  # newer version
	$FILES{$_} = {mtime=> $mtime,
		      size => $size,
		      dir  => $File::Find::dir}
    }
}
