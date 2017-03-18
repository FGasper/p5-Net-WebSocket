package Net::WebSocket::Mask;

use strict;
use warnings;

use Module::Load ();

my $_loaded_rng;

sub create {
    if (!$_loaded_rng) {
        Module::Load::load('Net::WebSocket::RNG');
        $_loaded_rng = 1;
    }

    return Net::WebSocket::RNG::get()->bytes(4);
}

sub apply {
    my ($payload_sr, $mask) = @_;

    $mask = $mask x (int(length($$payload_sr) / 4) + 1);

    substr($mask, length($$payload_sr)) = q<>;

    $$payload_sr .= q<>;
    $$payload_sr ^= $mask;

    return;
}

1;
