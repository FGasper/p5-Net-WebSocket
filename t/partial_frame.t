#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    eval 'use autodie;';
}

use Test::More;
use Test::Deep;

use IO::Select ();

use Net::WebSocket::Parser ();

my @tests = (
    {
        label => 'from server',
        bytes => "\x81\x07" . "Sample.",
        payload => 'Sample.',
    },
    {
        label => 'from client',
        bytes => "\x81\x87" . "\x01\x02\x03\x04" . ("Sample." ^ "\x01\x02\x03\x04\x01\x02\x03"),
        payload => 'Sample.',
    },
    {
        label => 'from server, medium length',
        bytes => "\x81\x7e" . "\x01\x00" . ('x' x 256),
        payload => ('x' x 256),
    },
    {
        label => 'from server, long length',
        bytes => "\x81\x7f" . "\x00\x00\x00\x00\x00\x01\x00\x00" . ('x' x 2**16),
        payload => ('x' x 65536),
    },
);

plan tests => 0 + @tests;

for my $t (@tests) {
    my $bytes = $t->{'bytes'};

    pipe( my $rdr, my $wtr );

    $rdr->blocking(0);

    my $frame;

    my $parser = Net::WebSocket::Parser->new( $rdr );

    my $ios = IO::Select->new($rdr);

    alarm 300;

    do {
        syswrite $wtr, substr( $bytes, 0, 1, q<> );
        my ($rdrs_ar) = IO::Select->select( $ios );

        $frame = $parser->get_next_frame();
    } while !$frame;

    cmp_deeply(
        $frame,
        all(
            methods(
                get_type => 'text',
                get_payload => $t->{'payload'},
            ),
            Isa('Net::WebSocket::Frame'),
        ),
        "$t->{'label'}: partial frame",
    ) or diag explain $frame;
}

1;
