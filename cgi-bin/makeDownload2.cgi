#!/usr/bin/perl

use strict;
use URI::Escape;
use File::Path 'remove_tree';
use CGI;

$SIG{INT} = $SIG{TERM} = \&cleanup();

#The name of the session folder is passed in from JavaScript
my $cgi = new CGI;
my $id = $cgi->param("id");	
$id =~ /^session\d+$/           or die "invalid session ID passed: $id";

#Opening the idList file which contains the name of the tarball to be generated
open (FILE, "</tmp/$id/idList") or print_error_and_exit();

my @downloadName = <FILE>;
close FILE;	
#Removing the file so that it does not get downloaded
unlink "/tmp/$id/idList" or warn "Could not unlink /tmp/$id/idList";	
chdir "/tmp/$id";

#Specifying the MIME type so that the browser downloads 
print "Content-Type:application/x-download\n"; 
print "Content-Disposition:attachment;filename=$downloadName[0].tar.gz\n\n";

#Streaming the tarball while it is being made 
#Options/Characters
#	z = archive
#	c = compressed
#	h = dereference symbolic links and get the actual files
#	* = no output argument is given so it streams to stdout
#	-| Pipe connecting stdout back to script/download, if this was not there then it would create the 
#	   tarball and then throw it for download, this way it streams it "live" 
open my $datastream, '-|', "tar zch *" or die;
while (<$datastream> ) {
	print;
}

#Recursively deleting the session folder and all symbolic links within
END { cleanup() }

exit 0;

sub cleanup {
    if ($id && -e "/tmp/$id") {
	chdir '/';
	remove_tree("/tmp/$id");
    }
}

sub print_error_and_exit {
    print CGI->header;
    print CGI->start_html(-onLoad=>'alert("Your download session has expired. Please try again.")');
    print "<button onClick='history.go(-1)'>Go Back</button>";
    print CGI->end_html;
    exit 0;
}
