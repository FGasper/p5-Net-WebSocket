package Net::WebSocket::Handshake::Base;

use strict;
use warnings;

use Call::Context ();
use Digest::SHA ();
use Module::Load ();

use Net::WebSocket::X ();

use constant _WS_MAGIC_CONSTANT => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

sub create_header_text {
    my $self = shift;

    return join( "\x0d\x0a", $self->_create_header_lines(), q<> );
}

sub get_match_protocol {
    my $self = shift;

    Call::Context::must_be_list();

    return @{ $self->{'_match_protocol'} };
}

sub _get_accept {
    my ($self) = @_;

    my $key_b64 = $self->{'key'} or do {
        die Net::WebSocket::X->create('BadArg', key => $self->{'key'});
    };

    $key_b64 =~ s<\A\s+|\s+\z><>g;

    my $accept = Digest::SHA::sha1_base64( $key_b64 . _WS_MAGIC_CONSTANT() );

    #pad base64
    $accept .= '=' x (4 - (length($accept) % 4));

    return $accept;
}

sub _encode_subprotocols {
    my ($self) = @_;

    return ( $self->{'subprotocols'}
        ? ( 'Sec-WebSocket-Protocol: ' . join(', ', @{ $self->{'subprotocols'} } ) )
        : ()
    );
}

sub _encode_extensions {
    my ($self) = @_;

    Module::Load::load('HTTP::Headers::Util');

    return if !$self->{'extensions'};
    return if !@{ $self->{'extensions'} };

    my ($first, @others) = map { $_->get_handshake_object() } grep { $_->consume_peer_extensions() } @{ $self->{'extensions'} };

    return 'Sec-WebSocket-Extensions: ' . $first->to_string(@others);
}

1;
