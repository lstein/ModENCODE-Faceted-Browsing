#!/usr/bin/perl

# Create links from big-mongo data volumes to sorted hierarchical list, for
# convenient FTP browsing.

use strict;
use FindBin '$RealBin';
use lib "$RealBin/../lib","$RealBin/../perl/lib/perl","$RealBin/../perl/lib/perl/5.10";
use FacetedBrowsingUtils;
use MatchMeFile;
use File::Path 'make_path','remove_tree';
use File::Spec;
use File::Basename;
use File::Find;
use LWP::Simple 'getprint','mirror';

my $VERBOSE;
if ($ARGV[0] =~ /^-[vV]/) {
    $VERBOSE++;
}

# This is where the terabyte volume mounts are
use constant ALL_FILES => 'all_files';
use constant FLAT      => MODENCODE_DATA .'/'.ALL_FILES;

# volumes are mounted at /modencode/data/all_files/volume{1,2,3,4...}
use constant MNT      => FLAT . '/volume';

# the data files are located in this directory underneath the volume
# would like to get rid of this extra level of indirection
use constant MNT_SUBDIR => 'data';

# The location of the name mapping file
use constant NAME_MAPPING      => MODENCODE_DATA . '/MANIFEST.txt';
use constant FIXED_SPREADSHEET => MODENCODE_DATA . '/metadata.csv';

# Location of METADATA_URL and METADATA_FIXED is currently hard-coded in lib/FacetedBrowsingUtils.pm
my $mirror = '/modencode/release/metadata_mirror.csv';
mirror(METADATA_URL,$mirror);
unless (-e METADATA_FIXED && (-M METADATA_FIXED <= -M $mirror) && -s METADATA_FIXED) {
    open FH,"$RealBin/fix_spreadsheet.pl <$mirror| tee ".METADATA_FIXED."|" or die "pipe: $!";
} else {
    open FH,METADATA_FIXED or die METADATA_FIXED,": $!";
}

my (%Links,%Files,%Metadata,$Row_header,$Count);
warn "Building database of symbolic file names...\n";
while (<FH>) {
    chomp;
    my @fields = split ("\t");

    my ($submission,$original_name,$directory,$uniform_filename,$format,
	$organism,$target,$technique,$factor,$stage,$condition,
	$replicate_set,$build,$pi,$category) = @fields;

    if ($submission eq 'DCC id') {
	$Row_header = $_;
	next ;
    }
    warn "no submission on $_" unless $submission;
    next unless $submission;

    # we are going to quality original filenames with the submission
    $Links{$original_name}             = [$submission,$directory,$uniform_filename];

    # keep a record of the data so that we can write it out
    $Metadata{$submission}{$original_name} = \@fields;
    $Count++;
}

warn "Removing symbolic link tree...\n";
remove_old_directories();

# now find where all the original files live
# after this runs %Files will contain filename=>directory-in-which-it-lives
warn "Symlinking data sets...\n";

# recursive find; on name collisions, keep the most recent file
find (sub {
    return      if /^\./;
    return unless -f $_;
    my $record = {dir   => $File::Find::dir,
		  mtime => (stat(_))[9]};
    next if $Files{$_} && ($Files{$_}{mtime} > $record->{mtime});
    $Files{$_} = $record;
      },
      FLAT);

open MANIFEST,"|sort -n >".NAME_MAPPING.'.new'  or die NAME_MAPPING,": $!";;
print MANIFEST "#<modencode accession>   <original filename>   <uniform filename>\n";

open SPREADSHEET,'>',FIXED_SPREADSHEET. '.new' or die FIXED_SPREADSHEET,": $!";
print SPREADSHEET $Row_header,"\n";

my (%Seenit,%Missing,%MissingS);
for my $original_name (keys %Links) {

    my ($submission,$link_dir,$link_file) = @{$Links{$original_name}};

    # the last argument allows match_me to return multiple hits;
    # only allowed case are the SRR files, which have the format SRR12345.fastq, SRR12345_1.fastq, SRR12345_2.fastq
    my $srr = $original_name =~ /SRR\d+/;
    my ($m,$explanation) = match_me($original_name,$submission,\%Files,$srr);

    # Uncomment this to discard dubious matches, which are usually
    # related to files from related submissions being deliberately mingled.
    # next if $explanation =~ /dubious/i;  

    unless ($m) {
	$Missing{$original_name}++;
	$MissingS{$submission}++;
	next;
    }

    my $matches;
    if (ref $m && ref $m eq 'ARRAY') {
	$matches = $m;
    } else {
	$matches = [$m];
    }

    $link_dir = File::Spec->catfile(MODENCODE_DATA,$link_dir);
    make_path($link_dir) or die "make_path($link_dir): $!"
	unless -e $link_dir;

    for my $match (sort @$matches) {

	my $target = File::Spec->catfile($Files{$match}{dir},$match);
	my $source = File::Spec->catfile($link_dir,$link_file);

	# ensure that one link doesn't overwrite another
	if ($Seenit{$source}++) {
	    if ($target =~ /(_\d+)\.fastq(?:.gz)?$/) {
		my $a   = $1;
		$source =~ s/\.fastq/${a}.fastq/;
	    } else {
		my $index = 1;
		my $candidate;
		do {
		    $candidate = $source;
		    $candidate =~ s/(\.[^.]+(?:\.gz)?)$/-${index}\1/;
		    $index++;
		} until !$Seenit{$candidate}++;
		$source = $candidate;
	    }
	}

	$source .= '.gz' unless $source =~ /\.(gz|zip|z|bzip2)$/i;
	
	my $data = MODENCODE_DATA;
	(my $t = $target) =~ s!^$data!../../../..!;
	symlink $t,$source;
	
	(my $a = $target) =~ s/^$data/./;
	(my $b = $source) =~ s/^$data/./;
	print MANIFEST join("\t",$submission,$a,$b),"\n";
	
	my @fields = @{$Metadata{$submission}{$original_name}};
	$fields[1] = $match;
	$fields[2] .= '.gz' unless $fields[2] =~ /\.(gz|zip|z|bzip2)$/i;
	print SPREADSHEET join("\t",@fields),"\n";
    }
}

close MANIFEST;
close SPREADSHEET;
rename FIXED_SPREADSHEET.'.new',FIXED_SPREADSHEET;
rename NAME_MAPPING.'.new',NAME_MAPPING;

my $missing_files = keys %Missing;
my $missing_subs  = keys %MissingS;
if ($missing_files > 0) {
    print STDERR "$missing_files data files of $Count total ($missing_subs submissions) are missing or not mounted.\n";
    print join "\n",keys %Missing,"\n" if $VERBOSE;
}

warn "Done!\n";

exit 0;

sub remove_old_directories {
    my $all_files = ALL_FILES;
    my @dirs      = grep {!/publications|$all_files/} glob(MODENCODE_DATA."/*");
    for my $d (@dirs) {
	next unless -d $d;
	remove_tree($d);
    }
}
