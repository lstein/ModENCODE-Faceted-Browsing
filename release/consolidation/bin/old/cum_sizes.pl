#!/usr/bin/perl

use strict;
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
open my $unique,"$ENV{HOME}/unique_names.txt" or die $!;
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
    $sizes{$record->{organism}}{$record->{format}} += $size;
    $count{$record->{organism}}{$record->{format}}++;
}

for my $organism (sort keys %sizes) {
    for my $format (sort keys %{$sizes{$organism}}) {
	print join("\t",$organism,$format,int($sizes{$organism}{$format}/1_073_741_824+0.5),$count{$organism}{$format}),"\n"
    }
}


