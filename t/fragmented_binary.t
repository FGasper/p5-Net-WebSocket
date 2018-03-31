#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    eval 'use autodie';
}

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 4;

use FindBin;
use IO::Framed::Read;
use IO::Framed::Write;
use File::Slurp;
use File::Temp;
use Text::Control;

use Net::WebSocket::Parser ();
use Net::WebSocket::Endpoint::Server ();

my $in = File::Slurp::read_file("$FindBin::Bin/assets/fragmented_binary");
$in =~ tr<\n><>d;
$in = Text::Control::from_hex($in);

my ($fh, $path) = File::Temp::tempfile( CLEANUP => 1 );
print {$fh} $in;
close $fh;

open my $pre_ws_fh, '<', $path;
my $io = IO::Framed::Read->new($pre_ws_fh);
my $parser = Net::WebSocket::Parser->new( $io );

open my $out_fh, '>', \do { my $v = q<> };
my $io_out = IO::Framed::Write->new($out_fh);

my $ept = Net::WebSocket::Endpoint::Server->new(
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

my $should_be = File::Slurp::read_file("$FindBin::Bin/assets/fragmented_binary_should_be");

is(
    $msg->get_payload(),
    $should_be,
    'read fragmented payload',
);
