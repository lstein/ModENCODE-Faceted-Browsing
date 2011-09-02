package FacetedBrowsingUtils;
use strict;

use base 'Exporter';
use FindBin '$Bin';

our @EXPORT_OK = qw(
                    METADATA_URL MODENCODE_ROOT MODENCODE_DATA
                    fix_original_name fix_organism fix_stage fix_factor find_category 
                    fix_factor fix_pi fix_target fix_build
                    fix_condition fix_repset);
our @EXPORT    = @EXPORT_OK;

# Data file with metadata, filenames, etc. Can be a URL
use constant METADATA_URL     => "file:$Bin/../data/modencode-22August2011.csv";
use constant MODENCODE_ROOT   => '/modencode';  

# This is the root of the anonymous FTP account
# top level links, such as D.melanogaster are found here
use constant MODENCODE_DATA     => MODENCODE_ROOT .'/data';

my %Factor_map = (
	'BEAF32A and B' => 'BEAF-32',
        'BEAF32A and BEAF32B' => 'BEAF-32',
	"cap'n collar" => 'cnc',
	"CTCF C-terminus" => 'CTCF',
	"CTCF N-terminus" => 'CTCF',
	'CBP-1' => 'cbp',
	'C-terminal Binding Protein' => 'cbp',
	'H4tetraac' => 'H4acTetra',
	'Histone H3' => 'H3',
	'histone H3' => 'H3',
	'MCM2-7 complex' => 'mcm2-7',
	'MOD(MDG4)67.2' => 'mod(mdg4)',
	'na' => 'no-antibody-control',
	'Not Applicable' => 'no-antibody-control', 
	'PolII' => 'pol2',
	'polII' => 'pol2',
	'RNA polII CTD domain unphosophorylated' => 'pol2', 
	'RNA Polymerase II' => 'pol2',
	'RNA polymerase II CTD repeat YSPTSPS' => 'pol2', 
	'Drosophila ORC2p' => 'orc2',
	'H4K20me' => 'h4k20me1',
	'Histone H3' => 'h3',
	'JIL1' => 'jil-1',
	'N/A (negative control IgG)' => 'IgG control',
    );
my %Stage_map = ('E0-4' => 'Embryo 0-4h',
	'E12-16' => 'Embryo 12-16h',
	'E16-20' => 'Embryo 16-20h',
	'E20-24' => 'Embryo 20-24h',
	'E4-8' => 'Embryo 4-8h',
	'E8-12' => 'Embryo 8-12h',
	'Embryo 22-24hSC' => 'Embryo 22-24h',
	'Dmel Adult Female Whole Species' => 'Adult Female',
	'Dmel Adult Male Whole Species' => 'Adult Male',
	'Adult female eclosion+4 day'   => 'Adult Female, eclosion + 4 days',
        'Adult Female eclosion+4 day'   => 'Adult Female, eclosion + 4 days',
	'third instar larval stage'     => 'Larvae 3rd instar',
	'2-18 hr Embryos'               => 'Embryos 2-18 hr',
    );

sub fix_original_name {
    my $name = shift;
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    return $name;
}

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
    $stage   =~ s/^dmel\s+//;
    $stage   =~ s/^\s+//;
    $stage   =~ s/adult female/Adult Female/ig;
    $stage   =~ s/adult male/Adult Male/ig;
    $stage   =~ s/^(\d+-\d+) day old pupae/Pupae $1 day/; 
    $stage   =~ s/^(\w+) instar larvae/Larvae $1 instar/i;
    $stage   =~ s/^(\w+) stage larvae/Larvae $1 stage/i;
    $stage   = $Stage_map{$stage} || $stage;
    return ucfirst($stage);
}

sub fix_factor {
    my $factor = shift;
    $factor =~ s!^(H\d+[A-Z]\d+)(\w+)!$1\l$2!;
    $factor =~ s!H4tetraac!H4acTetra!i;
    $factor =~ s!Trimethylated Lys-4 o[fn] histone H3!H3K4me3!i;
    $factor =~ s!Trimethylated Lys-9 o[fn] histone H3!H3K9me3!i;
    $factor =~ s!Trimethylated Lys-36 o[fn] histone H3!H3K36me3!i;
    $factor =~ s!SU\(HW\)!Su(Hw)!i;
    return $Factor_map{$factor} || $factor;
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

sub fix_target {
    my $target = shift;
    $target =~ tr/-/ /;
    return $target;
}

sub fix_pi {
    my $pi = shift;
    $pi       =~ s/^(\w)\w+\s*(\w+)/$2, $1./;
    $pi      ||= 'Oliver B.';   # nasty fix
    return $pi;
}

sub fix_condition {
    my $condition = shift;
    my @conditions;
    for my $c (split ';',$condition) {
	my ($key,$value) = split '_',$c;
	if ($key eq 'Compound' && $value =~ /mM/) {
	    $value .= ' salt';
	} elsif ($key eq 'Developmental-Stage') {
	    $value  = fix_stage($value);
	}
	push @conditions,[$key,$value] if (defined $key && defined $value);
    }
    return join ('#',map {join('=',@$_)} sort {$a->[0] cmp $b->[0]} @conditions);
}

sub fix_build {
    my $b = shift;
    return 'Dmel_R5'     if $b eq 'Dmel_r5.4';
    return 'Cele_WS220'  if $b eq 'Cele_WS190';
    return $b;
}

sub fix_repset {
    my ($repset,$filename) = @_;
    if ($filename =~ /rep-?(\d+)/i) {
	$repset = "Rep-$1";
    }
    return $repset;
}

1;
