#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use IO::Socket::INET ();
use IO::Select ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use lib "$FindBin::Bin/lib";
use NWDemo ();

use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Frame::text ();
use Net::WebSocket::Frame::binary ();
use Net::WebSocket::Frame::continuation ();
use Net::WebSocket::Handshake::Server ();
use Net::WebSocket::Parser ();

my $host_port = $ARGV[0] || die "Need host:port or port!\n";

if (index($host_port, ':') == -1) {
    substr( $host_port, 0, 0 ) = '127.0.0.1:';
}

my ($host, $port) = split m<:>, $host_port;

my $server = IO::Socket::INET->new(
    LocalHost => $host,
    LocalPort => $port,
    ReuseAddr => 1,
    Listen => 2,
);

while ( my $sock = $server->accept() ) {
    fork and next;

    $sock->autoflush(1);

    NWDemo::handshake_as_server($sock);

    NWDemo::set_signal_handlers_for_server($sock);

    my $parser = Net::WebSocket::Parser->new($sock);

    $sock->blocking(0);

    my $s = IO::Select->new($sock);

    my $sent_ping;

    my $ept = Net::WebSocket::Endpoint::Server->new(
        parser => $parser,
        out => $sock,

        on_data_frame => sub {
            my ($frame) = @_;

            my $answer = 'Net::WebSocket::Frame::' . $frame->get_type();
            $answer = $answer->new(
                fin => $frame->get_fin(),
                rsv => $frame->get_rsv(),
                payload_sr => \$frame->get_payload(),
            );

            print { $sock } $answer->to_bytes();
        },
    );

    while (!$ept->is_closed()) {
        my ( $rdrs_ar, undef, $errs_ar ) = IO::Select->select( $s, undef, $s, 10 );

        if ($errs_ar && @$errs_ar) {
            $s->remove($sock);
            last;
        }

        if (!$rdrs_ar && !$errs_ar) {
            $ept->timeout();
            last if $ept->is_closed();
            next;
        }

        if ( $rdrs_ar ) {
            try {
                $ept->get_next_message();
            }
            catch {
                if (!try { $_->isa('Net::WebSocket::X::ReceivedClose') } ) {
                    local $@ = $_;
                    die;
                }
            };
        }
    }

    exit;
}
