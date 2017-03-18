package Net::WebSocket::Serializer;

use strict;
use warnings;

use parent qw( Net::WebSocket::Base::Serializer );

use Net::WebSocket::Message ();

sub create_text {
    my ($self, $payload) = @_;

    return $self->_create('text', $payload);
}

sub create_binary {
    my ($self, $payload) = @_;

    return $self->_create('binary', $payload);
}

sub _create {
    my ($self, $type, $payload) = @_;

    my $frame_class = $self->_load_frame_class($type);

    return Net::WebSocket::Message::create_from_frames(
        $frame_class->new(
            mask => $self->_create_new_mask(),
            payload_sr => \$payload,
        ),
    );
}

1;
