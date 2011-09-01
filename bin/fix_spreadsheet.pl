#!/usr/bin/perl

# fix Zheng's spreadsheet to account for various issues
use strict;

use FindBin '$Bin';
use lib "$Bin/../lib";
use FacetedBrowsingUtils;

my (%seenline,$firstline,%records);
while (<>) {
    chomp;

    next if $seenline{$_}++;
    next unless $firstline++;

    my ($id,$title,$original_name,$path,
	$organism,$target,$technique,
	$format,$factor,$condition,
	undef,$repset,$chipno,$chiprole,$build,
	$submission,undef,
	undef,undef,undef,undef,$stage,undef,undef,
	$pi) = split ("\t");

    $organism   = fix_organism($organism);
    $target     = fix_target($target);
    $stage      = fix_stage($stage);
    $factor     = fix_factor($factor);
    $condition  = fix_condition($condition);
    $pi         = fix_pi($pi);
    $build      = fix_build($build);
    $repset     = defined $repset ? "Rep-".($repset+1) : '';
    $chiprole ||= '';
    
    my $uniform_filename = join (':',$factor,$condition,$technique,$repset,$chiprole,$build,"modENCODE_$id");
    
    my %hash = (id            => $id,
		title         => $title,
		original_name => $original_name,
		directory     => join("/",map {s/\s+/-/g; $_} ($organism,$target,$technique,$format)),
		path          => $path,
		organism      => $organism,
		target        => $target,
		technique     => $technique,
		'format'      => $format,
		factor        => $factor,
		condition     => $condition,
		stage         => $stage,
		submission    => $submission,
		uniform_filename => $uniform_filename,
		pi            => $pi,
		repset        => $repset,
		build         => $build,
		category      => find_category($pi,$technique,$target),
	);
    $records{$original_name} = \%hash;
}

my %names;
for my $o (keys %records) {
    my $ext = get_extension($records{$o}{format});
    $names{$records{$o}{uniform_filename}.$ext}{$o}++;
}

# find and fix uniform names that are not unique
for my $r (keys %names) {
    my @orig = keys %{$names{$r}};
    if (@orig > 1) {
	$r =~ s/\.\w+$//; # strip extension
	my @uniform = uniquify($r,@orig);
	foreach (@orig) {
	    $records{$_}{uniform_filename} = shift @uniform;
	}
    }
}

# assign proper filetype extension
for my $o (keys %records) {
    my $uniform = $records{$o}{uniform_filename};
    my $orig    = $records{$o}{original_name};
    my $format  = $records{$o}{format};
    $uniform   .=  get_extension($format);
    if ($orig =~ /\.(gz|gzip)$/i) {
	$uniform .= ".gz";
    } elsif ($orig =~ /\.zip$/i) {
	$uniform .= ".zip";
    } elsif ($orig =~ /\.(bz2|bunzip2)$/i) {
	$uniform .= ".bz2";
    } elsif ($orig =~ /\.z$/i) {
	$uniform .= '.z';
    }
    $uniform =~ tr/ /-/;  # no spaces allowed
    $records{$o}{uniform_filename} = $uniform;
}

print join("\t",
	   'DCC id',
	   'Original Name',
	   'Directory',
	   'Uniform filename',
	   'File Format',
	   'Organism',
	   'Target',
	   'Technique',
	   'Factor',
	   'Stage',
	   'Condition',
	   'ReplicateSetNum',
	   'Build',
	   'Principal Investigator',
	   'Category'),"\n";

for my $o (sort {$records{$a}{id}<=>$records{$b}{id}} keys %records) {
    my $r = $records{$o};
    print join ("\t",@{$r}{qw(id original_name directory uniform_filename format organism target technique factor stage condition repset build pi category)}),"\n";
}
		
exit 0;

sub get_extension {
    my $format = shift;
    return $format =~ /sam/i    ? '.sam'
	:$format =~ /bam/i    ? '.bam'
	:$format =~ /gff/i    ? '.gff3'
	:$format =~ /wiggle/i ? '.wig'
	:$format =~ /cel/i    ? '.CEL'
	:$format =~ /pair/i   ? '.pair'
	:$format =~ /agilent/i? '.agilent'
	:$format =~ /fast/i   ? '.fastq'
	:$format =~ /geo/i    ? '.txt'
	: '.txt';
}

sub uniquify {
    my ($uniform,@original_names) = @_;
    my $prefix = find_common_prefix(@original_names);
    my $suffix = find_common_suffix(@original_names);
    my @unique;
    foreach (@original_names) {
	s/^$prefix//;
	s/$suffix$//;
	push @unique,"$uniform:$_";
    }
    return @unique;
}

sub find_common_prefix {
    my @w = @_;
    my ($shortest) = sort {$a<=>$b} map {length} @w;
    my $i=1;
    while ($i<=$shortest) {
	my @substr = map {substr($_,0,$i)} @w;
	my %u      = map {$_=>1} @substr;
	last if keys %u>1;
	$i++;
    }
    return substr($w[0],0,$i-1);
}

sub find_common_suffix {
    my @w = @_;
    my ($shortest) = sort {$a<=>$b} map {length} @w;
    my $i = 1;
    while ($i<=$shortest) {
	my @substr = map {substr($_,length($_)-$i,$i)} @w;
	my %u      = map {$_=>1} @substr;
	last if keys %u>1;
	$i++;
    }
    $i--;
    return substr($w[0],length($w[0])-$i,$i);
}
