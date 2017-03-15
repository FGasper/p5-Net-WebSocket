package Net::WebSocket::Endpoint::Server;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Endpoint
    Net::WebSocket::SerializerBase
    Net::WebSocket::Masker::Server
);

1;
