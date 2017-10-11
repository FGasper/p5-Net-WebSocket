package Net::WebSocket::PMCE::deflate::Streamer;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Net::WebSocket::PMCE::deflate::Streamer

=head1 SYNOPSIS

    my $streamer = $deflate_data->create_streamer( $frame_class );

    #These frames form a single compressed message in three
    #fragments whose content is “onetwothree”.
    my @frames = (
        $streamer->create_chunk('one'),
        $streamer->create_chunk('two'),
        $streamer->create_final('three'),
    );

=head1 DESCRIPTION

This class implements fragmentation for the permessage-deflate WebSocket
extension. The class is not instantiated directly, but returned as the
result of L<Net::WebSocket::PMCE::deflate::Data>’s C<create_streamer()>
method.

Strictly speaking, this is a base class; the C<::Client> and C<::Server>
subclasses implement a bit of logic specific to either endpoint type.

The C<create_chunk()> and C<create_final()> methods follow the same
pattern as L<Net::WebSocket::Streamer>.

=cut

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
    $_COMPRESS_FUNC = '_compress_fragment';
    $_FIN = 0;

    goto &_create;
}

sub create_final {
    $_COMPRESS_FUNC = $self->{'_data_obj'}{'final_frame_compress_func'};
    $_FIN = 1;

    goto &_create;
}

sub _create {
    my ($self) = @_;

    my $data_obj = $self->{'_data_obj'};

    my $payload_sr = \($data_obj->$_COMPRESS_FUNC( $_[1] ));

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
