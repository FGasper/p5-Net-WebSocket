package Net::WebSocket::Message::close;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::ControlMessage
);

sub get_code_and_reason {
    my ($self) = @_;

    return $self->[0]->get_code_and_reason();
}

1;
