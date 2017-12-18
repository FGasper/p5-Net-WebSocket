#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::NoWarnings;
use Test::Deep;
use Test::Exception;

use Net::WebSocket::Constants         ();
use Net::WebSocket::Handshake::Server ();

plan tests => 1 + 14;

#----------------------------------------------------------------------

{
    my $server = Net::WebSocket::Handshake::Server->new();

    throws_ok(
        sub { $server->valid_protocol_or_die('HTTP/1.0') },
        'Net::WebSocket::X::BadRequestProtocol',
        'invalid protocol',
    );

    lives_ok(
        sub { $server->valid_protocol_or_die(Net::WebSocket::Constants::REQUIRED_REQUEST_PROTOCOL()) },
        'valid protocol',
    );

    throws_ok(
        sub { $server->valid_method_or_die('POST') },
        'Net::WebSocket::X::BadHTTPMethod',
        'invalid protocol',
    );

    lives_ok(
        sub { $server->valid_method_or_die(Net::WebSocket::Constants::REQUIRED_HTTP_METHOD()) },
        'valid HTTP method',
    );
}

#----------------------------------------------------------------------

my $ok_key = 'dGhlIHNhbXBsZSBub25jZQ==';

my @good_headers = (
    'sec-websocket-version' => Net::WebSocket::Constants::PROTOCOL_VERSION(),
    'sec-websocket-key' => $ok_key,
    'connection' => 'upgrade',
    'upgrade' => 'websocket',
);

{
    my $server = Net::WebSocket::Handshake::Server->new();

    lives_ok(
        sub { $server->consume_headers(@good_headers) },
        'all’s well',
    );
}

{
    my $server = Net::WebSocket::Handshake::Server->new();

    throws_ok(
        sub { $server->consume_headers() },
        'Net::WebSocket::X::MissingHeaders',
        'empty submission - missing headers'
    );

    cmp_bag(
        $@->get('names'),
        [ 'Connection', 'Upgrade', 'Sec-WebSocket-Key', 'Sec-WebSocket-Version' ],
        '… and the missing headers are the ones we expect',
    );
}

{
    my $server = Net::WebSocket::Handshake::Server->new();

    my %headers = (
        @good_headers,
        'sec-websocket-version' => 10,
    );

    throws_ok(
        sub { $server->consume_headers(%headers) },
        'Net::WebSocket::X::UnsupportedProtocolVersion',
        'unsupported WebSocket version',
    );
}

{
    my $server = Net::WebSocket::Handshake::Server->new();

    my %headers = (
        @good_headers,
        'sec-websocket-key' => 'blahblah',
    );

    throws_ok(
        sub { $server->consume_headers(%headers) },
        'Net::WebSocket::X::BadHeader',
        'invalid key',
    );

    is(
        $@->get('name'),
        'Sec-WebSocket-Key',
        '… and the “name” is as we expect',
    );
}

{
    my $server = Net::WebSocket::Handshake::Server->new();

    my %headers = (
        @good_headers,
        'connection' => 'blahblah',
    );

    throws_ok(
        sub { $server->consume_headers(%headers) },
        'Net::WebSocket::X::BadHeader',
        'invalid Connection',
    );

    is(
        $@->get('name'),
        'Connection',
        '… and the “name” is as we expect',
    );
}

{
    my $server = Net::WebSocket::Handshake::Server->new();

    my %headers = (
        @good_headers,
        'upgrade' => 'blahblah',
    );

    throws_ok(
        sub { $server->consume_headers(%headers) },
        'Net::WebSocket::X::BadHeader',
        'invalid Upgrade',
    );

    is(
        $@->get('name'),
        'Upgrade',
        '… and the “name” is as we expect',
    );
}
