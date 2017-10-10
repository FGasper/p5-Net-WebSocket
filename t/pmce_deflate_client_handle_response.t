use strict;
use warnings;

use Test::More;
use Test::NoWarnings;

plan tests => 1 + 4;

use Net::WebSocket::PMCE::deflate::Client ();

my $default = Net::WebSocket::PMCE::deflate::Client->new();

is_deeply(
    [ $default->create_request_header_parts() ],
    [
        'permessage-deflate',
        'client_max_window_bits' => undef,
    ],
    'default state',
);

sub _get_request_hash {
    my (@params) = @_;

    my $obj = Net::WebSocket::PMCE::deflate::Client->new(@params);
    my @request = $obj->create_request_header_parts();

    shift @request;

    return { @request };
}

#----------------------------------------------------------------------



1;
