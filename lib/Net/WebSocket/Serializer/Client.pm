package Net::WebSocket::Serializer::Client;

use strict;
use warnings;

use Net::WebSocket::RNG ();

sub _create_new_mask {
    return Net::WebSocket::RNG::get()->bytes(4);
}

1;
