#!/usr/bin/perl

use strict;
# find modencode mounts

my $ignore_bind = $ARGV[0] && $ARGV[0] eq '--ignore_bind';

my (%mounts,%mountpoints);
open my $f,"<",'/etc/mtab' or die "/etc/mtab: $!";
while (<$f>) {
    chomp;
    my ($device,$mount,$type,$options)  = split /\s+/;
    next unless $mount =~ m!^/modencode!;
    $mounts{$device} = {mountpoint => $mount,
			type       => $type,
			options    => $options};
    $mountpoints{$mount}  = $device;
}
close $f;

open my $fstab,'<','/etc/fstab'      or die "/etc/fstab: $!";
open my $new,  '>','/etc/fstab.new'  or die "/etc/fstab.new: $!";
while (<$fstab>) {
    chomp;
    my ($device,$mtpoint,@rest) = split /\s+/;
    print $new $_,"\n" unless $mounts{$device} || $mountpoints{$mtpoint} || /^## Added by.+update_fstab\.pl/;
}
print $new "## Added by /modencode/bin/update_fstab.pl\n";
for my $device (sort keys %mounts) {
    next if $ignore_bind && $mounts{$device}{options} =~ /bind/;
    print $new join("\t",$device,
		    $mounts{$device}{mountpoint},
		    $mounts{$device}{type},
		    $mounts{$device}{options},
		    0,2),"\n";
}
close $new;
rename '/etc/fstab.new','/etc/fstab';

