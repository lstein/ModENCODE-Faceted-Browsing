#!/usr/bin/perl

use strict;

use lib '/modencode/perl/share/perl','/modencode/lib';
use VM::EC2;
use EC2Utils;

print STDERR <<END;
This script tags current data snapshots with the "Current"
tag, and then DELETES non-current snapshots. Proceed
carefully.
END
    ;


print STDERR "Tagging current snapshots...";
system "/modencode/release/bin/tag_current_snapshots.pl";
print STDERR "done\n";

setup_credentials();
my $ec2         = VM::EC2->new();
my @snapshots   = grep {!exists $_->tags->{Current}}
                     sort {$a->description cmp $b->description} 
                     $ec2->describe_snapshots(-owner=>296402249238,-filter=>{description=>'modENCODE*data, part*'});

print STDERR "The following snapshots will be removed:\n";
foreach my $s (@snapshots) {
    print STDERR $s,' ',$s->description,"\n";
}

print STDERR "Proceed? [yN] ";
my $response = <>;
die "aborted\n" unless $response =~ /^[yY]/;

foreach (@snapshots) { 
    my $result = $ec2->delete_snapshot($_);
    unless ($result) {
	warn "$_: ",$ec2->error_str,"\n";
    }
}

exit 0;
