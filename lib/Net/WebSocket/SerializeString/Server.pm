package Net::WebSocket::SerializeString::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::SerializeString::Server

=head1 SYNOPSIS

    my $ser = Net::WebSocket::SerializeString::Server->new( $filehandle );

See L<Net::WebSocket::SerializeFilehandle::Client> for more information on
use of this class.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::SerializeString
    Net::WebSocket::Serializer::Server
);

1;
