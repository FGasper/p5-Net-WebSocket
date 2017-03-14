package Net::WebSocket::DataMessage;

use parent qw(
    Net::WebSocket::Message
    Net::WebSocket::Typed
);

use constant is_control_message => 0;

1;
