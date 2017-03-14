package Net::WebSocket::SerializeFilehandle;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Serializer
    Net::WebSocket::ReadFilehandle
);

#stream a set number of bytes
sub stream_bytes { ... }

#stream the remainder of what’s in the filehandle
sub flush_stream { ... }

1;
