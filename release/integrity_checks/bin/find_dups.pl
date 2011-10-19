#!/usr/bin/perl

# find and report on cases in which the same file is present twice,
# once as a uncompressed file and once compressed

use strict;
use File::Find;
use File::Basename 'basename';
use constant DATA => '/modencode/data/all_files';
use constant MB   => 1_048_576;
my %FILES;
my %SIZES;
my $Wasted = 0;

my @directories = @ARGV ? @ARGV : glob(DATA.'/volume*');
find(\&tabulate,@directories);

for my $basename (sort keys %FILES) {
    my @paths = keys %{$FILES{$basename}};
    next if @paths == 1;
    my $size = sprintf("%5.2f",$SIZES{$basename});
    print $basename,': ',scalar @paths," copies, consuming $size MB\n";

    my %sizes = map {$_ => (-s $_)/MB} @paths;
    foreach (@paths) {
	print "\t",$_,"\t",sprintf("%5.2f",$sizes{$_}),"\n";
    }

    # sort sizes
    my ($min,@rest) = sort {$a<=>$b} values %sizes;
    $Wasted += $_ foreach (@rest);
}
printf "\n\n***%5.2f GB wasted space ***\n",$Wasted/1024;

exit 0;

sub tabulate {
    return unless -f $_;
    my $size  = (stat(_))[7];
    my $base  = basename($_,'.gz','.Z','.zip','.bz2','.tar.gz','.tgz');
    $FILES{$base}{$File::Find::name}++;
    $SIZES{$base} += $size/MB;
}
