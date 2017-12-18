#!/usr/bin/env perl

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 7;

use Net::WebSocket::Frame::text ();

my $frame_class = 'Net::WebSocket::Frame::text';

sub _to_hex {
    return sprintf( '%v.02x', shift );
}

my $zero = $frame_class->new( payload => q<> );
is(
    _to_hex( substr $zero->to_bytes(), 1, 1 ),
    '00',
    'zero-byte frame',
);

my $one = $frame_class->new( payload => q<x> );
is(
    _to_hex( substr $one->to_bytes(), 1, 1 ),
    '01',
    'one-byte frame',
);

my $max_simple = $frame_class->new( payload => ('x' x 125) );
is(
    _to_hex( substr $max_simple->to_bytes(), 1, 1 ),
    '7d',
    '125-byte frame (max “small” size)',
);

my $min_medium = $frame_class->new( payload => ('x' x 126) );
is(
    _to_hex( substr $min_medium->to_bytes(), 1, 3 ),
    "7e.00.7e",
    'min bytes in “medium” size encoding',
);

my $max_medium = $frame_class->new( payload => ('x' x 65535) );
is(
    _to_hex( substr $max_medium->to_bytes(), 1, 3 ),
    "7e.ff.ff",
    'max bytes in “medium” size encoding',
);

my $min_large = $frame_class->new( payload => ('x' x 65536) );

is(
    _to_hex( substr $min_large->to_bytes(), 1, 9 ),
    "7f.00.00.00.00.00.01.00.00",
    'min bytes in “large” size encoding',
);

if (!$frame_class->isa('Net::WebSocket::Base::DataFrame')) {
    die 'bad inheritance assumption!';
}

SKIP: {
    if (!$Net::WebSocket::Base::DataFrame::_can_pack_Q) {
        skip 'Already tested 32-bit pack of >16-bit size', 1;
    }

    local $Net::WebSocket::Base::DataFrame::_can_pack_Q = 0;

    is(
        _to_hex( substr $min_large->to_bytes(), 1, 9 ),
        "7f.00.00.00.00.00.01.00.00",
        'min bytes in “large” size encoding, forced 32-bit test',
    );
}
