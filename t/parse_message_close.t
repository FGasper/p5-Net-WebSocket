#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

plan tests => 3;

use Net::WebSocket::Parser;

my @tests = (
    [
        "\x88\x00",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Frame'),
                    methods(
                        get_type => 'close',
                        get_payload => "",
                    ),
                    listmethods(
                        get_code_and_reason => [],
                    ),
                ),
                'goodbye - close (bare)',
            ) or diag explain $_;
        },
    ],
    [
        "\x88\x02\x03\xea",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Frame'),
                    methods(
                        get_type => 'close',
                        get_payload => "\x03\xea",
                    ),
                    listmethods(
                        get_code_and_reason => [ 1002, "" ]
                    ),
                ),
                'goodbye - close (with code)',
            ) or diag explain $_;
        },
    ],
    [
        "\x88\x0a\x03\xeaGoodbye\x0a",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Frame'),
                    methods(
                        get_type => 'close',
                        get_payload => "\x03\xeaGoodbye\x0a",
                    ),
                    listmethods(
                        get_code_and_reason => [ 1002, "Goodbye\x0a" ]
                    ),
                ),
                'goodbye - close (with code & reason)',
            ) or diag explain $_;
        },
    ],
);

my $full_buffer = join( q<>, map { $_->[0] } @tests );
open my $bfh, '<', \$full_buffer;
my $parser = Net::WebSocket::Parser->new( $bfh );

for my $t (@tests) {

    my $frame = $parser->get_next_frame();

    $t->[1]->() for $frame;
}
