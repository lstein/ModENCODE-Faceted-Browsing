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
my $zone        = $meta->availabilityZone;

my $f;

my $Changed;

warn "Reading volume snapshot list...\n";
my $Snapshots      = read_snapshot_list();
my %Name2snapshot  = map {$Snapshots->{$_}{name}=>$_} keys %$Snapshots;

# get list of volumes mounted on this filesystem
warn "Gathering information about volumes attached to this instance...\n";
my $Attached       = read_attached_list();

# determine which snapshots are already attached
my %Mismatched;
for my $name (keys %$Attached) {
    if ($Attached->{$name}{snapshotId} eq $Name2snapshot{$name}) {
	my $snapId = $Name2snapshot{$name};
	warn "$snapId ($name) is already attached. Skipping...\n";
	delete $Snapshots->{$snapId};
    } else {
	$Mismatched{$name}++;
    }
}

if (my @mounted = sort keys %Mismatched) {
    my $action = prompt_for_disposition(\@mounted);
    skip(\@mounted,$Snapshots)   if $action eq 'skip';
    detach(\@mounted,$Attached)  if $action eq 'detach';
    destroy(\@mounted,$Attached) if $action eq 'destroy';
    $Changed++ if $action eq 'detach' or $action eq 'destroy';
}

if (keys %$Snapshots) {
    warn "Creating data volumes. This may take a while...\n";
    my @volumes = create_volumes($Snapshots);

    warn "Attaching data volumes to this instance...\n";
    my @attachments = attach_volumes($Snapshots);

    warn "Mounting data volumes on /modencode/all_files/...\n";
    mount_volumes(\@attachments,$Snapshots);

    $Changed++;
} else {
    print STDERR "No snapshots need to be added at this time.\n";
}

if ($Changed) {
    warn "Refreshing mount information in fstab...\n";
    system 'sudo',"$RealBin/update_fstab.pl",'--ignore_bind';
}

exit 0;

sub volume_name {
    my $description = shift;
    my ($genus,$species,$format) = $description  =~ /modENCODE ([A-Z])\. (\w+) (\w+) data/ 
	or die "failed to derive name from description";
    my ($part)      =  $description =~ /part (\d+)/;
    $part         ||= 1;
    return lc($genus).substr($species,0,3).'-'.$format.'-'.$part;
}

sub read_snapshot_list {
    open my $f,'<','/modencode/DATA_SNAPSHOTS.txt' or die "DATA_SNAPSHOTS.txt: $!";
    my %snapshots;
    while (<$f>) {
	chomp;
	next if /^\s*#/;
	my ($snapid,$description) = /^([\w-]+)\s+(.+)/;

	my $snap                            = $ec2->describe_snapshots($snapid) or next;
	$snapshots{$snap}{name}             = volume_name($description);
	$snapshots{$snap}{description}      = $description;
	$snapshots{$snap}{snapshot}         = $snap;
    }
    close $f;
    return \%snapshots;
}

sub read_attached_list {
    my %attached;

    my $instance           = $ec2->describe_instances($instance_id);
    my @block_devices      = $instance->blockDeviceMapping;

    for my $bd (@block_devices) {
	my $volume = $bd->volume            or next;
	my $snap   = $volume->from_snapshot or next;
	my $device = ebs_to_local($bd->deviceName);
	$device    =~ m!/dev/(?:sd|xvd)[g-z]\d+! or next;
	my $name   = volume_name($snap->description) or next;
	$attached{$name}{snapshotId} = $snap;
	$attached{$name}{volumeId}   = $volume;
	$attached{$name}{attachDev}  = $device;
    }

    # in addition, find mounted volumes
    open $f,'<','/etc/mtab' or die "/etc/mtab: $!";
    while (<$f>) {
	chomp;
	my ($device,$mount) = split /\s+/;
	my ($name)          = $mount =~ m!^/modencode/data/all_files/([^/]+)$!;
	$name or next;
	$attached{$name}{mountDev} = $device;
    }
    close $f;
    return \%attached;
}

