package Net::WebSocket::Arch;

use strict;
use warnings;

use constant CAN_PACK_64 => eval { pack 'Q', 0 } && 1;

1;
