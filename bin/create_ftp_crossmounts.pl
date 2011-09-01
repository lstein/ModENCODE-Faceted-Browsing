#!/usr/bin/perl
use strict;
use FindBin '$Bin';
use lib "$Bin/../lib";
use File::Path;
use Data::Dumper;
use File::Basename;
use FacetedBrowsingUtils;

# Original author: Sohab Qureshi
# Original name: tree.pl
# Modified by: Lincoln Stein
#
# Purpose: after mounting modencode data volumes on an EC2 machine,
# run this script to create symbolic links/crossmounts. Pass it the
# current tag spreadsheet.

my $root_dir;
BEGIN {
    $root_dir = $0;
    $root_dir =~ s/[^\/]*$//;
    $root_dir = "./" unless $root_dir =~ /\//;
    push @INC, $root_dir;
}

my $spreadsheet = $ARGV[0];
use constant P_dir               => '/modencode/modencode-dcc/data';
use constant Slink_dir           => 'symbolic_links';
use constant Filename_separator  => ';';
use constant Tag_value_separator => '_';

my ($lvl1_dir, $lvl2_dir, $lvl3_dir, $lvl4_dir);
open my $fh, "<", $spreadsheet;
<$fh>; #header
my @nr = ();
my @r = (); 
my (%seenline,%seen_name);

while(my $line = <$fh>) {
    chomp $line;    
    next if $seenline{$line}++;
    my ($id, 
	$title, 
	$filename, 
	$rel_path,
	$organism,
	$target,
	$tech,
	$format,
	$factor,
	$condition,
	$lvl4_tech,
	$rep,
	$chip,
	$label,
	$build,
	$submission_id,
	$draft_universal_filename
	) = split "\t", $line;

    for my $x ($id, $title, $filename, $rel_path, $organism, $target, $tech, $format, $factor, $lvl4_tech, $rep, $chip, $label, $build, $submission_id) {
	$x =~ s/^\s*//; $x =~ s/\s*$//;
    }
    # errors, errors and more errors!
    if ($filename =~ /rep(\d+)/i) {
	$rep = $1;
    }
    $organism = fix_organism($organism);
    $organism =~ s/\s+/-/g;

    my ($lvl1_dir, $lvl2_dir, $lvl3_dir, $lvl4_dir) = ($organism, $target, $tech, $format);    

    $factor = fix_factor($factor);
    my ($strain, $cellline, $devstage, $tissue) = parse_condition($condition);
    $devstage = fix_stage($devstage);
    

    my @bio_dir = gen_bio_dir($factor, $strain, $cellline, $devstage, $tissue);
#    remove_tree(P_dir) if -e P_dir; #why it does not work?!
    my $leaf_dir = ln_dir(P_dir, Slink_dir, $lvl1_dir, $lvl2_dir, $lvl3_dir, $lvl4_dir, @bio_dir);

    my ($extension)            = $draft_universal_filename =~ /\.(\w+)(?:\.(?:gz|zip))?$/;
    $extension                 = 'wig' if $extension eq 'wiggle';
    $extension                .= '.' . lc($1) if $filename =~ /\.(gz|gzip|z|zip|bzip2)$/i;

    my $universal_filename     = std_filename($factor, $condition, $tech, $rep, $chip, $label, $build, $submission_id,$filename,$extension);
    my $ln_file = $leaf_dir . $universal_filename;
    print $ln_file,"\n";
    next;

    my $data_file = find_path($id, $filename, $format);
    chdir $leaf_dir;
    my $t;
    if (length($universal_filename)>255) {
	$t = substr($universal_filename, 0, 255);
    } else {
	$t = $universal_filename;
    }
    #Creating an empty file if it does not exist
    if (!(-e $t)) {
	open(FH,">$t") or die "Can't create $data_file: $!";
	close(FH);
    }
    #cross mounting if the data file exists 
    if (-e $data_file) {
	#my $signal = symlink($data_file, $t);
	#print join("\t", ('##ln -s ', $ln_file, $data_file)), "\n" if $signal == 0;
	
	$t =~ s/\;/\\;/g;
	$t =~ s/\ /\\ /g;
	$t =~ s/\(/\\\(/g;
        $t =~ s/\)/\\\)/g;
	#print ("Mounting $t \n");
	#my $result=`sudo mount --bind $data_file $t`;
	#print ("$result \n");	
    } else {
	#symlink($data_file, $t);
	print ("Data file not available: $t ----> $data_file\n the id/filename/format is $id $filename $format\n");
	#print ("$data_file \n");
	#print ("\n");

	#print join("\t", ('#ln -s ', $ln_file, $data_file)), "\n";
    }
}
#map {print $_, "\n"} @nr;



