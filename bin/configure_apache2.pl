#!/usr/bin/perl

use strict;
my $apache_conf = '/etc/apache2/sites-available/default';
my $new         = '/etc/apache2/sites-available/default.new';

open my $in, '<',$apache_conf or die "$apache_conf: $!";
open my $out,'>',$new         or die "$new: $!";
while (<$in>) {
    chomp;
    s!/var/www!/modencode/htdocs!;
    s!/usr/lib/cgi-bin!/modencode/cgi-bin!;
} continue {
    print $out $_,"\n";
}

rename $apache_conf,"${apache_conf}.orig";
rename $new,$apache_conf;
system 'sudo','/etc/init.d/apache2','restart';

exit 0;
