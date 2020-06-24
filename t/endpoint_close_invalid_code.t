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

my $bad_close = Net::WebSocket::Frame::close->new(
    code => 4999,
    reason => 'dunno',
)->to_bytes();

my $close_packed = pack 'n', 4999;
my $new_close_packed = pack 'n', 5000;

$bad_close =~ s<$close_packed><$new_close_packed>;

open my $send_fh, '>', $infile;
syswrite $send_fh, $bad_close;

$ept->get_next_message();;

open my $re_in_fh, '<', $outfile;
my $reparser = Net::WebSocket::Parser->new( IO::Framed->new($re_in_fh) );

my $close_frame = $reparser->get_next_frame();

cmp_deeply(
    $close_frame,
    all(
        Isa('Net::WebSocket::Frame::close'),
        listmethods(
            get_mask_bytes => [ q<> ],
            get_code_and_reason => [
                1002,
                all(
                    re( qr<dunno> ),
                    re( qr<5000> ),
                ),
            ],
        ),
    ),
    'close() prompts a response',
) or diag explain $close_frame;
