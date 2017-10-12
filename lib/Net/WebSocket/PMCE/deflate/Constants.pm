package Net::WebSocket::PMCE::deflate::Constants;

use strict;
use warnings;

use constant {
    TOKEN => 'permessage-deflate',
    INITIAL_FRAME_RSV => 0b100,  #RSV1
};

use constant VALID_MAX_WINDOW_BITS => (8 .. 15);

1;
