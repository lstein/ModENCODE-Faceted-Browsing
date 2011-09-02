#!/usr/bin/perl

use strict;
use warnings;
use File::Path;
use File::Spec;
use File::Basename 'basename','dirname';
use JSON;
use CGI;
use URI::Escape;

use constant DATA_ROOT => '/modencode/data';
use constant MANIFEST  => File::Spec->catfile(DATA_ROOT,'MANIFEST.txt');

#Printing the HTML header
header();

my $cgi = new CGI;
my $idList = $cgi->param("download");

#Parsing the accessionIDs and putting them into an array
my %seenit;
my @AccessionId = grep {!$seenit{$_}++} split(',', $idList);

my $Database = read_manifest(MANIFEST);

my %DataFiles;
my @found_accessions = grep {$Database->{$_}} @AccessionId;

for my $id (@found_accessions) {
    my $records        = $Database->{$id} or next;
    my @filespecs;

    for my $r (@$records) {
	my $original_name = basename($r->{original});
	my $semantic_name = basename($r->{semantic});

	my $semantic_dir       = File::Spec->catfile(DATA_ROOT,dirname($r->{semantic}));
	my $data_directory     = File::Spec->catfile(DATA_ROOT,dirname($r->{original}));

	my $type = get_type($r->{semantic});

	my $filespec = {
	    id       => $id,
	    rpath    => $semantic_dir,
	    rname    => $semantic_name,
	    filename => $original_name,
	    type     => $type,
	    size     => -s File::Spec->catfile(DATA_ROOT,$r->{original}) || 0,
	};
	push @filespecs,$filespec;
    }
    $DataFiles{'modEncode_'.$id} = \@filespecs;
}
$DataFiles{idList} = [map {{id=>$_}} @found_accessions];
my $jsonString = to_json(\%DataFiles);

for my $id (@found_accessions) {
    createDiv($id);
}

#Creating a div that will contain the totalsize and the download button 
print ("<div id=\"totalSize\" name=\"0\"></div>");
print ("<div id=\"checkout\"></div>");

#Calling the startControl function inside controller.js and passing it the JSON string
print "<script language='javascript' type='text/javascript'>startControl('$jsonString')</script>";
print ('</div><div id="finished">Your files are now downloading...</div></body>');

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

sub get_type {
    my $semantic_name = shift;
    local $_ = $semantic_name; # cut down on typing
    return 
	 m!/(alignment_sam|raw-array-file[^/]*|raw-seqfile[^/]*)/!   ? 'raw'
	:m!/(computed-peaks[^/]+|gene-model[^/]*)/!                   ? 'interpreted'
	:m!/[^/]*wiggle[^/]*!                                        ? 'signal'
	:'interpreted';
}

#This sub takes in an accessionID and creates divs for the title and table. The div names should be self-explanatory
sub createDiv {
    my $id = shift;
    my $hyperText = qq{<div id="$id" class="container">
			<div id="$id-title" class="title"></div>
			<div id="$id-raw" class="subheader"></div>
			<div id="$id-signal" class="subheader"></div>
			<div id="$id-interpreted" class="subheader"></div></div>
			<p><p><p>};
    print $hyperText;
}

#This sub creates a HTML header for the webpage and prints it
sub header {
	my $head = qq{<head>
			<title>Modencode FTP Server</title>
			<link rel="stylesheet" type="text/css" href="/css/filefinder.css" />
			<script type="text/javascript" src="/js/jquery.js"></script>
			<script type="text/javascript" src="/js/filefinder/controller.js"></script>
			<script type="text/javascript" src="/js/jquery-ui-1.8.15.custom.min.js"></script>
		</head>
              <body>
		<div class="header">
	    <h1><a href="www.modencode.org"><img src="http://www.modencode.org/img/modENCODE_logo_small.png" height="60" align="middle" border="0"></a>
	      Download modENCODE Data Sets</h1>
	</div><p><p>
	<div id="fileMenu">};
	#Printing the HTML content type header
	print "Content-type: text/html\n\n";
	#Printing the HTML
	print ($head);
}