sub prompt_for_disposition {
    my $mounted = shift;
    print STDERR "\n** One or more data volumes are already attached, but their snapshots are not listed in DATA_SNAPSHOTS.txt. **\n";
    print STDERR "  Volumes: ",join(", ",@$mounted),"\n";
    print STDERR <<END;
"Skip": leave these volumes alone and skip mounting the corresponding snapshot(s).
"Unmount": unmount and detach the volumes, but leave their volumes intact. Mount all snapshots.
"Destroy": unmount and detach the volumes, then DESTROY them.  Mount all snapshots.
END
    my $answer = '';
    while ($answer !~ /^[sud]$/i) {
	print STDERR "(S)kip, (U)nmount & detach, or (D)estroy these volume(s)? ";
	chomp($answer = <>);
    }
    return   lc $answer eq 's' ? 'skip'
           : lc $answer eq 'u' ? 'detach'
	   : lc $answer eq 'd' ? 'destroy'
	   : 'skip';
}

# delete indicated volumes from the list to be attached & mounted
sub skip {
    my ($mounted,$Snapshots) = @_;
    my %delete = map {$_=>1} @$mounted;
    for my $snapId (keys %$Snapshots) {
	delete $Snapshots->{$snapId} if $delete{$Snapshots->{$snapId}{name}};
    }
}

sub detach {
    my ($mounted,$Attached) = @_;
    my @detached;
    for my $name (@$mounted) {
	my $volumeId = $Attached->{$name}{volumeId};
	my $mountDev = $Attached->{$name}{mountDev};
	if ($mountDev) {
	    warn "unmounting $name from $mountDev...\n";
	    system "sudo umount $mountDev" and die "Couldn't umount $mountDev";
	}
	print STDERR "Detaching volume $volumeId...\n";
	push @detached,$ec2->detach_volume($volumeId);
    }
    print STDERR "Waiting for detachments...\n";
    $ec2->wait_for_attachments(@detached);
}

sub destroy {
   my ($mounted,$Attached) = @_;
   detach($mounted,$Attached);
   for my $name (@$mounted) {
       my $volumeId = $Attached->{$name}{volumeId};
       $ec2->delete_volume($volumeId) or die "Couldn't delete $volumeId";
   }
}

sub create_volumes {
    my $Snapshots = shift;

    my @volumes;
    for my $snap (keys %$Snapshots) {
	my $volume = $Snapshots->{$snap}{snapshot}->create_volume(-zone=>$zone);
	$volume->add_tag(Name => $Snapshots->{$snap}{description});
	$Snapshots->{$snap}{volume} = $volume;
	push @volumes,$volume;
    }

    # wait for all volumes to become available
    my $status = $ec2->wait_for_volumes(@volumes);
    my @failed = grep {$status->{$_} ne 'available'} @volumes;
    warn "One or more volumes could not be created: @failed\n" if @failed;
    @volumes   = grep {$status->{$_} eq 'available'} @volumes;
    return @volumes;
}

sub attach_volumes {
    my $Snapshots = shift;

    my @attachments;
    for my $snap (keys %$Snapshots) {
	my ($local_device,$ebs_device)        = unused_block_device('g');  # start at /dev/sdg
	$Snapshots->{$snap}{local_device}     = $local_device;
	$Snapshots->{$snap}{ebs_device}       = $ebs_device;
	my $volume = $Snapshots->{$snap}{volume}     or die;
	my $dev    = $Snapshots->{$snap}{ebs_device} or die;
	warn "Attaching $Snapshots->{$snap}{name} to unused disk device $dev\n";
	push @attachments,$volume->attach($instance_id,$ebs_device);
}

    warn "Waiting for attachments to complete...\n";
    my $status = $ec2->wait_for_attachments(@attachments);
    my @failed = grep {$status->{$_} ne 'attached'} @attachments;
    warn "One or more volumes could not be attached: @failed\n" if @failed;
    return grep {$status->{$_} eq 'attached'} @attachments;
}

sub mount_volumes {
    my ($attachments,$Snapshots) = @_;

    for my $a (@$attachments) {
	my $vol    = $a->volume or die;
	$vol->delete_on_termination('true');
	my $snap   = $vol->snapshotId or die;
	my $device = $Snapshots->{$snap}{local_device} or die;
	my $name   = $Snapshots->{$snap}{name}         or die;
	my $mntpt  = "/modencode/data/all_files/$name";
	make_path($mntpt);
	system 'sudo','mount',$device,$mntpt,'-o','ro';
    }
}


__END__
