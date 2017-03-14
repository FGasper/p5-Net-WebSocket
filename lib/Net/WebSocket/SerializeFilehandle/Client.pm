package Net::WebSocket::SerializeFilehandle::Client;

=encoding utf-8

=head1 NAME

Net::WebSocket::SerializeFilehandle::Client

=head1 SYNOPSIS

    my $ser = Net::WebSocket::SerializeFilehandle::Client->new( $filehandle );

    $msg = $ser->create_text( $bytes_count );
    $msg = $ser->create_binary( $bytes_count );

    $msg = $ser->flush_text();
    $msg = $ser->flush_binary();

    $msg = $ser->create_ping( $payload );
    $msg = $ser->create_pong( $payload );
    $msg = $ser->create_close( $code, $reason );

Each of the C<create_*> and C<flush_*> methods creates a single message.

C<create_text()> and C<create_binary()> accept a specific byte count to
send as the message, whereas C<flush_text()> and C<flush_binary()> read
until there are no more bytes to read and then send the result as a single
message. Note that the C<create_*> methods will stop reading once there is
no more data to read; if you do C<create_text(2048)> when there are only
100 more bytes to read, it’ll return with a message whose payload is
those 100 bytes.

The same restrictions on parameters for
L<Net::WebSocket::Frame::ping|ping>, L<Net::WebSocket::Frame::pong|pong>,
and L<Net::WebSocket::Frame::close|close> frames
apply as are documented in their respective C<Net::WebSocket::Frame::*>
modules.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::SerializeFilehandle
    Net::WebSocket::Serializer::Client
);

1;
