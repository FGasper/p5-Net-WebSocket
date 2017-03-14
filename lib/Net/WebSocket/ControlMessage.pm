package Net::WebSocket::ControlMessage;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Message
    Net::WebSocket::Typed
);

use constant is_control_message => 1;

1;
