#!/usr/bin/perl

# Create links from big-mongo data volumes to sorted hierarchical list, for
# convenient FTP browsing.

use strict;
use FindBin '$Bin';
use lib "$Bin/../lib";
use FacetedBrowsingUtils;
use File::Path 'make_path','remove_tree';
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

# The location of the name mapping file
use constant NAME_MAPPING => DATA . '/MANIFEST.txt';

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
warn "Building database of symbolic file names...\n";
while (<FH>) {
    chomp;
    my ($submission,$original_name,$directory,$uniform_filename,$format,
	$organism,$target,$technique,$factor,$stage,$condition,
	$replicate_set,$build,$pi,$category) = split ("\t");

    next if $submission eq 'DCC id';
    next unless $submission;

    # Weird. Some filenames have the submission prepended, and others don't :-(
    $Links{$original_name}                   = [$directory,$uniform_filename,$submission];
    $Links{"${submission}_${original_name}"} = [$directory,$uniform_filename,$submission];
}

warn "Unbinding old mounts...\n";
remove_old_mounts();

warn "Removing symbolic link tree...\n";
remove_old_directories();

# now find where all the original files live
# after this runs %Files will contain filename=>directory-in-which-it-lives
warn "Cross-mounting data sets...\n";
find (sub {!/^\./ && -f $_ && ($Files{$_}=$File::Find::dir)},glob(MNT."*/data"));

open MANIFEST,"|sort -n >".NAME_MAPPING;
print MANIFEST "#<modencode accession>   <original filename>   <uniform filename>\n";

my %Seenit; # find duplicate file errors
for my $file (keys %Files) {
    my $link_source = $Links{$file};

    # recovery from mismatched file names; there shouldn't be any, but there are!!!!
  TRY: {
      last TRY if $link_source;  #found it

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

      # try removing the submission ID from the file
      # turns out to be a bad idea because it can lead to link going to wrong file.
      # (my $a = $file) =~ s/^\d+_//;
      # $link_source = $Links{$a} and last TRY;

      warn "No metadata for $Files{$file}/$file\n";
    }
    next unless $link_source;

    my ($link_dir,$link_file,$id) = @$link_source;
    $link_dir = File::Spec->catfile(DATA,$link_dir);
    make_path($link_dir) or die "make_path($link_dir): $!"
	unless -e $link_dir;

    my $target = File::Spec->catfile($Files{$file},$file);
    my $source = File::Spec->catfile($link_dir,$link_file);

    # do an export mount
    # touch file to create a mount point
    if ($Seenit{$source}++) {
	die "File already linked:\nOriginal: $target\nLink name:$source\n";
    }
    open FH,'>',$source or die "Can't write $source: $!";
    close FH;

    my @args   = ('sudo','mount','--bind',$target,$source);
    system @args;

    my $data = DATA;
    (my $a = $target) =~ s/^$data/./;
    (my $b = $source) =~ s/^$data/./;
    print MANIFEST join("\t","$id",$a,$b),"\n";
}

close MANIFEST;

warn "Done!\n";

exit 0;

sub remove_old_mounts {
    my $all_files = ALL_FILES;
    open M,"/etc/mtab" or return;
    while (<M>) {
	chomp;
	my ($from,$to) = split /\s+/;
	next unless $from =~ m!/$all_files/!;
	system 'sudo','umount',$from;
    }
    close M;
}

sub remove_old_directories {
    my $all_files = ALL_FILES;
    my @dirs      = grep {!/$all_files/} glob(DATA."/*");
    for my $d (@dirs) {
	next unless -d $d;
	remove_tree($d);
    }
}
