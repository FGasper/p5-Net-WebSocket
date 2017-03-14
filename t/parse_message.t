#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

plan tests => 7;

use Net::WebSocket::ParseString;

use Carp::Always;

my @control_frames;

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
                $control_frames[0],
                all(
                    Isa('Net::WebSocket::Frame::ping'),
                    methods(
                        get_type => 'ping',
                        get_payload => "Hello-ping\x0a",
                    ),
                ),
                'hello - ping',
            ) or diag explain $_;
        },
    ],
    [
        "\x8a\x0bHello-pong\x0a" . "\x82\x00",
        sub {
            cmp_deeply(
                $control_frames[0],
                all(
                    Isa('Net::WebSocket::Frame::pong'),
                    methods(
                        get_type => 'pong',
                        get_payload => "Hello-pong\x0a",
                    ),
                ),
                'hello - pong',
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

            cmp_deeply(
                \@control_frames,
                [
                    all(
                        Isa('Net::WebSocket::Frame'),
                        methods(
                            get_type => 'ping',
                            get_payload => q<>,
                            get_fin => 1,
                            is_control_frame => 1,
                            get_mask_bytes => q<>,
                        ),
                    ),
                ],
                'ping in the middle comes out as expected',
            );
        },
    ],
);

my $full_buffer = join( q<>, map { $_->[0] } @tests );
my $parser = Net::WebSocket::ParseString->new( \$full_buffer );

for my $t (@tests) {
    @control_frames = ();

    my $msg = $parser->get_next_message( sub { push @control_frames, @_; } );

    $t->[1]->() for $msg;
}