sub find_path {
    my ($id, $filename, $format) = @_;
    my $data_file;
    my $t;
    if ($format =~ /raw-seqfile/) {
        $t = $filename;
    } else {
        $t = "$id" . "_". $filename;
    }

    #Because we have 7 EBS volume we need to see which voume the data is in
    #Goes through the data folder of each volume and finds where the data is
    for (my $count = 1; $count <= 7; $count++) {
 	  if (-e "/modencode/modencode-dcc/drive$count/data/$t") {
		print ("Data is at: /modencode/modencode-dcc/drive$count/data/$t \n\n");
		$data_file = "/modencode/modencode-dcc/drive" . $count . "/data/" . $t;
	 }
    } 
    if (-e $data_file) {
	return $data_file;
    } 
    #Removing the .gz at the end???
    else {
	if ($data_file =~ /\.gz$/) {
	    $t = $data_file;
	    $t =~ s/\.gz$//;
	    if (-e $t) {
		return $t;
	    } 
	    else {
		return $data_file;
	    }
	} else {
	    return $data_file;
	}
    }
}

sub std_filename {
    my ($factor, $condition, $tech, $rep, $chip, $label, $build,$submission_id,$original,$extension) = @_ ;
    $rep  = $rep ? 'Rep-' . $rep : 'Rep-1';
    my $filename = join(Filename_separator, ($factor, $condition, $tech, $rep));
    if (defined($chip) && $chip ne '') {
	$filename = join(Filename_separator, ($filename, $chip));
    }
    if (defined($label) && lc($label) ne 'biotin' && $label ne '') {
	$filename = join(Filename_separator, ($filename, $label));
    }
    $build = 'Dmel_R5'      if $build eq 'Dmel_r5.4';
    $build = 'Cele_WS220'   if $build eq 'Cele_WS190';

    $filename = join(Filename_separator, ($filename, $build,$submission_id));

    $original =~ s/\.(gz|z|zip|bunzip2|gzip)$//i;
    while ($seen_name{"$filename.$extension"}++) {
	if ($original =~ s/[_.](\w+)$//) {
	    next if $1 eq $extension;
	    next if $1 =~ /cel|wig|fastq|pair|gff/i;
	    $filename .= ";$1";
	} else {
	    $filename .= ";$original";
	}
	warn "uniquefying to $filename";
    }
    
    # $filename .= ".smoothedM.clusters" if $original =~ /smoothedM\.clusters/;
    # $filename .= ".smoothedM"         if $original =~ /smoothedM/;
    # $filename .= ".Mvalues"           if $original =~ /Mvalues/;
    # $filename .= ".$1"                if $original =~ /(\d+LM)\.wig/;
    # if ($original =~ /((?:\w+-\w+_)?\d+_(?:I[NP]_)?\d+)\.pair/) {
    # 	$filename .= ".$1";
    # }
    # if ($original =~ /((?:\w+-\w+_)?\d+_INPUT_?\d+)\.pair/) {
    # 	(my $i = $original) =~ s/INPUT/IN/;
    # 	$filename .= ".$i";
    # }
    # $filename .= '_Input' if $original =~ /Input\.CEL/;

    return "$filename.$extension";
}

