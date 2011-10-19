#!/usr/bin/perl

use strict;
use constant ARGC_LIMIT => 500;

my $files = shift;
my $dest  = shift;

die "bad destination" unless -d $dest && -w $dest;
open my $fh,$files or die "$files: $!";
my @files;
while (<$fh>) {
    chomp;
    next unless /\S/;
    push @files,$_;
    if (@files >= ARGC_LIMIT) {
	print STDERR "rsync ",scalar @files," files to $dest\n";
	system 'rsync','-avv',@files,$dest;
	@files = ();
    }
}
print STDERR "rsync ",scalar @files," files to $dest\n";
system 'rsync','-avv',@files,$dest if @files;

exit 0;
