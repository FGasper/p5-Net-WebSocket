package IO::WriteQueue;

#This module could be useful on its own.

use strict;
use warnings;

use IO::Syswrite ();

sub new {
    my ($class, $out_fh) = @_;

    return bless { _out_fh => $out_fh, _queue => [] }, shift;
}

sub add {
    my $self = shift;

    push @{$self->{'_queue'}}, \@_;

    return $self;
}

sub process {
    my ($self) = @_;

    while ( my $qi = $self->{'_queue'}[0] ) {
        if ( $self->_write_now_then_callback( @$qi ) ) {
            shift @{ $self->{'_queue'} };
        }
        else {
            last;
        }
    }
}

my $wrote;

sub _write_now_then_callback {
    my ($self) = shift;

    local $!;

    my $wrote = IO::Syswrite::write_all( $self->{'_out_fh'}, $_[0] ) or do {
        die IO::WriteQueue::X->create('WriteError', $!) if $!;
    };

    #completion case
    if ($wrote == length $_[0]) {
        $_[1]->() if $_[1];
        return 1;
    }

    #partial write, so reduce the buffer
    substr( $_[0], 0, $wrote ) = q<>;

    return 0;
}

#----------------------------------------------------------------------

package IO::WriteQueue::X;

use parent qw( X::Tiny );

#----------------------------------------------------------------------

package IO::WriteQueue::X::WriteError;

use parent qw( X::Tiny::Base );

sub _new {
    my ($class, $os_err) = @_;

    return $class->SUPER::_new( "Write error: [$os_err]", OS_ERROR => $os_err );
}

1;
