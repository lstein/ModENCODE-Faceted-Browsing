#!/usr/bin/perl

use strict;

# this script deletes all the data snapshots associated with a deregistered AMI

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

my $ami = shift or die "Usage: $0 <ami-xxxxxx>\nDelete volume snapshots associated with a deregistered AMI\n";

# initial setup
setup_credentials();

my $ec2 = VM::EC2->new;

my @snapshots = grep {$_->description =~ /^Created by CreateImage\S+ for $ami from vol/}
                     $ec2->describe_snapshots;

print STDERR "Delete @snapshots? [yN] ";
die "aborted" unless <> =~ /^[yY]/;
foreach (@snapshots) {
    $ec2->delete_snapshot($_) or warn "$_: ",$ec2->error_str;
}

