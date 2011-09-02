#!/usr/bin/perl

# generate database file for use with faceted browsing
# NOTE -- this will invoke fix_spreadsheet.pl to fix up the fields and
# filenames

use strict;
use warnings;

use JSON;
use FindBin '$Bin';
use lib "$Bin/../lib";
use FacetedBrowsingUtils;
use LWP::Simple 'get','getprint';
use Text::ParseWords 'shellwords';
use Bio::Graphics::FeatureFile;
use constant BROWSER => 'http://modencode.oicr.on.ca/fgb2/gbrowse/';
use constant SOURCES => [qw(fly worm fly_ananas fly_dmoj fly_dp fly_simul fly_virilis fly_yakuba)];

use constant DEBUG=>0;

my %DATA;

if (DEBUG) {
    open FH,"$Bin/../data/modencode-22August2011.csv" or die $!;
} 
else {
    # This opens a pipe named FH which fetches the CSV database, cleans it up (fixes capitalization etc)
    # and returns a new CSV.
    # Location of METADATA_URL is currently hard-coded in lib/FacetedBrowsingUtils.pm
    unless (open FH, '-|') { # in child
	open FIX,"|$Bin/fix_spreadsheet.pl";
	select \*FIX;
	getprint(METADATA_URL);
	exit 0;
    }
}

while (<FH>) {
    chomp;
    my ($submission,$original_name,$directory,$uniform_filename,$format,
	$organism,$target,$technique,$factor,$stage,$condition,
	$replicate_set,$build,$pi,$category) = split ("\t");

    next if $submission eq 'DCC id';
    next unless $submission;

    my @conditions;
    for my $c (split '#',$condition) {
	my ($key,$value) = split '=',$c;
	push @conditions,($key,$value) if (defined $key && defined $value);
    }

    my %conditions = @conditions;
    my $label    = join(';',$factor,values %conditions,$technique);

    $DATA{$submission} = {
	submission => $submission,
	label      => $label,
	organism   => $organism,
	target     => $target,
	technique  => $technique,
	factor    => $factor,
	category  => $category,
	type      => 'data set',
	$pi ? (principal_investigator => $pi) : (),
	@conditions,
    }
}

# add scan data from modencode browser
my (%seenit,%id2track);
for my $source (@{SOURCES()}) {
    my $url  = BROWSER . "$source?action=scan";
    my $scan = get($url) or next;
    my $ff   = Bio::Graphics::FeatureFile->new(-text=>$scan);
    for my $l ($ff->labels) {
	my @select = shellwords($ff->setting($l  => 'select'));      # tracks with subtracks
	my @ds     = shellwords($ff->setting($l  => 'data source')); # tracks without subtracks
	for my $s (@select) {
	    my ($subtrack,$id) = split ';',$s;
	    $id2track{$id}{"$source/$l/$subtrack"}++;
	    $seenit{"$source/$l/$id"}++;
	}
	for my $id (@ds) {
	    $id2track{$id}{"$source/$l"}++ unless $seenit{"$source/$l/$id"}++;
	}
    }
}
for my $id (keys %id2track) {
    next unless $DATA{$id};
    my @tracks = keys %{$id2track{$id}};
    $DATA{$id}{Tracks} = \@tracks;
}

my @ids   = sort {$a<=>$b} keys %DATA;
my @items = map {$DATA{$_}} @ids;

my $json  = JSON->new;
print $json->pretty->encode({items=>\@items,
			     types => {'data set' => {pluralLabel=>'data sets'}}
			    });

exit 0;

