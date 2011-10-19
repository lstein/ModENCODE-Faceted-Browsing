#!/usr/bin/perl

use strict;
use FindBin '$RealBin';
use lib "$RealBin/../perl/share/perl","$RealBin/../lib";
use File::Path 'make_path';
use VM::EC2;

my $metadata       = VM::EC2->instance_metadata;
my $public_ip      = $metadata->ipAddress;

my $vsftpd_conf = '/etc/vsftpd.conf';
my $new         = '/etc/vsftpd.conf.new';

system 'sudo','usermod','-d','/modencode/data','ftp';
open my $in, '<',$vsftpd_conf or die "$vsftpd_conf: $!";
open my $out,'>',$new         or die "$new: $!";

my ($ports_already_handled,$pasv_already_handled);
while (<$in>) {
    chomp;
    if (/^anonymous_enable/) {
	$_ = 'anonymous_enable=YES';
	next;
    }
    if (/^chroot_local_user/) {
	$_ = 'chroot_local_user=YES';
	next;
    }
    if (/^ls_recurse_enable/) {
	$_ = 'ls_recurse_enable=YES';
	next;
    }
    if (/ftpd_banner/) {
	$_ = 'ftpd_banner=Welcome to the modENCODE data server. Please login using the username "anonymous" and your email address. This data is also available as an Amazon cloud image. See http://data.modencode.org/modencode-cloud.html.';
    }
    $ports_already_handled++ if /^pasv_(?:min|max)_port/;
    $pasv_already_handled++ if /^pasv_address/;
} continue {
    print $out $_,"\n";
}

print $out <<END unless $ports_already_handled;
# fix for timeouts on directory listings -- current firewall rules must allow this
pasv_min_port=12000
pasv_max_port=12200
END
    ;
print $out <<END unless $pasv_already_handled;
pasv_address=$public_ip
END
    ;
close $out;
rename $vsftpd_conf,"$vsftpd_conf.orig";
rename $new,$vsftpd_conf;
system 'sudo','/etc/init.d/vsftpd','restart';

exit 0;
