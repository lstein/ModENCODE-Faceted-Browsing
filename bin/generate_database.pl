#!/usr/bin/perl

# generate database file for use with faceted browsing

use strict;
use warnings;

use JSON;
use LWP::Simple 'get','getprint';
use Text::ParseWords 'shellwords';
use Bio::Graphics::FeatureFile;
use FindBin '$Bin';
#use constant CSV     => 'http://localhost/testing/modencode.csv';
use constant CSV     => 'file:./data/modencode-22August2011.csv';
use constant BROWSER => 'http://modencode.oicr.on.ca/fgb2/gbrowse/';
use constant SOURCES => [qw(fly worm)];

use constant DEBUG=>1;

my %DATA;

if (DEBUG) {
    open FH,"$Bin/../data/modencode-22August2011.csv" or die $!;
} 
else {
    unless (open FH, '-|') { # in child
	getprint(CSV);
	exit 0;
    }
}

while (<FH>) {
    chomp;
    my ($id,$title,$file,$path,
	$organism,$target,$technique,
	$format,$factor,$condition,
	undef,undef,undef,undef,undef,
	$submission,$uniform_filename,
	undef,undef,undef,undef,undef,undef,undef,
	$pi) = split ("\t");

    next if $id eq 'DCC id';
    next unless $id;

    my @conditions;
    for my $c (split ';',$condition) {
	my ($key,$value) = split '_',$c;
	if ($key eq 'Compound' && $value =~ /mM/) {
	    $value .= ' salt';
	} elsif ($key eq 'Developmental-Stage') {
	    $value  = fix_stage($value);
	}
	push @conditions,($key,$value);
    }

    $organism = fix_organism($organism);
    $factor   = fix_factor($factor);
    $target   =~ tr/-/ /;
    $pi       =~ s/^(\w)\w+\s*(\w+)/$2, $1./;

    $DATA{$id} = {
	submission => $submission,
	label      => $title,
	organism   => $organism,
	target     => $target,
	technique  => $technique,
	factor    => $factor,
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

sub fix_organism {
    my $org = shift;
    return $org =~ /^Cele/ ? 'C. elegans'
	  :$org =~ /^Dmel/ ? 'D. melanogaster'
	  :$org =~ /^Dmoj/ ? 'D. mojavensis'
	  :$org =~ /^Dyak/ ? 'D. yakuba'
	  :$org =~ /^Dana/ ? 'D. ananassae'
	  :$org =~ /^Dpse/ ? 'D. pseudoobscura'
	  :$org =~ /^Dsim/ ? 'D. simulans'
	  :$org =~ /^Dvir/ ? 'D. virilis'
	  :$org;
}

sub fix_stage {
    my $stage = shift;
    $stage   =~ tr/_/ /;  # get rid of underscores
    $stage   =~ s/embryo/Embryo/;
    $stage   =~ s/Embyro/Embryo/;
    $stage   =~ s/^E(?=\d)/Embryo /;
    $stage  .= ' h' if $stage =~ /^Embryo.*\d$/;
    $stage   =~ s/hr$/h/;
    $stage   =~ s/(\d)h$/$1 h/;
    $stage   =~ s/^DevStage://;
    $stage   .= ' stage larvae' if $stage =~ /L\d/;
    $stage   =~ s/Larvae? stage larvae/stage larvae/i;
    $stage   =~ s/^late/Late/;
    $stage   =~ s/^early/Early/;
    $stage   =~ s/^larva L(\d)/L$1/i;
    $stage   =~ s/^yAdult/Young adult/i;
    $stage   =~ s/(\d)\s?hr?/$1 hr/g;
    $stage   =~ s/larvae?(.+stage larvae)/$1/;
    $stage   =~ s/\s+\d+dc//i;
    $stage   =~ s/embryo\b/Embryos/i;
    $stage   =~ s/stage stage/stage/;
    $stage   =~ s/WPP/White prepupae (WPP)/;
    return ucfirst($stage);
}

sub fix_factor {
    my $factor = shift;
    $factor =~ s!^(H\d+[A-Z]\d+)(\w+)!$1\l$2!;
    $factor =~ s!H4tetraac!H4acTetra!;
    $factor =~ s!Trimethylated Lys-4 o[fn] histone H3!H3K4me3!i;
    $factor =~ s!Trimethylated Lys-9 o[fn] histone H3!H3K9me3!i;
    $factor =~ s!Trimethylated Lys-36 o[fn] histone H3!H3K36me3!i;
    $factor =~ s!SU\(HW\)!Su(Hw)!i;
    return $factor;
}
