package Fennec::Collector::Files;
use strict;
use warnings;

use base 'Fennec::Collector';

use Fennec::Runner;
use Fennec::File;
use Data::Dumper;

our %BADFILES;
our $SEMI_UNIQ = 1;

sub bad_files { \%BADFILES }

sub cull {
    my $self = shift;
    my $handle = $self->dirhandle;
    for my $file ( readdir( $handle )) {
        next if -d $file;
        next if $file =~ m/^\.+$/;
        my ($obj) = $self->read_and_unlink( $file );
        $_->handle( $obj ) for @{ $self->handlers };
    }
}

sub dirhandle {
    my $self = shift;
    unless( $self->{ dirhandle }) {
        my $path = $self->testdir;
        opendir( my $handle, $path ) || die( "Cannot open dir $path: $!" );
        $self->{ dirhandle } = $handle;
    }

    return $self->{ dirhandle };
}

sub start {
    my $self = shift;
    $self->SUPER::start(@_);
    $self->prepare;
}

sub finish {
    my $self = shift;
    $self->SUPER::finish(@_);
    my $handle = $self->{ dirhandle };
    close( $handle );
    $self->cleanup;
}

sub read_and_unlink {
    my $class = shift;
    my @out;
    for my $file ( @_ ) {
        next if $BADFILES{ $file };
        if( my $obj = $class->read( $file )) {
            push @out => $obj;
            unlink( $class->testdir . "/$file" );
        }
    }
    return @out;
}

sub read {
    my $class = shift;
    my ( $file ) = @_;
    my $obj = do( $class->testdir . "/$file" );
    if ( $obj ) {
        my $bless = $obj->{ bless };
        my $data = $obj->{ data };
        return bless( $data, $bless );
    }
    warn( "bad file: '$file' - $! - $@" );
    $BADFILES{$file} = [ $!, $@ ];
    return;
}

sub write {
    my $self = shift;
    my ( $output ) = @_;
    my $out = $output->serialize;
    my $file = $self->testdir . "/$$-" . $SEMI_UNIQ++ . '.res';
    open( my $HANDLE, '>', $file ) || warn "Error writing output:\n\t$file\n\t$!";
    print $HANDLE Dumper( $out ) || warn "Error writing output";
    close( $HANDLE ) || die( $! );
}

sub testdir { Fennec::File->root . "/_test" }

sub prepare {
    my $self = shift;
    $self->cleanup;
    my $path = $self->testdir;
    mkdir( $path ) unless -d $path;
}

sub cleanup {
    my $class = shift;
    return unless -d $class->testdir;
    opendir( my $TDIR, $class->testdir ) || die( $! );
    for my $file ( readdir( $TDIR )) {
        next if $file =~ m/^\.+$/;
        next if -d $class->testdir . "/$file";
        unlink( $class->testdir . "/$file" );
    }
    closedir( $TDIR );
    rmdir( $class->testdir ) || warn( "Cannot cleanup test dir: $!" );
}

1;