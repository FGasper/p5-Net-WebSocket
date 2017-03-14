package Net::WebSocket::Constants;

use strict;
use warnings;

use constant OPCODE => {
    continuation => 0,
    text => 1,
    binary => 2,
    close => 8,
    ping => 9,
    pong => 10,
};

use constant CONTROL_TYPES => qw( close ping pong );

use constant PROTOCOL_VERSION => 13;

my %opcode_type;

sub opcode_to_type {
    my ($opcode) = @_;

    %opcode_type = reverse %{ OPCODE() } if !%opcode_type;

    return $opcode_type{$opcode};
}

1;
