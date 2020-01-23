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

use Net::WebSocket::Frame::close     ();
use Net::WebSocket::Parser           ();
use Net::WebSocket::Endpoint::Server ();

plan tests => 1;

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
$ept->do_not_die_on_close();

open my $send_fh, '>', $infile;
syswrite $send_fh, Net::WebSocket::Frame::close->new(
    mask => 1234,
)->to_bytes();

$ept->get_next_message();

open my $re_in_fh, '<', $outfile;
my $reparser = Net::WebSocket::Parser->new( IO::Framed->new($re_in_fh) );
my $close_frame = $reparser->get_next_frame();

cmp_deeply(
    $close_frame,
    all(
        Isa('Net::WebSocket::Frame::close'),
        listmethods(
            get_mask_bytes => [ q<> ],
            get_code_and_reason => [ undef, q<> ],
        ),
    ),
    'close() prompts a response',
);
