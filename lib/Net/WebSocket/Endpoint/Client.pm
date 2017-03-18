package Net::WebSocket::Endpoint::Client;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Endpoint
);

use Net::WebSocket::Serializer::Client ();

use constant _SERIALIZER => 'Net::WebSocket::Serializer::Client';

1;