sub gen_bio_dir {
    my ($factor, $strain, $cellline, $devstage, $tissue) = @_;
    my @rna = ('5-prime-utr', 'small-rna', '3-prime-utr', 'utr', 'splice-junction', 'transfrag', 'polya-rna', 'total-rna');
    if (scalar grep {$_ eq $factor} @rna) {
	if (defined($cellline)) {
	    return ($cellline);
	} else {
	    if (defined($tissue)) {
		return ($tissue);
	    } else {
		$devstage = format_dirname($devstage);
		return ($strain, $devstage);
	    }
	}
    } else {
	$devstage = format_dirname($devstage);
	return ($factor, $devstage);
    }
}

sub format_dirname {
    my $dir = shift;
    $dir =~ s/,//g;
    return $dir;
}

sub format_dirname2 {
    my ($dir, $name) = @_;
    $dir =~ s/\.txt$/.CEL/;
    $dir =~ s/\.wiggle$/.wig/;
    return $dir;
    my ($suffix) = $name =~ /\.(\w+(?:\.gz)?)$/;
    return "$dir.$suffix";
    $dir =~ s/\///g; #absolutely needed
    $dir =~ s/\(/ /g; #absolutely needed
    $dir =~ s/\)/ /g; #absolutely needed
    $dir =~ s/,//g;  #absolutely needed
    $dir =~ s/ +/-/g; #absolutely needed
    $dir =~ s/\.//g; #absolutely needed 
    #this version will creat 5995 symbolic link out of 6035 files
    #since the filename generated is tooo long for my poor 32bit laptop.
    #if I do s/ +//g, then 6019 slink created.
    my $base;
    my $rtn_name;
    if (defined($name)) {
	my ($file, $dirx, $suffix) = fileparse($name, qr/\.[^.]*/);
	#print $suffix, "\n";
	if (scalar grep {lc($suffix) eq $_} ('.zip', '.bz2', '.gz')) {
	    my ($zfile, $zdir, $zsuffix) = fileparse($file, qr/\.[^.]*/);
	    $base = $zfile;
	} else {
	    $base = $file;
	}
	$rtn_name = $dir . Filename_separator . $base;
    } else {
	$rtn_name = $dir;
    }
    return $rtn_name;
}

sub parse_condition {
    my $condition = shift;
    my %map;
    $condition =~ s/^\s*//g; $condition =~ s/\s*$//g;
    my @cds = split(Filename_separator, $condition);
    for my $cd (@cds) {
	my ($k, $v) = split(Tag_value_separator, $cd);
	$map{$k} = $v;
    }
    my ($strain, $cellline, $devstage, $tissue) = (
	$map{'Strain'}, 
	$map{'Cell-Line'}, 
	$map{'Developmental-Stage'},
	$map{'Tissue'},
	);
    #$strain = $1 if $condition =~ /Strain_(.*?)_/;
    #$cellline = $1 if $condition =~ /Cell-Line_(.*?)_/;
    #$devstage = $1 if $condition =~ /Developmental-Stage_(.*?)_/;
    #$tissue = $1 if $condition =~ /Tissue_(.*?)_/;
    return ($strain, $cellline, $devstage, $tissue);
}


sub ln_dir {
    my @dirs = @_;
    die if $dirs[0] ne P_dir;
    die if $dirs[1] ne Slink_dir;
    my $dir;
    for (my $i=0; $i<scalar @dirs; $i++) {
	my $tdir = '';
	for (my $j=0; $j<=$i; $j++) {
	    my $t = $dirs[$j];
	    $tdir .= $t . "/";
	}
	mkdir($tdir) unless -e $tdir;
	$dir = $tdir;
    }
    return $dir;
}

sub sfx {
    my $format = shift;
    my ($category, $sfks) = split "_", $format;
    return ".$sfks";    
}
