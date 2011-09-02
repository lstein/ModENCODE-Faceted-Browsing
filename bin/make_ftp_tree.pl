#!/usr/bin/perl

# Create links from big-mongo data volumes to sorted hierarchical list, for
# convenient FTP browsing.

use strict;
use FindBin '$Bin';
use lib "$Bin/../lib";
use FacetedBrowsingUtils;
use File::Path 'make_path';
use File::Spec;
use File::Basename;
use File::Find;
use LWP::Simple 'getprint';

# Data file with metadata, filenames, etc. Can be a URL
#use constant CSV     => 'file:/var/www/spreadsheet.csv';
use constant CSV      => "file:$Bin/../data/modencode-22August2011.csv";

# this contains copies of make_ftp_tree.pl and README, for convenience of
# administrators and cloud users
use constant ROOT     => '/modencode';  

# This is the root of the anonymous FTP account
# top level links, such as D.melanogaster are found here
use constant DATA     => ROOT .'/data';

# This is where the terabyte volume mounts are
use constant ALL_FILES => 'all_files';
use constant FLAT      => DATA .'/'.ALL_FILES;

# volumes are mounted at /modencode/data/all_files/volume{1,2,3,4...}
use constant MNT      => FLAT . '/volume';

# the data files are located in this directory underneath the volume
# would like to get rid of this extra level of indirection
use constant MNT_SUBDIR => 'data';

# this opens a pipe named FH which fetches the CSV database, cleans it up (fixes capitalization etc)
# and returns a new CSV
unless (open FH, '-|') { # in child
    $DB::inhibit_exit = 0;  # allow me to debug in perl debugger
    open FIX,"|$Bin/fix_spreadsheet.pl";
    select \*FIX;
    getprint(CSV);
    exit 0;
}

my (%Links,%Files);
while (<FH>) {
    chomp;
    my ($submission,$original_name,$directory,$uniform_filename,$format,
	$organism,$target,$technique,$factor,$stage,$condition,
	$replicate_set,$build,$pi,$category) = split ("\t");

    next if $submission eq 'DCC id';
    next unless $submission;

    # Weird. Some filenames have the submission prepended, and others don't :-(
    $Links{$original_name}                   = [$directory,$uniform_filename];
    $Links{"${submission}_${original_name}"} = [$directory,$uniform_filename];
}

# now find where all the original files live
# after this runs %Files will contain filename=>directory-in-which-it-lives
find (sub {!/^\./ && -f $_ && ($Files{$_}=$File::Find::dir)},glob(MNT."*/data"));

for my $file (keys %Files) {
    my $link_source = $Links{$file};

    # recovery from mismatched file names; there shouldn't be any, but there are!!!!
  TRY: {
      last TRY if $link_source;  #found it

      # try removing the submission ID from the file
      (my $a = $file) =~ s/^\d+_//;
      $link_source = $Links{$a} and last TRY;

      # try adding a .gz extension
      if ($file !~ /\.gz$/) {
	  my $a = "$file.gz";
	  $link_source = $Links{$a} and last TRY;	  
      }

      # try adding a .zip extension
      if ($file !~ /\.zip$/) {
	  my $a = "$file.zip";
	  $link_source = $Links{$a} and last TRY;	  
      }

      warn "Nothing known about $Files{$file}/$file\n";
    }
    next unless $link_source;

    my $dfile  = DATA;
    (my $rel_target = $Files{$file}) =~ s!^$dfile/!!;

    my ($link_dir,$link_file) = @$link_source;
    $link_dir = File::Spec->catfile(DATA,$link_dir);
    make_path($link_dir) or die "make_path($link_dir): $!"
	unless -e $link_dir;

    # make a relative symbolic link so that ftp runs in chroot environment
    my $target = File::Spec->catfile('..','..','..','..',$rel_target,$file);

    chdir $link_dir;
    unlink $link_file if -e $link_file;
    symlink $target,$link_file or die "symlink('$target' => '$link_dir/$link_file'): $!";
}

exit 0;
