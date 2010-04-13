package Fennec::Workflow::Spec;
use strict;
use warnings;

use Fennec::Workflow qw/:subclass/;

use Fennec::Util::Alias qw/
    Fennec::Workflow
    Fennec::TestSet
    Fennec::TestSet::SubSet
    Fennec::TestSet::SubSet::Setup
    Fennec::Runner
    Fennec::Util::Accessors
/;

Accessors qw/ before_each before_all after_each after_all /;

sub init {
    my $self = shift;
    $self->$_([]) for qw/ before_each before_all after_each after_all /;
}

export it => sub {
    my $caller = caller;
    no strict 'refs';
    goto &{ $caller . '::tests' };
};

export describe => sub {
    Fennec::Workflow->current->add_item(
        __PACKAGE__->new( @_ )
    );
};

for my $name ( qw/ before_each before_all after_each after_all /) {
    export $name => sub(&) {
        my ($sub) = @_;
        Fennec::Workflow->current->add_item(
            Setup->new( $name => $sub )
        );
    };
}

sub testsets {
    my $self = shift;
    my @sets;
    my @_sets = ( @{ $self->_testsets }, map {( $_->testsets )} $self->workflows );

    if ( @{ $self->before_each } || @{ $self->after_each }) {
        for my $test ( @_sets ) {
            my $subset = SubSet->new(
                name => $self->name . ' (Setup/Teardown wrapper)',
                workflow => $self,
                file => $self->file,
                no_result => 1,
            );
            push @{ $subset->{tests} } => $test;
            $subset->setups( $self->before_each );
            $subset->teardowns( $self->after_each );
            push @sets => $subset;
        }
    }
    else {
        @sets = @_sets;
    }

    return @sets unless @{ $self->before_all } || @{ $self->after_all };

    my $subset = SubSet->new(
        name => $self->name,
        workflow  => $self,
        file => $self->file,
    );
    $subset->tests( \@sets );
    $subset->setups( $self->before_all );
    $subset->teardowns( $self->after_all );
    return ( $subset );
}

sub add_setup {
    my $self = shift;
    my ( $setup ) = @_;
    my $type = $setup->name;
    push @{ $self->$type } => $setup;
}

sub add_item {
    my $self = shift;
    my ( $item ) = @_;

    return $self->add_setup( $item )
        if $item->isa( Setup() );

    return $self->SUPER::add_item( $item );
}

1;