package Net::WebSocket::Serializer::Server;

use strict;
use warnings;

use parent qw( Net::WebSocket::Serializer );

sub _create_new_mask { q<> }

1;
