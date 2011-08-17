#!/usr/bin/perl

# generate database file for use with faceted browsing

use strict;
use warnings;

use JSON;
use LWP::Simple 'get','getprint';
use Text::ParseWords 'shellwords';
use Bio::Graphics::FeatureFile;
use constant CSV     => 'http://localhost/testing/modencode.csv';
use constant BROWSER => 'http://modencode.oicr.on.ca/fgb2/gbrowse/';
use constant SOURCES => [qw(fly worm)];

my %DATA;

unless (open FH, '-|') { # in child
    getprint(CSV);
    exit 0;
}

while (<FH>) {
    chomp;
    my ($id,$title,$file,$path,
	$organism,$target,$technique,
	$format,$factor,$condition,
	undef,undef,undef,undef,undef,
	$submission) = split ("\t");
    next if $id eq 'DCC id';
    next unless $id;
    my @conditions;
    for my $c (split ';',$condition) {
	my ($key,$value) = split '_',$c;
	if ($key eq 'Compound' && $value =~ /mM/) {
	    $value .= ' salt';
	}
	push @conditions,($key,$value);
    }
    $DATA{$id} = {
	submission => $submission,
	label      => $title,
	organism   => $organism,
	target     => $target,
	technique  => $technique,
	factor    => $factor,
	type      => 'data set',
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

