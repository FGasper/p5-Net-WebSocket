package Net::WebSocket::SerializeFilehandle::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::SerializeFilehandle::Server

=head1 SYNOPSIS

    my $ser = Net::WebSocket::SerializeFilehandle::Server->new( $filehandle );

See L<Net::WebSocket::SerializeFilehandle::Client> for more information on
use of this class.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::SerializeFilehandle
    Net::WebSocket::Serializer::Server
);

1;
