package Fennec::File::Module;
use strict;
use warnings;

use base 'Fennec::File';

sub valid_file {
    my $self = shift;
    my ( $file ) = @_;
    return $file =~ m{/t/.*\.pm$} ? 1 : 0;
}

sub load_file {
    my $self = shift;
    my $file = $self->filename;
    require $file;
}

sub paths { 't/' }

1;