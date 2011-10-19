#!/usr/bin/perl

use strict;
use URI::Escape;
use CGI;
use FindBin '$RealBin';
use lib "$RealBin/../lib";
use FacetedBrowsingUtils 'MODENCODE_DATA';

my $cgi = new CGI;
print $cgi->header ( );
#Download parameters are passed in the form ,file1Name&DirectoryPath^typeofFile(e.g.raw),file2Name..
#Decoding special characters
my $information = uri_unescape ($cgi->param("selected"));

#Splitting files and putting them into an array (Each file/element passed in is separated by a ,)
my @passedParams = split(',', $information);

#First element in the array is useless
shift (@passedParams);

#Generating a unique session ID to avoid collision (if two or more people are using it at the same
#time. Collision chances are 1/1000
my $range = 10000000;
my $random_number = int(rand($range));

#Making a directory where the symbolic links will be created
mkdir "/tmp/session$random_number" or die $!;
chdir "/tmp/session$random_number";

my @parameters;	
#This variable will be the name of the tarball that will be generated
my $datasetIDs='modEncode_';

#Iterating through each element, creating required directory structure and populating it with symbolic links to
#files that are to be downloaded
# TO DO: instead of encoding filenames & paths in this awkward way, convert to JSON
foreach my $temp(@passedParams) {

    #Splitting the filename from the directory path and file type
    my @tempArray = split('&',$temp);

    #Pushing the filename 	
    push (@parameters, $tempArray[0]);

    #Splitting the directory path and the file type (\ in front of the ^ because we need to escape it)
    my @secondTemp = split('\^',$tempArray[1]);

    #Pushing the directory path and file type
    push (@parameters, $secondTemp[0]);
    push (@parameters, $secondTemp[1]);

    #Finding out the id and the file from the file type parameter which is in the format acessionID-fileType e.g. 21-raw 
    my @typeID = split ('\-',$parameters[2]);
    check_types(@typeID);

    #Checking if the ID is not already part of the name, if not then adding it to the string	
    if (!($datasetIDs =~ /$typeID[0]/)) {
	$datasetIDs .= $typeID[0];
	$datasetIDs .= '_';
    }
    #Create the directory for the acessionId if it does not exist
    if (!(-d "/tmp/session$random_number/modEncode_$typeID[0]")) {
	mkdir "/tmp/session$random_number/modEncode_$typeID[0]" or die $!;
    }	
    create_readme("/tmp/session$random_number/modEncode_$typeID[0]");
    #Checking the filetype and seeing if a subdirectory for that filetype exists, if it does not then create it
    if ($typeID[1] eq "raw") {
	if (!(-d "/tmp/session$random_number/modEncode_$typeID[0]/raw_data_files")) {
	    mkdir "/tmp/session$random_number/modEncode_$typeID[0]/raw_data_files" or die $!;
	}
	chdir "/tmp/session$random_number/modEncode_$typeID[0]/raw_data_files";
    } elsif ($typeID[1] eq "signal") {
	if (!(-d "/tmp/session$random_number/modEncode_$typeID[0]/signal_data_files")) {
	    mkdir "/tmp/session$random_number/modEncode_$typeID[0]/signal_data_files" or die $!;
	}
	chdir "/tmp/session$random_number/modEncode_$typeID[0]/signal_data_files";
    } else {
	if (!(-d "/tmp/session$random_number/modEncode_$typeID[0]/interpreted_data_files")) {			
	    mkdir "/tmp/session$random_number/modEncode_$typeID[0]/interpreted_data_files" or die $!;
	}
	chdir "/tmp/session$random_number/modEncode_$typeID[0]/interpreted_data_files";
    }

    #Creating the symbolic link	
    check_files($parameters[0]);
    check_paths($parameters[1]);
    symlink("$parameters[1]/$parameters[0]", "$parameters[0]");

    #Changing back into the session directory	
    chdir "/tmp/session$random_number/";

    #Removing all elements from the array	
    # LS (this is certainly crazy and needs fixing)
    shift (@parameters);
    shift (@parameters);
    shift (@parameters);
}

#Removing the last _ in the tarball name
chop ($datasetIDs);

#Writing out the name of the tarball to a file called idList which is in the session folder
open (FILE, ">/tmp/session$random_number/idList");
	print FILE ($datasetIDs);
close FILE;
#Passing the session folder name back to the JavaScript
print ("session$random_number");


exit 0;

sub check_types {
    foreach (@_) {
	m/^\w+$/ or die "invalid parameter: $_";
    }
}

sub check_files {
    foreach (@_) {
	# no slashes
	m!/!     and die "invalid filename: $_";
	# only non-whitespace
	m/^\S+$/ or  die "invalid filename: $_";
	length() < 255 or die "invalid filename: $_";
    }
}

sub check_paths {
    my $root = MODENCODE_DATA;
    foreach (@_) {
	m!/\.\./!          and die "invalid path: $_";
	m!^/!              or die "invalid path: $_";
	m!$root! or die "invalid path: $_";
    }
}

sub create_readme {
    my $dir = shift;
    my $source = "$dir/README";
    my $target = '/modencode/data/README';
    symlink($target,$source);
}
