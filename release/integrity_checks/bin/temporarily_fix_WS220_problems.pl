#!/usr/bin/perl

# this patches the spreadsheet so that it doesn't lie about WS220 builds
use strict;

my $incorrect_files = '/modencode/release/integrity_checks/results/unlifted_celegans_files.txt';
my $spreadsheet     = '/modencode/data/metadata.csv';

open my $bad,$incorrect_files or die "$incorrect_files: $!";
my %Builds;
while (<$bad>) {
    chomp;
    my ($accession,$file,$build) = split /\s+/;
    $Builds{$accession} = $build;
}
close $bad;

open my $in,'<',$spreadsheet        or die "$spreadsheet: $!";
open my $out,'>',"$spreadsheet.new" or die "$spreadsheet.new: $!";
while (<$in>) {
    my @fields   = split "\t";
    my $build    = $Builds{$fields[0]} or next;
    my $original = $fields[12];
    $original    =~ s/^Cele_//;
    print STDERR "Was $_\n";
    s/$original/$build/gi;
    print STDERR "Now $_\n";
} continue {
    print $out $_;
}
