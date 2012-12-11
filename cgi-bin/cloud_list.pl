#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;
use File::Basename 'dirname','basename';
use CGI qw(:standard);

use constant DATA_ROOT => '/modencode/data';
use constant MANIFEST  => File::Spec->catfile(DATA_ROOT,'MANIFEST.txt');
use constant SNAPSHOTS => '/modencode/DATA_SNAPSHOTS.txt';

my $Database = read_manifest(MANIFEST);
my $Snaps    = read_snapshot_list(SNAPSHOTS);
my $idList = param("accessions");
my $urls   = param('urls');
my %seenit;
my @AccessionId = grep {!$seenit{$_}++} split(',', $idList);

my @found_accessions   = grep {$Database->{$_}}  @AccessionId;
my @missing_accessions = grep {!$Database->{$_}} @AccessionId;

print header('text/plain');
if ($urls) {
    print "## This is a list of download URLs corresponding to data files in the selected submissions.\n";
    printf "#%-4s %-50s\n",'ID','Url';
} else {
    print "## This information will help you locate the data files on the modENCODE Amazon Cloud Image\n";
    print "## and data snapshots. See http://data.modencode.org/modencode-cloud.html for more information.\n\n";
    printf "#%-4s %-15s %-20s %-50s\n",'ID','Snapshot','Volume','File';
}
for my $id (@found_accessions) {
    my $records        = $Database->{$id} or next;

    for my $r (@$records) {
	(my $original_name = $r->{original}) =~ s!^\./all_files/!!;
	my $basename       = basename($original_name);
	my $volname        = dirname($original_name);
	my $snap           = $Snaps->{$volname};
	my $url            = "ftp://data.modencode.org/all_files/$volname/$basename";
	if ($urls) {
	    printf "%5d %-50s\n",$id,$url;
	} else {
	    printf "%5d %-15s %-20s %-50s\n",$id,$snap,$volname,$basename;
	}
    }
}



exit 0;

sub read_manifest {
    my $manifest = shift;
    my %data;
    open my $f,$manifest or die "$manifest: $!";
    while (<$f>) {
	chomp;
	next if /^#/;
	my ($accession,$original_path,$semantic_path) = split "\t";
	foreach ($original_path,$semantic_path) {
	    die "Absolute path found in manifest at '$_'"    if m!^/!;
	    die "Double-dot path found in manifest at '$_'"  if m!^\.\.!;
	}
	push @{$data{$accession}},{original => $original_path,
				   semantic => $semantic_path};
    }
    close $f;
    return \%data;
}

sub read_snapshot_list {
    my $snapshots = shift;
    my %data;
    open my $f,$snapshots or die "$snapshots: $!";
    while (<$f>) {
	chomp;
	my ($snap,$description) = split "\t";
	my ($species,$type) = $description =~ / ([A-Z]\. \w+) (\w+) data/;
	my ($part)          = $description =~ /part (\d+)/;
	$part             ||= 1;
	$species           =~ s/^([A-Z])\. (\w{3}).+/lc($1).$2/e;
	my $vol = "$species-$type-$part";
	$data{$vol} = $snap;
    }
    return \%data;
}
