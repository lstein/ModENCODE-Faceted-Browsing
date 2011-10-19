#!/usr/bin/perl

use strict;
use lib '/modencode/perl/share/perl','/modencode/lib';
use EC2Utils;
use VM::EC2;

setup_credentials();
my $ec2 = VM::EC2->new;
my @snaps = $ec2->describe_snapshots(-filter=>{'tag:Name' => 'modEncode Data*'});
for my $s (@snaps) {
    print join("\t",$s,$s->tags->{Name}),"\n";
}

exit 0;
