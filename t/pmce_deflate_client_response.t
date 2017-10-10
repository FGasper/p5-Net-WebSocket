use strict;
use warnings;

use Test::More;
use Test::NoWarnings;
use Test::Deep;
use Test::Exception;

use constant EXT_CLASS => 'Net::WebSocket::Handshake::Extension';

plan tests => 1 + 15;

use Net::WebSocket::PMCE::deflate::Client ();

my $max_window_bits = ( Net::WebSocket::PMCE::deflate::Client->VALID_MAX_WINDOW_BITS() )[-1];
my $min_window_bits = ( Net::WebSocket::PMCE::deflate::Client->VALID_MAX_WINDOW_BITS() )[0];

my $default = Net::WebSocket::PMCE::deflate::Client->new();

is(
    $default->deflate_max_window_bits(),
    ( Net::WebSocket::PMCE::deflate->VALID_MAX_WINDOW_BITS() )[-1],
    'deflate_max_window_bits() default',
);

is(
    $default->inflate_max_window_bits(),
    ( Net::WebSocket::PMCE::deflate->VALID_MAX_WINDOW_BITS() )[-1],
    'inflate_max_window_bits() default',
);

ok(
    !$default->local_no_context_takeover(),
    'local_no_context_takeover() default = off',
);

ok(
    !$default->peer_no_context_takeover(),
    'peer_no_context_takeover() default = off',
);

#----------------------------------------------------------------------

my $pmd = Net::WebSocket::PMCE::deflate::Client->new();

$pmd->consume_parameters(
    'client_no_context_takeover' => undef,
);

ok(
    $pmd->local_no_context_takeover(),
    'local_no_context_takeover() after parsing extension string',
);

ok(
    !$pmd->peer_no_context_takeover(),
    'peer_no_context_takeover() default = off',
);

#Catch this in Net::WebSocket::Handshake instead.
#dies_ok(
#    sub {
#        $pmd->consume_parameters(
#            'client_no_context_takeover' => undef,
#        );
#    },
#    'consume_peer_extensions() only works once (for a client)',
#);

#----------------------------------------------------------------------
#server_no_context_takeover
{
    my $pmd = Net::WebSocket::PMCE::deflate::Client->new( peer_no_context_takeover => 1 );

    dies_ok(
        sub {
            $pmd->consume_parameters();
        },
        'peer_no_context_takeover - dies when !received server_no_context_takeover',
    );

    $pmd = Net::WebSocket::PMCE::deflate::Client->new( peer_no_context_takeover => 1 );

    lives_ok(
        sub {
            $pmd->consume_parameters('server_no_context_takeover' => undef);
        },
        'peer_no_context_takeover - OK when received server_no_context_takeover',
    );
}

#----------------------------------------------------------------------
#client_max_window_bits
{
    throws_ok(
        sub {
            Net::WebSocket::PMCE::deflate::Client->new( deflate_max_window_bits => $max_window_bits + 1 ),
        },
        qr<deflate_max_window_bits>,
        'deflate_max_window_bits: enforce max',
    );

    throws_ok(
        sub {
            Net::WebSocket::PMCE::deflate::Client->new( deflate_max_window_bits => $min_window_bits - 1 ),
        },
        qr<deflate_max_window_bits>,
        'deflate_max_window_bits: enforce min',
    );

    my $pmd = Net::WebSocket::PMCE::deflate::Client->new( deflate_max_window_bits => 12 );

    $pmd->consume_parameters('client_max_window_bits' => 11);

    is( $pmd->deflate_max_window_bits(), 11, 'absorb received client_max_window_bits' );
}

#----------------------------------------------------------------------
#server_max_window_bits
{
    throws_ok(
        sub {
            Net::WebSocket::PMCE::deflate::Client->new( inflate_max_window_bits => $max_window_bits + 1 ),
        },
        qr<inflate_max_window_bits>,
        'inflate_max_window_bits: enforce max',
    );

    throws_ok(
        sub {
            Net::WebSocket::PMCE::deflate::Client->new( inflate_max_window_bits => $min_window_bits - 1 ),
        },
        qr<inflate_max_window_bits>,
        'inflate_max_window_bits: enforce min',
    );

    my $pmd = Net::WebSocket::PMCE::deflate::Client->new( inflate_max_window_bits => 12 );

    $pmd->consume_parameters('server_max_window_bits' => 11);

    is( $pmd->inflate_max_window_bits(), 11, 'absorb received server_max_window_bits' );

    $pmd = Net::WebSocket::PMCE::deflate::Client->new( inflate_max_window_bits => 12 );

    throws_ok(
        sub {
            $pmd->consume_parameters('server_max_window_bits' => 13);
        },
        qr<server_max_window_bits>,
        'die() when server_max_window_bits is more than we stipulated',
    );
}
