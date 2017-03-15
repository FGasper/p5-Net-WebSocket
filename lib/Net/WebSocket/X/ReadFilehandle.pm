package Net::WebSocket::X::ReadFilehandle;

use strict;
use warnings;

use parent qw( Net::WebSocket::X::Base );

sub _new {
    my ($class, $err) = @_;

    return $class->SUPER::_new( "Read error: $err", OS_ERROR => $err );
}

sub errno_is {
    my ($self, $name) = @_;

    local $! = $self->get('OS_ERROR');
    return $!{$name};
}

1;
