package EC2Utils;
use strict;

use base 'Exporter';
use Carp 'croak';

our @EXPORT_OK = qw(setup_credentials unused_block_device ebs_to_local);
our @EXPORT    = @EXPORT_OK;

sub setup_credentials {
    return if defined $ENV{EC2_ACCESS_KEY} && defined $ENV{EC2_SECRET_KEY};
    my $file = "$ENV{HOME}/.modencoderc";
    if (-e $file) {
	open my $f,'<',$file or die "$file: $!";
	while (<$f>) {
	    chomp;
	    my ($key,$value) = m/(\w+)\s*=\s*(.+)/ or next;
	    $ENV{$key} = $value;
	}
	close $f;
    }
    return if defined $ENV{EC2_ACCESS_KEY} && defined $ENV{EC2_SECRET_KEY};
    print STDERR "This script needs access to your EC2 account credentials in order to mount the ModENCODE data sets\n";
    $ENV{EC2_ACCESS_KEY} ||= prompt('Enter your EC2 access key: ');
    $ENV{EC2_SECRET_KEY} ||= prompt('Enter your EC2 secret key: ');
    if (yes_no('Save these into ~/.modencoderc? [Yn]','y')) {
	open my $f,'>',"$ENV{HOME}/.modencoderc" or die "$ENV{HOME}/.modencoderc: $!";
	chmod 0600,"$ENV{HOME}/.modencoderc";
	print $f "EC2_ACCESS_KEY=$ENV{EC2_ACCESS_KEY}\n";
	print $f "EC2_SECRET_KEY=$ENV{EC2_SECRET_KEY}\n";
	close $f;
    }
}

sub prompt {
    my $msg = shift;
    print STDERR $msg;
    chomp (my $result = <>);
    die "aborted" unless $result;
    $result;
}

sub yes_no {
    my ($prompt,$default) = @_;
    print STDERR $prompt;
    chomp (my $result = <>);
    $result      ||= $default;
    return $result =~ /^[yY]/;
}

my %Used;

# find an unused block device
sub unused_block_device {
    my $major_start = shift || 'f';

    # find a device that isn't in use.
    my $base =   -e "/dev/sda1"   ? "/dev/sd"
	       : -e "/dev/xvda1"  ? "/dev/xvd"
	       : '';
    my $ebs = '/dev/sd';
    die "Don't know what kind of disk device to use; neither /dev/sda1 nor /dev/xvda1 exists" unless $base;

    for my $major ($major_start..'p') {
	for my $minor (1..15) {
	    my $local_device = "${base}${major}${minor}";
	    next if -e $local_device;
	    next if $Used{$local_device}++;
	    my $ebs_device = "/dev/sd${major}${minor}";
	    return ($local_device,$ebs_device);
	}
    }
    return;
}

# possibly transform /dev/sdXX to /dev/xvdXX
sub ebs_to_local {
    my $ebs_device = shift;
    my ($major,$minor) = $ebs_device =~ m!(?:sd|xvd)([a-z])(\d+)!
	or croak "device $ebs_device is not in a known format";
    my $base =   -e "/dev/sda1"   ? "/dev/sd"
	       : -e "/dev/xvda1"  ? "/dev/xvd"
	       : '';
    $base or croak "Don't know what kind of disk device to use; neither /dev/sda1 nor /dev/xvda1 exists";
    return "$base$major$minor";
}


1;
