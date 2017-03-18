package Net::WebSocket::Serializer::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::Serializer::Server - Serialization for a WebSocket server

=head1 SYNOPSIS

    my $msg = Net::WebSocket::Serializer::Server->create_text(

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Serializer
    Net::WebSocket::Masker::Server
);

1;
