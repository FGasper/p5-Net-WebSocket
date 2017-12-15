package Net::WebSocket::Message;

use strict;
use warnings;

use Call::Context ();

sub new {
    if (!$_[1]->isa('Net::WebSocket::Frame')) {
        die( (caller 0)[3] . ' needs at least one Net::WebSocket::Frame object!' );
    }

    return bless \@_, shift;
}

sub get_frames {
    my ($self) = @_;

    Call::Context::must_be_list();

    return @$self;
}

sub get_payload {
    my ($self) = @_;

    return join( q<>, map { $_->get_payload() } @$self );
}

sub get_type {
    return $_[0][0]->get_type();
}

sub is_control {
    return $_[0][0]->is_control();
}

sub to_bytes {
    my ($self) = @_;

    return join( q<>, map { $_->to_bytes() } @$self );
}

1;
