#!/usr/bin/perl

use strict;

warn "Fetching most recent AMI/snapshot IDs...\n";
my $ids = `/modencode/release/bin/list_amis.pl`;
my %map;
foreach (split "\n",$ids) {
    next unless $_;
    my ($key,$val) = /(\w+)\s*=\s*(.+)/;
    $map{$key} = $val;
}

warn "Updating modencode-cloud.html...\n";
open my $f,"/modencode/htdocs/modencode-cloud.template" or die $!;
open my $out,">/modencode/htdocs/modencode-cloud.html.new" or die $!;
while (<$f>) {
    s/<!--(\w+)-->/$map{$1}/eg;
} continue {
    print $out $_;
}
close $out;
rename '/modencode/htdocs/modencode-cloud.html.new','/modencode/htdocs/modencode-cloud.html';
