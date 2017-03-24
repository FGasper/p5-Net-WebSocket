#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Test::More;

use IO::Sys ();

plan tests => 1;

#NB: not 'IGNORE'
$SIG{'USR1'} = sub {};

my ($pr, $cw);

pipe( $pr, $cw );

my $pid = fork or do {
    close $pr;

    my $ppid = getppid;

    $cw->blocking(0);

    my $rin = q<>;
    vec( $rin, fileno($cw), 1 ) = 1;

    my $rout;

    while (1) {
        if ( select undef, $rout = $rin, undef, undef ) {
            syswrite( $cw, ('x' x 65536) );
        }
        kill 'USR1', $ppid;
    }

    exit;
};

close $cw;

my $start = time;

my $secs = 8;

note "Thrashing IPC for $secs seconds to test EINTR resistance …";

while (time - $start < $secs) {
    IO::Sys::read( $pr, my $buf, 65536 ) or die $!;
}

kill 'TERM', $pid;

ok 1;
