package MatchMeFile;
use strict;

# Utility to match up modencode filenames via various heuristics
# Should not be necessary.

use base 'Exporter';
our @EXPORT_OK = qw(match_me);
our @EXPORT    = @EXPORT_OK;

# in:  $proposed_name,$accession_number,\%hash_of_filenames
# out: $matched_name,'explanation'
# $matched_name will be undef if no match found
sub match_me {
    my ($filename,$id,$file_list,$is_srr) = @_;

    # these are standard, expected, cleanups
    $filename  =~ s/^\s+//;
    $filename  =~ s/\s+$//;
    $filename  =~ s/\.(FASTQ|GFF3|WIG|PAIR)/'.'.lc($1)/e;
    $filename .= '.gz' unless $filename =~ /\.(gz|zip|z|bzip2)$/i;
    $filename  = "${id}_$filename" unless $filename =~ /^$id[_.]/;
    return $filename,'FOUND' if $file_list->{$filename};

    # horrid hack/workaround -- return multiple names for SRR files
    if ($is_srr) {
	(my $base = $filename) =~ s/\..+$//;
	$base =~ s/^\d+_//;
	my @candidates = grep {/\Q$base\U/i} keys %$file_list;
	return (\@candidates,'SRR match') if @candidates;
    }

    # horrid hack/workaround -- use lifted filenames in preference
    if ($filename =~ /WS\d+/) {
	(my $try = $filename) =~ s/WS\d+/WS220/;
	return $try,'found after C. elegans liftover munging'  if $file_list->{$try};
	($try = $filename) =~ s/WS\d+/ws220/;
	return $try,'found after C. elegans liftover munging'  if $file_list->{$try};
    }
    if ($filename =~ /ws\d+/i) {
	(my $try = $filename) =~ s/ws\d+/ws220/i;
	return $try,'found after C. elegans liftover munging'  if $file_list->{$try};
	($try = $filename) =~ s/ws\d+/WS220/i;
	return $try,'found after C. elegans liftover munging'  if $file_list->{$try};
    }

    return $filename,'FOUND' if $file_list->{$filename};

    my $try = $filename;

    # try stripping leading whitespace
    $try =~ s/^\s+//;
    $try =~ s/\s+$//;
    if ($file_list->{$try}) {
	return $try,'found after whitespace removal'; 
    }

    # try adding leading whitespace
    if ($file_list->{" $try"}) {
	return " $try",'found after adding leading whitespace';
    }

    # try adding trailing whitespace
    if ($file_list->{"$try "}) {
	return "$try ",'found after adding trailing whitespace';
    }

    # try adding the accession number to the beginning
    if ($file_list->{"${id}_$try"}) {
	return "${id}_$try",'found after adding accession prefix';
    }

    # try adding modENCODE_accession number to the beginning
    if ($file_list->{"modENCODE_${id}_$try"}) {
	return "modENCODE_${id}_$try",'found after adding modENCODE accession prefix';
    }

    # try adding the accession number to the beginning and adding a .gz extension
    if ($file_list->{"${id}_${try}.gz"}) {
	return "${id}_${try}.gz",'found after adding accession and .gz extension';
    }

    # try removing the accession number from the beginning
    (my $try2 = $try) =~ s/^(?:modencode_)?\d+_//i;
    if ($file_list->{$try2}) {
	return $try2,'found after stripping accession';
    }

    # try removing the accession number from the beginning and adding a .gz extension
    if ($file_list->{"$try2.gz"}) {
	return "$try2.gz",'found after stripping accession and adding .gz';
    }

    # try removing extension
    (my $base = $filename) =~ s/\.[^.]+$//;
    if ($file_list->{$base}) {
	return $base,'found after removing extension altogether';
    }

    # last desperate attempt; try a regular expression match
    my @candidates;
  REGEX: {
      @candidates = grep {/\Q$try\U/i} keys %$file_list;
      last REGEX if @candidates == 1;

      @candidates = grep {/\Q$try2\U/i} keys %$file_list;
      last REGEX if @candidates == 1;

      (my $try3 = $try) =~ s/\.[^.]+$//;
      @candidates = grep {/\Q$try3\U/i} keys %$file_list;
      last REGEX if @candidates == 1;

      $try3 =~ s/^\d+_//;
      @candidates = grep {/\Q$try3\U/i} keys %$file_list;
      last REGEX if @candidates == 1;

      # this allows the WS number to change on C. elegans builds
      # to account for the case in which the filename was changed
      # during liftover...
      (my $try4 = $try) =~ s/^(.*ws)\d+(.*)$/\Q$1\U\d+\Q$2\U/;
      @candidates = grep {/\Q$try3\U/i} keys %$file_list;
      last REGEX if @candidates == 1;
    }

    return undef,'NOT FOUND' unless @candidates == 1;
    my $candidate = $candidates[0];
    if ($candidate =~ /^(\d+)_/ && $1 != $id) {
	return $candidate,'DUBIOUS REGEX MATCH';
    } else {
	return $candidate,'found after regex match';
    }
}

1;
