#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    eval 'use autodie';
}

use Test::More;

use File::Temp ();

use IO::Framed::Read ();

use Net::WebSocket::Parser ();

my @frames_to_test = (
    {
        label => 'close (1000/) - small frame',
        type => 'close',
        payload => "\x03\xe8",
    },
    {
        label => 'text, 128 - medium-sized frame',
        type => 'text',
        payload => ('x' x 128),
    },
);

#CPAN Testers keeps getting OOM errors when it parses this frame.
#e.g.:
#
#   http://www.cpantesters.org/cpan/report/33205f0a-e2b3-11e7-b440-b0a88896c47c
#   http://www.cpantesters.org/cpan/report/67dd0a5a-e2d0-11e7-a1cf-bb670eaac09d
#
#I’ve not been able to find any memory leaks, and this test runs fine on
#machines that appear to be much lower-powered than the smokers. There may be
#some artificial memory limit being imposed? Anyway, for now let’s forgo this
#one on the CPAN Testers smokers:
my $is_cpan_testers = $ENV{'AUTOMATED_TESTING'};
$is_cpan_testers &&= $ENV{'NONINTERACTIVE_TESTING'};
$is_cpan_testers &&= $ENV{'PERL_CR_SMOKER_CURRENT'};

if ( 1 || !$is_cpan_testers ) {
    push @frames_to_test, {
        label => 'binary, 70000 - large frame (32-bit compatible)',
        type => 'binary',
        payload => ('x' x 70000),
    };
}

#----------------------------------------------------------------------
#Let’s forgo 64-bit tests for now since they’d require a testing
#setup to use > 2 GiB of either memory or disk space.
#
#if ( eval { pack 'Q', 123 } ) {
#    push @frames_to_test, (
#        {
#            label => 'binary - large-large frame',
#            type => 'binary',
#            payload => ('x' x (20 + 0xffffffff)),
#        },
#    );
#}
#----------------------------------------------------------------------

plan tests => 0 + @frames_to_test;

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
        $frame2->to_bytes(),
        $frame->to_bytes(),
        $frame_t->{'label'},
    );
}
