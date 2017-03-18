package Net::WebSocket::Serializer;

#=encoding utf-8
#
#=head1 NAME
#
#Net::WebSocket::Serializer - serializer base class
#
#=head1 SYNOPSIS
#
#    $ser->create_text(2048);  #creates a 2-KiB text message
#
#    #creates a 1-MiB binary message
#    $ser->create_binary(1_048_576);
#
#=cut

use strict;
use warnings;

use constant MAX_FRAGMENT_SIZE => 65535;

use parent qw( Net::WebSocket::Base::Serializer );

use Net::WebSocket::Frame::continuation ();
use Net::WebSocket::Message ();

sub create_text {
    my ($self, $size) = @_;

    return $self->_create('text', $size);
}

sub create_binary {
    my ($self, $size) = @_;

    return $self->_create('binary', $size);
}

sub flush_text {
    my ($self) = @_;

    return $self->_create('text');
}

sub flush_binary {
    my ($self) = @_;

    return $self->_create('binary');
}


sub _create {
    my ($self, $type, $size) = @_;

    if (@_ > 2) {
        if ($size !~ m<\A[1-9][0-9]*\z>) {
            die "Size ($size) must be a positive integer!";
        }
    }

    my $frame_class = $self->_load_frame_class($type);

    my $mask = $self->_create_new_mask();

    my ($max_chunk, @frames);

    while (!defined($size) || $size > 0) {
        $max_chunk = defined($size) && ($size < MAX_FRAGMENT_SIZE)
            ? $size
            : MAX_FRAGMENT_SIZE
        ;

        my $payload_sr = \$self->_read($max_chunk);

        #We need at least one frame, so this is not
        #the time to break the loop if there are no frames yet.
        last if @frames && !length $$payload_sr;

        my $frame = $frame_class->new(
            fin => 0,
            mask => $mask,
            payload_sr => $payload_sr,
        );

        push @frames, $frame;

        if (defined $size) {
            $size -= length $$payload_sr;
        }
        else {
            last if length($$payload_sr) < MAX_FRAGMENT_SIZE;
        }

        $frame_class = 'Net::WebSocket::Frame::continuation';
    }

    $frames[-1]->set_fin(1);

    return Net::WebSocket::Message::create_from_frames(@frames);
}

1;
