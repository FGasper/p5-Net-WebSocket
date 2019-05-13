#!/usr/bin/env perl

use Test::More;
use Test::FailWarnings;

plan tests => 39;

use Net::WebSocket::Frame::text ();

my $frame = Net::WebSocket::Frame::text->new( payload => 123123 );

is( $frame->get_rsv(), 0, 'default frame RSV flags = 0' );

ok(
    !$frame->has_rsv1(),
    'RSV1 is off',
);

ok(
    !$frame->has_rsv2(),
    'RSV2 is off',
);

ok(
    !$frame->has_rsv3(),
    'RSV3 is off',
);

#----------------------------------------------------------------------

for my $rsv ( 0 .. 7 ) {
    $frame->set_rsv($rsv);

    is( $frame->get_rsv(), $rsv, "set RSV: $rsv" );

    is(
        !!$frame->has_rsv1(),
        !!($rsv & 4),
        "RSV1 when RSV=$rsv",
    );

    is(
        !!$frame->has_rsv2(),
        !!($rsv & 2),
        "RSV2 when RSV=$rsv",
    );

    is(
        !!$frame->has_rsv3(),
        !!($rsv & 1),
        "RSV3 when RSV=$rsv",
    );
}

#----------------------------------------------------------------------

$frame->set_rsv1();
ok(
    $frame->has_rsv1(),
    'RSV1 is on after set_rsv1()',
);

$frame->set_rsv(0);

$frame->set_rsv2();
ok(
    $frame->has_rsv2(),
    'RSV2 is on after set_rsv2()',
);

$frame->set_rsv(0);

$frame->set_rsv3();
ok(
    $frame->has_rsv3(),
    'RSV3 is on after set_rsv3()',
);
