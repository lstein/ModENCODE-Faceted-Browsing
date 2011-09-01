package FacetedBrowsingUtils;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw(fix_organism fix_stage fix_factor find_category fix_pi);
our @EXPORT    = @EXPORT_OK;

sub fix_organism {
    my $org = shift;
    return $org =~ /^Cele/ ? 'C. elegans'
	  :$org =~ /^Dmel/ ? 'D. melanogaster'
	  :$org =~ /^Dmoj/ ? 'D. mojavensis'
	  :$org =~ /^Dyak/ ? 'D. yakuba'
	  :$org =~ /^Dana/ ? 'D. ananassae'
	  :$org =~ /^Dpse/ ? 'D. pseudoobscura'
	  :$org =~ /^Dsim/ ? 'D. simulans'
	  :$org =~ /^Dvir/ ? 'D. virilis'
	  :$org;
}

sub fix_stage {
    my $stage = shift;
    $stage   =~ tr/_/ /;  # get rid of underscores
    $stage   =~ s/embryo/Embryo/;
    $stage   =~ s/Embyro/Embryo/;
    $stage   =~ s/^E(?=\d)/Embryo /;
    $stage  .= ' h' if $stage =~ /^Embryo.*\d$/;
    $stage   =~ s/hr$/h/;
    $stage   =~ s/(\d)h$/$1 h/;
    $stage   =~ s/^DevStage://;
    $stage   .= ' stage larvae' if $stage =~ /L\d/;
    $stage   =~ s/Larvae? stage larvae/stage larvae/i;
    $stage   =~ s/^late/Late/;
    $stage   =~ s/^early/Early/;
    $stage   =~ s/^larva L(\d)/L$1/i;
    $stage   =~ s/^yAdult/Young adult/i;
    $stage   =~ s/(\d)\s?hr?/$1 hr/g;
    $stage   =~ s/larvae?(.+stage larvae)/$1/;
    $stage   =~ s/\s+\d+dc//i;
    $stage   =~ s/embryo\b/Embryos/i;
    $stage   =~ s/stage stage/stage/;
    $stage   =~ s/WPP/White prepupae (WPP)/;
    $stage   =~ s/^\s+//;
    return ucfirst($stage);
}

sub fix_factor {
    my $factor = shift;
    $factor =~ s!^(H\d+[A-Z]\d+)(\w+)!$1\l$2!;
    $factor =~ s!H4tetraac!H4acTetra!;
    $factor =~ s!Trimethylated Lys-4 o[fn] histone H3!H3K4me3!i;
    $factor =~ s!Trimethylated Lys-9 o[fn] histone H3!H3K9me3!i;
    $factor =~ s!Trimethylated Lys-36 o[fn] histone H3!H3K36me3!i;
    $factor =~ s!SU\(HW\)!Su(Hw)!i;
    return $factor;
}

sub find_category {
    my ($pi,$technique,$target) = @_;

    if ($pi =~ /Henikoff/) {
	return 'Chromatin structure'      if $target =~ /chromatin structure/i;
	return 'RNA expression profiling' if $target =~ /mRNA/;
	return;
    }

    if ($pi =~ /Celniker/) {
	return 'RNA expression profiling' if $technique eq 'RNA-tiling-array';
	return 'Gene Structure';
    }

    if ($pi =~ /Waterston/) {
	return 'RNA expression profiling' if $technique eq 'RNA-tiling-array';
	return 'Gene Structure';
    }

    if ($pi =~ /Karpen/) {
	return 'Histone modification and replacement' if $target =~ /Histone Modification/;
	return 'Other chromatin binding sites'        if $target =~ /Non TF Chromatin binding factor/;
	return;
    }

    if ($pi =~ /Lai/) {
	return 'RNA expression profiling' if $target eq 'small RNA';
	return;
    }

    if ($pi =~ /Lieb/) {
	return 'Histone modification and replacement' if $target =~ /Histone Modification/;
	return 'Other chromatin binding sites'        if $target =~ /Non TF Chromatin binding factor/;
	return 'Chromatin structure'                  if $target =~ /chromatin structure/i;
	return 'RNA expression profiling'             if $target =~ /mRNA/;
	return;
    }

    if ($pi =~ /MacAlpine/i) {
	return 'Replication'                          if $target =~ /DNA Replication/i;
	return 'Copy Number Variation'                if $target =~ /Copy Number Variation/i;
	return 'TF binding sites'                     if $target =~ /Transcriptional Factor/i;
	return;
    }

    if ($pi =~ /Oliver/) {
	return 'RNA expression profiling' if $target =~ /mRNA/;
    }

    if ($pi =~ /Piano/) {
	return 'Gene Structure'                       if $target =~ /mRNA/;
	return 'RNA expression profiling'             if $target =~ /small RNA/i;
	return;
    }

    if ($pi =~ /Snyder/) {
	return 'TF binding sites'                     if $target =~ /Transcriptional Factor/i;
	return;
    }

    if ($pi =~ /White/) {
	return 'Histone modification and replacement' if $target =~ /Histone Modification/i;
	return 'TF binding sites'                     if $target =~ /Transcriptional Factor/i;
	return 'Other chromatin binding sites'        if $target =~ /Non TF Chromatin binding factor/i;
	return 'RNA expression profiling'             if $target =~ /mRNA/;
    }

    return;
 }

sub fix_pi {
    my $pi = shift;
    $pi       =~ s/^(\w)\w+\s*(\w+)/$2, $1./;
    $pi      ||= 'Oliver B.';   # nasty fix
    return $pi;
}

1;
