#!/usr/bin/perl

use strict;
use File::Basename 'basename';
use File::Find;

# this will add accession numbers to files that need them
@ARGV or die "Usage: fix_names.pl /path/to/directory\n";

my $directory = shift;

use constant MANIFEST => '/modencode/data/MANIFEST.txt';
open my $mf,MANIFEST or die MANIFEST,": $!";
my %Accessions;
while (<$mf>) {
    chomp;
    my ($accession,$physical_file) = split /\s+/;
    my $base = basename($physical_file);
    $Accessions{$base} = $accession;
    $Accessions{"$base.gz"} = $accession;
    $Accessions{"${accession}_$base"} = $accession;
    $Accessions{"${accession}_$base.gz"} = $accession;
}
close $mf;

find(sub {
    return unless -f $_;
    my $a = $Accessions{$_};
    unless ($a) {
	warn "$_: unknown\n";
	return;
    }
    return if /^${a}_/;
    warn "rename '$_','${a}_$_'\n";
    rename $_,"${a}_$_" or die "rename $_: $!";
     },
     $directory);

exit 0;
