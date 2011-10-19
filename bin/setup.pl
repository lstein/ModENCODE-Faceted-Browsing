#!/usr/bin/perl

use strict;

print STDERR "*** Installing Perl library dependencies...\n";
system "/modencode/bin/install_libraries.pl";

print STDERR "*** Attaching data snapshots listed in /modencode/VOLUMES.txt\n";
system "/modencode/bin/attach_snapshots.pl";
system "sudo /modencode/bin/update_fstab.pl";

print STDERR "*** Creating browse database.\n";
system "/modencode/bin/generate_faceted_database.pl";

print STDERR "*** Creating hierarchical tree of data sets.\n";
system "/modencode/bin/generate_ftp_tree.pl";

print STDERR "*** Installing vsftpd and apache servers.\n";
system "sudo apt-get install vsftpd apache2";

print STDERR "*** Configuring vsftpd and apache2.\n";
system "sudo /modencode/bin/configure_vsftpd.pl";
system "sudo /modencode/bin/configure_apache2.pl";

print STDERR "*** Opening ports for web and FTP access.\n";
system "/modencode/bin/open_ports.pl";


