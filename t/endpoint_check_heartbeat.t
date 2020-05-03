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

use Net::WebSocket::Parser           ();
use Net::WebSocket::Endpoint::Server ();

plan tests => 9;

#----------------------------------------------------------------------


open my $infh, '<', \do { my $v = q<> };

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
my $frame = $reparser->get_next_frame();
cmp_deeply(
    $frame,
    all(
        Isa('Net::WebSocket::Frame::ping'),
        methods(
            get_payload => re( qr<\#1> ),
        ),
    ),
    'check_heartbeat() sends 1st ping frame as expected',
);

#----------------------------------------------------------------------

$ept->check_heartbeat();

$frame = $reparser->get_next_frame();
cmp_deeply(
    $frame,
    all(
        Isa('Net::WebSocket::Frame::ping'),
        methods(
            get_payload => re( qr<\#2> ),
        ),
    ),
    'check_heartbeat() sends 2nd ping frame as expected',
);

#----------------------------------------------------------------------

$ept->check_heartbeat();

$frame = $reparser->get_next_frame();
cmp_deeply(
    $frame,
    all(
        Isa('Net::WebSocket::Frame::ping'),
        methods(
            get_payload => re( qr<\#3> ),
        ),
    ),
    'check_heartbeat() sends 3rd ping frame as expected',
);

for my $method ( qw( is_closed received_close_frame sent_close_frame ) ) {
    ok(
        !$ept->$method(),
        "!$method() before last check_heartbeat()",
    );
}

$ept->check_heartbeat();

$frame = $reparser->get_next_frame();
cmp_deeply(
    $frame,
    all(
        Isa('Net::WebSocket::Frame::close'),
        listmethods(
            get_code_and_reason => [
                Net::WebSocket::Constants::status_name_to_code('POLICY_VIOLATION'),
                re( qr<.> ),
            ],
        ),
    ),
    'check_heartbeat() sends close() instead of 4th ping',
);

for my $method ( qw( is_closed sent_close_frame ) ) {
    ok(
        $ept->$method(),
        "$method() after last check_heartbeat()",
    );
}
#----------------------------------------------------------------------
