#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 10;

use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Endpoint::Client ();

my $msg = Net::WebSocket::Endpoint::Client->create_message( 'text', 'Hello!' );
isa_ok( $msg, 'Net::WebSocket::Message', 'client create_message' );
is( $msg->get_payload(), 'Hello!', '… and the payload matches' );
is(
    0 + @{ [ $msg->get_frames() ] },
    1,
    'message has 1 frame',
);
my $frame = ($msg->get_frames())[0];
isa_ok( $frame, 'Net::WebSocket::Frame::text', '… and that frame is typed as expected' );
like( $frame->get_mask_bytes(), qr<\A....\z>, '… and that frame is masked' );

$msg = Net::WebSocket::Endpoint::Server->create_message( 'binary', 'Hello!' );
isa_ok( $msg, 'Net::WebSocket::Message', 'client create_message' );
is(
    0 + @{ [ $msg->get_frames() ] },
    1,
    'message has 1 frame',
);
$frame = ($msg->get_frames())[0];
isa_ok( $frame, 'Net::WebSocket::Frame::binary', '… and that frame is typed as expected' );
is( $frame->get_mask_bytes(), q<>, '… and that frame is NOT masked' );
is( $frame->get_payload(), 'Hello!', '… and the payload matches' );
