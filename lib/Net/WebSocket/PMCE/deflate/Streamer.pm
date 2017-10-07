package Net::WebSocket::PMCE::deflate::Streamer;

use strict;
use warnings;

use parent qw( Net::WebSocket::Streamer );

sub new {
    my ($class, $data_obj, $frame_class) = @_;

    my $self = {
        _data_obj => $data_obj,
        _frame_class => $frame_class,
    };

    return $self;
}

my $_COMPRESS_FUNC, $_FIN;

sub create_chunk {
    $_COMPRESS_FUNC = '_compress_sync_flush';
    $_FIN = 0;

    goto &_create;
}

sub create_final {
    my $self = $_[0];

    $_COMPRESS_FUNC = $self->{'_data_obj'}{'final_frame_compress_func'};
    $_FIN = 1;

    goto &_create;
}

sub _create {
    my ($self) = @_;

    my $data_obj = $self->{'_data_obj'};

    my $payload_sr = \($data_obj->_compress_sync_flush( $_[1] ));

    my $class = $self->{'_frames_count'} ? 'Net::WebSocket::Frame::continuation' : $self->{'_frame_class'};
    my $rsv = $self->{'_frames_count'} ? undef : $data_obj->INITIAL_FRAME_RSV();

    $self->{'_frames_count'}++;

    return $class->new(
        payload_sr => $payload_sr,
        rsv => $rsv,
        $data_obj->FRAME_MASK_ARGS(),
    );
}

1;
