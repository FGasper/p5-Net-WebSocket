package Net::WebSocket::PMCE::deflate::Data::Client;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::PMCE::deflate::Data
    Net::WebSocket::Masker::Client
);

sub new {
    my ($class, %opts) = @_;

    $opts{'deflate_max_window_bits'} = delete $opts{ $class->_DEFLATE_MAX_WINDOW_BITS_PARAM() };
    $opts{'inflate_max_window_bits'} = delete $opts{ $class->_INFLATE_MAX_WINDOW_BITS_PARAM() };
    $opts{'local_no_context_takeover'} = delete $opts{ $class->_LOCAL_NO_CONTEXT_TAKEOVER_PARAM() };

    return bless \%opts, $class;
}

1;
