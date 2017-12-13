#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use File::Temp ();

use IO::Framed::Read ();

use Net::WebSocket::Parser ();

my @frames_to_test = (
    {
        label => 'close (1000/)',
        type => 'close',
        payload => "\x03\xe8",
    },
    {
        label => 'text, 128',
        type => 'text',
        payload => ('x' x 128),
    },
    {
        label => 'binary, 70000',
        type => 'binary',
        payload => ('x' x 70000),
    },
);

plan tests => 3;

for my $frame_t (@frames_to_test) {
    my $class = "Net::WebSocket::Frame::$frame_t->{'type'}";
    Module::Load::load($class);
    my $frame = $class->new(
        payload => $frame_t->{'payload'},
    );

    my ($fh, $fpath) = File::Temp::tempfile( CLEANUP => 1 );

    print {$fh} $frame->to_bytes();
    close $fh;

    open my $rfh, '<', $fpath;

    my $iof = IO::Framed::Read->new($rfh);
    my $parser = Net::WebSocket::Parser->new($iof);

    my $frame2 = $parser->get_next_frame();

    is(
        sprintf('%v.02x', $frame2->to_bytes()),
        sprintf('%v.02x', $frame->to_bytes()),
        "$frame_t->{'label'}: round-trip close",
    );
}
