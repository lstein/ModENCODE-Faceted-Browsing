#!/usr/bin/perl 
use strict;
use warnings;
use File::Basename;
#

my $INPUT_SPREADSHEET =  $ARGV[0]; # must be a spreadsheet 
my $OUTPUT_SPREADSHEET =  $ARGV[1]; # must be a spreadsheet 
my $VERBOSE =  $ARGV[2]; # verbose ( hidden and optional ) 

if ( @ARGV < 2 ) {
   print "\n";
   print "\na template for fixing inconsisteny metadata for a submission.";
   print "\n\nusage: perl " . basename($0) . " [ FILE_1 ] [ FILE_2 ] ";
   print "\n\tFILE_1\tinput spreadsheet file";
   print "\n\tFILE_2\toutput spreadsheet file";
   print "\n\n";
   exit (0);
}

open SPREADSHEET, "<" , $INPUT_SPREADSHEET || die ;
open FHO, ">" , $OUTPUT_SPREADSHEET || die ;
my $src_str;
my $dest_str;

while (<SPREADSHEET>) {
   chomp;
   my @fields=split /\t/, $_;
   my $ID = $fields[0];
   my $filePath = $fields[3];

   if ($fields[0] =~ /DCC/){
      print FHO join("\t", @fields) . "\n";
      next;
   }
   my $str;

=head

1       DCC id
2       Title
3       Data File
4       Data Filepath
5       Level 1 <organism>
6       Level 2 <Target>
7       Level 3 <Technique>
8       Level 4 <File Format>
9       Filename <Factor>
10      Filename <Condition>
11      Filename <Technique>
12      Filename <ReplicateSetNum>
13      Filename <ChIP>
14      Filename <label>
15      Filename <Build>
16      Filename <Modencode ID>
17      Uniform filename
18      Extensional Uniform filename
19      factor
20      Strain
21      Cell Line
22      Devstage
23      Tissue
24      other conditions
25      PI

NOTE: 
  column 5 and 15 should be the same  ( species ) 

=cut 

   if ($ID == 4715)  {
      my $counter = 0;

      foreach my $c (@fields) {
        $counter++;

   	if (defined $VERBOSE) {
   	   $str = "********** [ " . $counter . " ]";
   	} else {
   	   $str = "";
   	}

        if ($counter > 4) { 
           #$c =~ s//$str/g;
        } 
      }
      print "\n" . join("\t", @fields) . "\n";
   }

   print FHO join("\t", @fields) . "\n";
}
close SPREADSHEET;
close FHO;



