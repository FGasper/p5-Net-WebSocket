package Net::WebSocket::Handshake::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::Handshake::Server

=head1 SYNOPSIS

    my $hsk = Net::WebSocket::Handshake::Server->new(

        #required, base 64
        key => '..',

        #optional
        subprotocols => [ 'echo', 'haha' ],
    );

    #Includes only one trailing CRLF, so you can add additional headers
    my $txt = $hsk->create_header_text();

    my $b64 = $hsk->get_accept();

=cut

use strict;
use warnings;

use parent qw( Net::WebSocket::Handshake::Base );

use Call::Context ();
use Digest::SHA ();

use Net::WebSocket::X ();

sub new {
    my ($class, %opts) = @_;

    if (!$opts{'key'}) {
        die Net::WebSocket::X->create('BadArg', key => $opts{'key'});
    }

    return bless \%opts, $class;
}

*get_accept = __PACKAGE__->can('_get_accept');

sub _create_header_lines {
    my ($self) = @_;

    Call::Context::must_be_list();

    return (
        'HTTP/1.1 101 Switching Protocols',

        #For now let’s assume no one wants any other Upgrade:
        #or Connection: values than the ones WebSocket requires.
        'Upgrade: websocket',
        'Connection: Upgrade',

        'Sec-WebSocket-Accept: ' . $self->get_accept(),

        $self->_encode_subprotocols(),

        #'Sec-WebSocket-Extensions: ',
    );
}

1;
