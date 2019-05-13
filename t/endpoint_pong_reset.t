#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;
use Test::Exception;

use File::Slurp ();
use File::Temp ();

use IO::Framed ();

use Net::WebSocket::Frame::pong      ();
use Net::WebSocket::Parser           ();
use Net::WebSocket::Endpoint::Server ();

plan tests => 3;

#----------------------------------------------------------------------

(undef, my $infile) = File::Temp::tempfile( CLEANUP => 1 );
open my $infh, '<', $infile;

(undef, my $outfile) = File::Temp::tempfile( CLEANUP => 1 );
open my $outfh, '>', $outfile;

my $parser = Net::WebSocket::Parser->new( IO::Framed->new($infh) );
my $out = IO::Framed->new($outfh);

my $ept = Net::WebSocket::Endpoint::Server->new(
    parser => $parser,
    out => $out,
);

$ept->check_heartbeat();

open my $re_in_fh, '<', $outfile;
my $reparser = Net::WebSocket::Parser->new( IO::Framed->new($re_in_fh) );
my $ping_frame = $reparser->get_next_frame();

#----------------------------------------------------------------------

$ept->check_heartbeat();
$ept->check_heartbeat();

open my $send_fh, '>', $infile;
syswrite $send_fh, Net::WebSocket::Frame::pong->new(
    payload => $ping_frame->get_payload(),
)->to_bytes();

$ept->get_next_message();   #will read the pong

$ept->check_heartbeat();

ok(
    !$ept->sent_close_frame(),
    '3 pings, then a pong, and another heartbeat = not closed',
);

$ept->check_heartbeat();

ok(
    !$ept->sent_close_frame(),
    '… and another heartbeat = not closed',
);

$ept->check_heartbeat();

ok(
    !$ept->sent_close_frame(),
    '… and still another heartbeat = not closed',
);
