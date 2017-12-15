#!/usr/bin/env perl

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 5;

use Net::WebSocket::Message ();
use Net::WebSocket::Frame::text ();
use Net::WebSocket::Frame::continuation ();

my @frames = (
    Net::WebSocket::Frame::text->new(
        payload => 123,
        fin => 0,
    ),
    Net::WebSocket::Frame::continuation->new(
        payload => 456,
        fin => 0,
    ),
    Net::WebSocket::Frame::continuation->new(
        payload => 789,
        fin => 1,
    ),
);

my $msg = Net::WebSocket::Message->new(@frames);

is( $msg->get_payload(), '123456789', 'get_payload()' );

is( $msg->get_type, $frames[0]->get_type(), 'get_type()' );
ok( !$msg->is_control_message, 'is_control_message()' );


is(
    $msg->to_bytes(),
    join( q<>, map { $_->to_bytes() } @frames ),
    'to_bytes()',
);

is_deeply(
    [ $msg->get_frames() ],
    \@frames,
    'get_frames()',
);
