package Net::WebSocket::SerializeString::Client;

=encoding utf-8

=head1 NAME

Net::WebSocket::SerializeString::Client

=head1 SYNOPSIS

    my $ser = Net::WebSocket::SerializeString::Client->new( \$buffer );

See L<Net::WebSocket::SerializeFilehandle::Client> for more information on
use of this class.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::SerializeString
    Net::WebSocket::Serializer::Client
);

1;
