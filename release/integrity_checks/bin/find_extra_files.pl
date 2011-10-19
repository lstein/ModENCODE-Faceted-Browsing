#!/usr/bin/perl

# This script reads the metadata.csv file and creates a list of
# files that can not be found in the filesystem, or which are
# found only after name transformation.

use strict;
use File::Find;
use File::Find;
use lib '/modencode/lib';
use MatchMeFile 'match_me';
use constant DATA => '/modencode/data/all_files';

my %FILES;
my @directories = @ARGV ? @ARGV : glob(DATA.'/volume*');
find(sub { return unless -f $_;
	   $FILES{$_} = $File::Find::name;},
     @directories);


my (%META,%FOUND);
my %seenit;

open my $meta,'<','/modencode/release/spreadsheet.csv' or die $!;
while (<$meta>) {
    next if /^DCC/;
    chomp;
    next if $seenit{$_}++;
    my ($id,undef,$filename) = split "\t";
    $META{$filename} = $id;
}

for my $filename (sort keys %FILES) {
    my ($id) = $filename =~ /^(\d+)_/;
    my ($match,$explanation) = match_me($filename,$id,\%META);
    $FOUND{$explanation}{$filename} = $match;
}

print "## these are files that are found in the filesystem, but not in spreadsheet.csv\n\n";
for my $reason (sort keys %FOUND) {
    next if $reason eq 'FOUND';
    print "** $reason **\n";
    for my $filename (sort {$a <=> $b} keys %{$FOUND{$reason}}) {
	printf "   %-80s   %-80s\n",$filename,$FOUND{$reason}{$filename};
    }
    print "\n";
}
exit 0;

