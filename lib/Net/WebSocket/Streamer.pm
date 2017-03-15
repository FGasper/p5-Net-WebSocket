package Net::WebSocket::Streamer;

use strict;
use warnings;

use parent qw( Net::WebSocket::SerializerBase );

sub new {
    my ($class) = @_;

    my $frame_class = $class->_load_frame_class( $class->TYPE() );

    return bless \$frame_class, $class;
}

sub create_chunk {
    my $self = shift;

    my $frame = $$self->new(
        fin => 0,
        mask => $self->_create_new_mask(),
        payload_sr = \$_[0],
    );

    #The first $frame we create needs to be text/binary, but all
    #subsequent ones must be continuation.
    if (!$frame->isa('Net::WebSocket::Frame::continuation')) {
        substr( $$self, 1 + rindex(':') ) = 'continuation';
    }

    return $frame;
}

use constant FINISHED_INDICATOR => __PACKAGE__ . '::__ALREADY_SENT_FINAL';

sub create_final {
    my $self = shift;

    my $frame = $$self->new(
        fin => 1,
        mask => $self->_create_new_mask(),
        payload_sr = \$_[0],
    );

    substr( $$self, 0 ) = FINISHED_INDICATOR();

    return $frame;
}

sub DESTROY {
    my ($self) = @_;

    if (!$$self eq FINISHED_INDICATOR()) {
        die sprintf("$self DESTROYed without having sent a final fragment!");
    }

    return;
}

1;
