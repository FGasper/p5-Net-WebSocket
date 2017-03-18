package Net::WebSocket::Base::Serializer;

use strict;
use warnings;

sub create_ping {
    my ($self, $msg) = @_;

    $msg = q<> if !defined $msg;

    return $self->_create_control('ping', payload_sr => \$msg);
}

sub create_pong {
    my ($self, $msg) = @_;

    $msg = q<> if !defined $msg;

    return $self->_create_control('pong', payload_sr => \$msg);
}

sub create_close {
    my ($self, $code, $reason) = @_;

    return $self->_create_control('close', code => $code, reason => $reason);
}

sub _create_control {
    my ($self, $type, @args) = @_;

    my $frame_class = $self->_load_frame_class($type);

    return $frame_class->new(
        @args,
        mask => $self->_create_new_mask(),
    );
}

sub _load_frame_class {
    my ($self, $type) = @_;

    my $frame_class = "Net::WebSocket::Frame::$type";

    for ( $frame_class ) {
        Module::Load::load($_) if !$_->can('new');
    }

    return $frame_class;
}

1;
