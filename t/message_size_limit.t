#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    eval 'use autodie';
}

use Test::More;
use Test::FailWarnings;
use Test::Exception;

use File::Temp;
use IO::Framed::Read;
use IO::Framed::Write;

use Net::WebSocket::Parser ();
use Net::WebSocket::Endpoint::Client ();

sub _test {
    my ($label, $in, $size, $limit) = @_;

    my ($fh, $path) = File::Temp::tempfile( CLEANUP => 1 );
    print {$fh} $in;
    close $fh;

    open my $pre_ws_fh, '<', $path;
    my $io = IO::Framed::Read->new($pre_ws_fh);
    my $parser = Net::WebSocket::Parser->new( $io );

    my $out_fh = File::Temp::tempfile();
    my $io_out = IO::Framed::Write->new($out_fh);

    my $ept = Net::WebSocket::Endpoint::Client->new(
        parser => $parser,
        out => $io_out,
        max_receive_message_length => $limit,
    );

    throws_ok(
        sub { 1 while !$ept->get_next_message() },
        'Net::WebSocket::X::ReceivedOversizedMessage',
        "$label: small message: error when oversized",
    );

    my $err = $@;

    like(
        "$@",
        qr<$size>,
        "$label: message size limit is included",
    );

    like(
        "$@",
        qr<$size>,
        "$label: actual size of the message is included",
    );
}

_test(
    'fragments exceed limit',
    join( q<>,
        "\x02\x7d",
        ("a" x 125),
        "\x80\x7d",
        ("b" x 125),
    ),
    250,
    200,
);

_test(
    'small',
    join( q<>,
        "\x82\x7d",
        ("a" x 125),
    ),
    125,
    100,
);

_test(
    'medium',
    join( q<>,
        "\x82\x7e",
        pack('n', 126),
        ("a" x 126),
    ),
    126,
    125,
);

_test(
    'large',
    join( q<>,
        "\x82\x7f",
        pack('x4 N', 126),
        ("a" x 126),
    ),
    126,
    125,
);

done_testing;
