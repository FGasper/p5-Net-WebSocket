#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

plan tests => 6;

use Net::WebSocket::Endpoint ();
use Net::WebSocket::ParseString ();
use Net::WebSocket::Serializer::Server ();

my $out_buffer = q<>;

my $out_parser = Net::WebSocket::ParseString->new( \$out_buffer );

my @tests = (
    [
        "\x81\x06Hello\x0a",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Message'),
                    methods(
                        get_type => 'text',
                        get_payload => "Hello\x0a",
                    ),
                ),
                'single hello - text',
            ) or diag explain $_;
        },
    ],
    [
        "\x82\x0dHello-binary\x0a",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Message'),
                    methods(
                        get_type => 'binary',
                        get_payload => "Hello-binary\x0a",
                    ),
                ),
                'single hello - binary',
            ) or diag explain $_;
        },
    ],
    [
        "\x89\x0bHello-ping\x0a" . "\x82\x00",
        sub {
            cmp_deeply(
                $out_parser->get_next_frame(),
                all(
                    Isa('Net::WebSocket::Frame'),
                    methods(
                        get_type => 'pong',
                        get_payload => "Hello-ping\x0a",
                    ),
                ),
                'hello - ping',
            ) or diag explain $_;
        },
    ],
    [
        "\x02\x06Hello\x0a" . "\x80\x06Hello\x0a",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Message'),
                    methods(
                        get_type => 'binary',
                        get_payload => "Hello\x0aHello\x0a",
                    ),
                ),
                'fragmented double hello',
            ) or diag explain $_;
        },
    ],
    [
        "\x02\x06Hello\x0a" . "\x89\x00" . "\x80\x06Hello\x0a",
        sub {
            cmp_deeply(
                $_,
                all(
                    Isa('Net::WebSocket::Message'),
                    methods(
                        get_type => 'binary',
                        get_payload => "Hello\x0aHello\x0a",
                    ),
                ),
                'fragmented double hello with ping in the middle',
            ) or diag explain $_;

            my $resp = $out_parser->get_next_frame();

            cmp_deeply(
                $resp,
                all(
                    Isa('Net::WebSocket::Frame'),
                    methods(
                        get_type => 'pong',
                        get_payload => q<>,
                        get_fin => 1,
                        is_control_frame => 1,
                        get_mask_bytes => q<>,
                    ),
                ),
                'ping in the middle comes out as expected',
            ) or diag explain [$resp, sprintf( "%v.02x", $out_buffer )];
        },
    ],
);

my $full_buffer = join( q<>, map { $_->[0] } @tests );
my $parser = Net::WebSocket::ParseString->new( \$full_buffer );

open my $out_fh, '>>', \$out_buffer;

my $ept = Net::WebSocket::Endpoint->new(
    parser => $parser,
    serializer => 'Net::WebSocket::Serializer::Server',
    out => $out_fh,
);

for my $t (@tests) {
    substr( $out_buffer, 0 ) = q<>;

    my $msg;

    while (1) {
        $msg = $ept->get_next_message();
        last if $msg;
    }

    $t->[1]->() for $msg;
}
