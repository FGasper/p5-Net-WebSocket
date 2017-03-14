package Net::WebSocket::Mask;

sub apply {
    my ($payload_sr, $mask) = @_;

    $mask = $mask x (int(length($$payload_sr) / 4) + 1);

    substr($mask, length($$payload_sr)) = q<>;

    $$payload_sr .= q<>;
    $$payload_sr ^= $mask;

    return;
}

1;
