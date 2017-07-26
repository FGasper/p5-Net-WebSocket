package Net::WebSocket::Handshake::Base;

use strict;
use warnings;

use Digest::SHA ();
use Module::Load ();

use constant _WS_MAGIC_CONSTANT => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

sub create_header_text {
    my $self = shift;

    return join( "\x0d\x0a", $self->_create_header_lines(), q<> );
}

sub _get_accept {
    my ($self) = @_;

    my $key_b64 = $self->{'key'};

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

    my ($first, @others) = @{ $self->{'extensions'} };

    return 'Sec-WebSocket-Extensions: ' . $first->to_string(@others);
}

1;
