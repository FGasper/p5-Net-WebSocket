use strict;
use warnings;

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 2;

use HTTP::Request  ();
use HTTP::Response ();

use Net::WebSocket::HTTP_R ();
use Net::WebSocket::Handshake::Client ();
use Net::WebSocket::Handshake::Server ();

my $client = Net::WebSocket::Handshake::Client->new(
    uri => 'ws://haha.tld',
    subprotocols => [ 'abc', 'def', 'ghi' ],
);

my $req_str = $client->to_string();

my $req = HTTP::Request->parse($req_str);

my $server = Net::WebSocket::Handshake::Server->new(
    subprotocols => [ 'ghi', 'def', 'jkl' ],
);

Net::WebSocket::HTTP_R::handshake_consume_request( $server, $req );

#Pick the first that the client gave, regardless of order
#in the server’s list.
is( $server->get_subprotocol(), 'def', 'server chose expected subprotocol' );

my $resp_str = $server->to_string();

my $resp = HTTP::Response->parse($resp_str);

Net::WebSocket::HTTP_R::handshake_consume_response( $client, $resp );

is( $client->get_subprotocol(), 'def', 'client has expected subprotocol' );