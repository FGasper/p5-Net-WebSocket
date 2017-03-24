#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Test::More;

use IO::Sys ();

plan tests => 1;

#NB: not 'IGNORE'
$SIG{'USR1'} = sub {};

my ($cr, $pw);

pipe( $cr, $pw );

my $pid = fork or do {
    close $pw;

    my $ppid = getppid;

    $cr->blocking(0);

    my $rin = q<>;
    vec( $rin, fileno($cr), 1 ) = 1;

    my $rout;

    while (1) {
        if ( select $rout = $rin, undef, undef, undef ) {
            sysread( $cr, my $buf, 65536 );
        }
        kill 'USR1', $ppid;
    }

    exit;
};

close $cr;

my $start = time;

my $secs = 8;

note "Thrashing IPC for $secs seconds to test EINTR resistance …";

while (time - $start < $secs) {
    IO::Sys::write( $pw, 'x' x 65536 ) or die $!;
}

kill 'TERM', $pid;

ok 1;
