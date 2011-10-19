#!/usr/bin/perl

# This script reads the metadata.csv file and creates a list of
# files to be copied, for purposes of sorting files into volumes
# organized by organism and file format.

# The output is suitable for passing to copy.pl (which does an rsync)
# or partitioning into sublists of a certain maximum size by
# partition_list_by_size.pl

use strict;
use FindBin '$Bin';
my $organism = shift;
my $format   = shift;

my %meta;
open my $meta,'<','/modencode/data/metadata.csv' or die $!;
while (<$meta>) {
    chomp;
    my (undef,$filename,undef,undef,$format,$organism) = split "\t";
    {
	local $_ = $format;
	my $form =  /raw/   ? 'raw'
                   :/fastq/ ? 'raw'
		   :/sam/   ? 'signal'
		   :/gff/   ? 'interpreted'
		   :/wiggle/? 'signal'
		   :/GEO/   ? 'interpreted'
		   :'';
	$meta{$filename}={format=>$form,organism=>$organism};
    }
}
close $meta;

my (%sizes,%count);
open my $unique,"$Bin/../unique_names.txt" or die $!;
while (<$unique>) {
    chomp;
    my ($name,$size,undef,$location) = split "\t";
    (my $stripped = $name) =~ s/^\d+_//;
    (my $nosuffix = $name) =~ s/\.gz$//;
    my $record = $meta{$name} || $meta{$stripped} || $meta{"$stripped.gz"} || $meta{"$name.gz"} || $meta{$nosuffix};
    if ($name =~ /^(.+)_\d+(\.fastq.+)/) {
	$record ||= $meta{"$1$2"}||$meta{"$1$2.gz"};
    }
    unless ($record) {
	warn "$name missing\n";
	next;
    }
    next unless $record->{organism} =~ /$organism/ && $format eq $record->{format};
    print "$location/$name\n";
}

