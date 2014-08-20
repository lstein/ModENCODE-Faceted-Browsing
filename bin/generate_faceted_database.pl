#!/usr/bin/perl

# generate database file for use with faceted browsing
# NOTE -- this will invoke fix_spreadsheet.pl to fix up the fields and
# filenames

use strict;
use warnings;

use JSON;
use FindBin '$RealBin';
use lib "$RealBin/../lib","$RealBin/../perl/lib/perl","$RealBin/../perl/lib/perl/5.10";
use FacetedBrowsingUtils;
use LWP::Simple 'get','getprint','mirror';
use Text::ParseWords 'shellwords';
use constant BROWSER => 'http://gbrowse.modencode.org/fgb2/gbrowse/';
use constant SOURCES => [qw(fly worm fly_ananas fly_dmoj fly_dp fly_simul fly_virilis fly_yakuba)];
use constant DEST    => "$RealBin/../htdocs/modencode.js";

my %DATA;

# Location of METADATA_URL and METADATA_FIXED is currently hard-coded in lib/FacetedBrowsingUtils.pm
my $mirror = '/modencode/release/metadata_mirror.csv';
mirror(METADATA_URL,$mirror);
unless (-e METADATA_FIXED && (-M METADATA_FIXED <= -M $mirror)) {
    open FH,"$RealBin/fix_spreadsheet.pl <$mirror| tee ".METADATA_FIXED."|" or die "Couldn't open pipe to fix raw spreadsheet: $!";
} else {
    open FH,METADATA_FIXED or die METADATA_FIXED,": $!";
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
    my $ff   = IniReader->read_string($scan);
    for my $l (keys %{$ff}) {
	my @select = shellwords($ff->{$l}{select});         # tracks with subtracks
	my @ds     = shellwords($ff->{$l}{'data source'});  # tracks without subtracks
	for my $s (@select) {
	    my ($subtrack,$id) = split ';',$s;
	    next unless defined $id;
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

open F,'>',DEST or die "Can't open ",DEST,": $!";
my $json  = JSON->new;
print F $json->pretty->encode({items=>\@items,
			       types => {'data set' => {pluralLabel=>'data sets'}}
			      });
print STDERR "Faceted database successfully updated\n";

exit 0;

package IniReader;

use base 'Config::INI::Reader';

sub can_ignore {
    my $self = shift;
    my $line = shift;
    return $line =~ /^\s*\#/ || $line =~ /^\s*$/;;
}
