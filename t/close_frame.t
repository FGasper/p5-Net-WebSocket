#!/usr/bin/env perl

use Net::WebSocket::Constants ();
use Net::WebSocket::Frame::close ();

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 27;

my $frame = Net::WebSocket::Frame::close->new();

is_deeply(
    [ $frame->get_code_and_reason() ],
    [ Net::WebSocket::Constants::status_name_to_code('EMPTY_CLOSE'), q<> ],
    "no code nor reason",
);

while ( my ($k, $v) = each %{ Net::WebSocket::Constants::STATUS() } ) {
    next if $k eq 'EMPTY_CLOSE';

    my $frame = Net::WebSocket::Frame::close->new(
        code => $k,
        reason => "Because $k",
    );

    is_deeply(
        [ $frame->get_code_and_reason() ],
        [ $v, "Because $k" ],
        "$k with code and reason",
    );

    $frame = Net::WebSocket::Frame::close->new(
        code => $k,
    );

    is_deeply(
        [ $frame->get_code_and_reason() ],
        [ $v, q<> ],
        "$k with just code",
    );
}
