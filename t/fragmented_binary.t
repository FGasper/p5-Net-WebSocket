#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    eval 'use autodie';
}

use Test::More;
use Test::FailWarnings;

plan tests => 4;

use FindBin;
use IO::Framed::Read;
use IO::Framed::Write;
use File::Temp;

use Net::WebSocket::Parser ();
use Net::WebSocket::Endpoint::Client ();

my $in = join( q<>,
    "\x02\x7f",
    "\x00\x00\x00\x00\x00\x01\xff\xb5", #130997
    ("a" x 130997),
    "\x00\x7f",
    "\x00\x00\x00\x00\x00\x02\x00\x00",
    ("b" x 131072),
    "\x00\x7f",
    "\x00\x00\x00\x00\x00\x02\x00\x00",
    ("c" x 131072),
    "\x80\x7e",
    ".\x8f",
    ("d" x 11919),
);

my $should_be = join( q<>,
    ("a" x 130997),
    ("b" x 131072),
    ("c" x 131072),
    ("d" x 11919),
);

my ($fh, $path) = File::Temp::tempfile( CLEANUP => 1 );
print {$fh} $in;
close $fh;

open my $pre_ws_fh, '<', $path;
my $io = IO::Framed::Read->new($pre_ws_fh);
my $parser = Net::WebSocket::Parser->new( $io );

my $io_out = IO::Framed::Write->new(\*STDERR);

my $ept = Net::WebSocket::Endpoint::Client->new(
    parser => $parser,
    out => $io_out,
);

is(
    $ept->get_next_message(),
    undef,
    'first fragment',
);

is(
    $ept->get_next_message(),
    undef,
    'second fragment',
);

is(
    $ept->get_next_message(),
    undef,
    'third fragment',
);

my $msg = $ept->get_next_message();

my @frames = $msg->get_frames();

is(
    $msg->get_payload(),
    $should_be,
    'read fragmented payload',
);
