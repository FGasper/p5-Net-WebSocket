package Net::WebSocket::Endpoint::Client;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Endpoint
);

use Net::WebSocket::Mask ();

sub FRAME_MASK_ARGS {
    return( mask => Net::WebSocket::Mask::create() );
}

1;
