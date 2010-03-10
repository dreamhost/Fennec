package Fennec::Files;
use strict;
use warnings;

use Fennec::Runner::Root;
use Fennec::Result;
use File::Find qw/find/;
use Fennec::Util qw/add_accessors/;
use Try::Tiny;
use Carp;
use base 'Exporter';

add_accessors qw/bad_files types/;

our @EXPORT_OK = qw/add_to_wanted/;
our %WANTED;

sub add_to_wanted {
    my ( $name, $match, $loader ) = @_;
    croak( "Must provide a name to 'add_to_wanted()'" )
        unless $name;
    croak( "$name is already defined as a file type" )
        if $WANTED{ $name };
    croak( "Second argument to 'add_to_wanted()' must be a regex or coderef" )
        unless $match and (ref $match eq 'Regexp' || ref $match eq 'CODE' );
    croak( "Third argument to 'add_to_wanted()' must be a coderef" )
        unless $loader and ref $loader eq 'CODE';

    $WANTED{ $name } = [ $match, $loader ];
}

sub wanted { \%WANTED }

sub new {
    my $class = shift;
    $class->_load_plugins;
    my @types = @_ ? @_ : keys %WANTED;
    my $self = bless({ types => \@types, bad_files => [] }, $class );
    return $self;
}

sub new_from_list {
    my $class = shift;
    my ( $list ) = @_;
    $class->_load_plugins;

    add_to_wanted(
        'Perl',
        qr{\.pm$},
        sub { my $file = shift; eval "require '$file'" || die( $@ )}
    );

    my @types = keys %WANTED;
    my $self = bless({ types => \@types, bad_files => [] }, $class );
    $self->_find( $list );
    return $self;
}

sub _load_plugins {
    my $class = shift;
    unless( $class->can( 'plugins' )) {
        require Module::Pluggable;
        Module::Pluggable->import( require => 1, search_path => [ 'Fennec::Files' ]);
        $class->plugins;
    }
}

sub list {
    my $self = shift;
    $self->_find unless $self->{ list };
    return @{ $self->{ list } };
}

sub _find {
    my $self = shift;
    my ( $provided ) = @_;

    my @list;
    my $wanted = sub {
        no warnings 'once';
        my $file = $File::Find::name;
        return if $Fennec::Runner::SINGLETON
               && grep { $file =~ $_ } @{ Fennec::Runner->get->ignore };
        return unless my ($type) = grep {
            my $check = $WANTED{ $_ }->[0];
            ref $check eq 'Regexp'
                ? $file =~ $check
                : $check->( $file );
        } @{ $self->types };
        push @list => [ $type, $file ];
    };

    if ( $provided ) {
        for my $file ( @$provided ) {
            no warnings 'once';
            local $File::Find::name = $file;
            $wanted->( $file );
        }
    }
    else {
        my $root = Fennec::Runner::Root->new->path;
        my @paths = ( "$root/t", "$root/lib" );
        find( $wanted, @paths ) if @paths;
    }
    $self->{ list } = \@list;
}

sub load {
    my $self = shift;
    for my $item ( $self->list ) {
        my %existing = map { $_ => 1 } keys %{ Fennec::Runner->get->tests };
        try {
            $WANTED{ $item->[0] }->[1]->( $item->[1] ) || die( "Loader did not return true" );
        }
        catch {
            push @{ $self->bad_files } => [ $item->[1], $_ ];

            # If loading the file added any tests remove them, they cannot be
            # trusted after a load failure.
            delete Fennec::Runner->get->tests->{ $_ }
                for grep { !$existing{$_} }
                    keys %{ Fennec::Runner->get->tests };

            # Immedietly report the error as a test failure
            Fennec::Runner->get->direct_result( Fennec::Result->new(
                result => 0,
                name   => $item->[1],
                diag   => [ "Failure loading file", $_ ],
                case   => undef,
                set    => undef,
                test   => undef,
                line   => "N/A",
                file   => $item->[1],
                benchmark   => undef,
            ));
        };
    }
}


1;