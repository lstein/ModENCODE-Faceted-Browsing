#!/usr/bin/perl

# this sends registration information to dev@modencode.org so that
# we can track (and justify to the NIH) the usage of the cloud resources.

use strict;
use FindBin '$RealBin';
use lib "$RealBin/../perl/share/perl","$RealBin/../lib";
use VM::EC2;
use HTTP::Request::Common;
use LWP::UserAgent;
use Module::Build;

use constant REGISTRATION_SERVER=>'http://gbrowse.modencode.org/cgi-bin/modencode_ami_registration';

my $is_image = shift;

# ask for confirmation at the terminal
if (-t STDIN && !$is_image) {
    print STDERR <<'END';
**Optional Registration**

In order to maintain funding for the modENCODE Amazon resources, we'd like to
record the fact that you are using them. Answering yes at the prompt will send
information about the version of the data and type of instance you are running.
No other information about you will be submitted.
END
#'
;
    exit 0 unless Module::Build->y_n("Do you wish to register this installation?",'y');
} else {
    # check whether user data has turned registration off
    my $metadata = VM::EC2->instance_metadata;
    my $userdata = $metadata->userData;
    exit 0 if $userdata =~ /noregister/;
}

my $metadata = VM::EC2->instance_metadata;

my $result = eval {
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request(POST(REGISTRATION_SERVER,
				     [imageId          => $metadata->imageId,
				      ancestorAmis     => join(',',$metadata->ancestorAmiIds),
				      instanceType     => $metadata->instanceType,
				      launchIndex      => $metadata->imageLaunchIndex,
				      availabilityZone => $metadata->availabilityZone,
				      attachType       => $is_image ? 'image' : 'data snapshot',
				     ]));
    die $response->status_line unless $response->is_success;
    my $content = $response->decoded_content;
    $content eq 'ok';
};

if ($@) {
    print STDERR "An error occurred during registration: $@\n";
 } else {
     print STDERR $result ? "Thank you. Your registration was sent successfully.\n"
	 : "An error occurred during registration. Thanks anyway.\n";
}


