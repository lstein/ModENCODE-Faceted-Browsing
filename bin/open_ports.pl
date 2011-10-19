#!/usr/bin/perl

use strict;
use FindBin '$RealBin';
use lib "$RealBin/../perl/share/perl","$RealBin/../lib";
use File::Path 'make_path';
use EC2Utils;
use VM::EC2;

setup_credentials();

my $ec2  = VM::EC2->new or die "Couldn't initialize connection to Amazon EC2: $!";
my $meta = $ec2->instance_metadata;
my $instance_id = $meta->instanceId;
my $instance    = $ec2->describe_instances($instance_id);
my ($group)     = $instance->groups;
$group          = $ec2->describe_security_groups($group);
my @permissions = $group->ipPermissions;
my %ports       = map {$_->fromPort=>1} @permissions;

# web
$group->authorize_incoming(-protocol => 'tcp',
			   -port     => 80)
    unless $ports{80};

# ftp control channel
$group->authorize_incoming(-protocol => 'tcp',
			   -port     => 21)
    unless $ports{21};

# ftp data channel
$group->authorize_incoming(-protocol => 'tcp',
			   -port     => 20)
    unless $ports{20};

# FTP PASV ports
$group->authorize_incoming(-protocol => 'tcp',
			   -ports    => '12000..12200')
    unless $ports{12000};

$group->update() or warn "Couldn't update firewall permissions: ",$ec2->error_str;
exit 0;
