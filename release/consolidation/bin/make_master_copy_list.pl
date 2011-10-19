#!/usr/bin/perl

# this creates a text file that describes what we're going to do with each file

use File::Basename 'basename','dirname';
use File::Spec;

use constant ROOT     => '/modencode/data/';
use constant MANIFEST => ROOT . 'MANIFEST.txt';
use constant METADATA => ROOT . 'metadata.csv';
use constant UNLIFTED_ELEGANS => '/modencode/release/integrity_checks/results/unlifted_celegans_files.txt';

open my $manifest,MANIFEST or die MANIFEST,": $!";
my %Source;
while (<$manifest>) {
    my ($accession,$filename) = split /\s+/;
    my $basename = basename($filename);
    my $path     = File::Spec->catfile(ROOT,$filename);
    $Source{$basename} = [$path,-s $path];
}
close $manifest;

open my $metadata,"sort -n ".METADATA."|" or die METADATA,": $!";
my %Meta;
while (<$metadata>) {
    chomp;
    next if /^DCC/;
    my ($accession,$filename,undef,undef,$format,$organism) = split "\t";
    {
	local $_ = $format;
	my $form =  /raw/   ? 'raw'
	    :/fastq/ ? 'raw'
	    :/sam/   ? 'signal'
	    :/gff/   ? 'interpreted'
	    :/wiggle/? 'signal'
	    :/GEO/   ? 'raw'
	    :'';
	$Meta{$filename}={format   => $form,
			  organism => $organism,
			  accession=> $accession,
	};
    }
}
close $metadata;


open my $unlifted,UNLIFTED_ELEGANS or die UNLIFTED_ELEGANS,": $!";
my %Unlifted;
while (<$unlifted>) {
    chomp;
    my ($accession,undef,$build) = split /\s+/;
    $Unlifted{$accession} = $build;
}
close $unlifted;

my @sorted_files = sort {
    $Meta{$a}{organism} cmp $Meta{$b}{organism}
    ||
    $Meta{$a}{format}  cmp $Meta{$b}{format} } keys %Meta;

for my $file (@sorted_files) {
    my ($path,$size) = @{$Source{$file}};  # if we crash here, then something is out of sync between MANIFEST and metadata.

    my $organism    = $Meta{$file}{organism};
    my $format      = $Meta{$file}{format};
    my $accession   = $Meta{$file}{accession};

    my $dest        = $file;
    unless ($dest =~ /^${accession}_/) {
	$dest = "${accession}_$dest";
    }

    if (my $build = $Unlifted{$accession}) {
	$build = lc($build);
	my $orig = $dest;
	$dest =~ s/ws\d+/$build/ig;
    }

    my $needs_gzip = 0;
    unless ($dest =~ /\.(gz|zip|bz2|z)$/i) {
	$needs_gzip = 1;
    }
    $dest =~ s/\.(FASTQ|GFF3|WIG|PAIR)/'.'.lc($1)/e;
    $dest =~ s/^${accession}_${accession}/$accession/;  # get rid of duplicate accessions

    print join("\t",$organism,$format,$path,$dest,$size,$needs_gzip),"\n";
}
