package Net::WebSocket::X::ReadFilehandle;

use strict;
use warnings;

use parent qw( Net::WebSocket::X::Base );

sub _new {
    my ($class, $err) = @_;

    return $class->SUPER::_new( "Read error: $err", OS_ERROR => $err );
}

1;
