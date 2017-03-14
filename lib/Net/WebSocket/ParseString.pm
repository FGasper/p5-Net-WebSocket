package Net::WebSocket::ParseString;

=encoding utf-8

=head1 NAME

Net::WebSocket::ParseString - Parse a string into WebSocket messages or frames

=head1 SYNOPSIS

    my $parse = Net::WebSocket::ParseString->new( \$buffer );

    while ( my $msg = $parse->get_next_message( \&_control_frame_handler ) ) {
        print $msg->get_payload();
    }

    while ( my $frame = $parse->get_next_frame() ) {
        ...
    }

See L<Net::WebSocket::ParseFilehandle> for more information about
methods of this class.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Parser
    Net::WebSocket::ReadString
);

sub _read {
    my ($self, $len) = @_;

    if ($len > length ${ $self->{'_sr'} }) {
        my $bytes_left = length ${ $self->{'_sr'} };
        die "Asked for “$len” bytes, but only “$bytes_left” are left!";
    }

    return $self->SUPER::_read($len);
}

1;
