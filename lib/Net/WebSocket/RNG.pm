package Net::WebSocket::RNG;

use strict;
use warnings;

use Bytes::Random::Secure::Tiny ();

my $RNG_PID;
my $RNG;

sub get {
    if (!$RNG_PID || ($$ != $RNG_PID)) {
        $RNG = Bytes::Random::Secure::Tiny->new();
        $RNG_PID = $$;
    }

    return $RNG;
}

1;
