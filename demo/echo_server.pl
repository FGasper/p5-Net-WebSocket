#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use HTTP::Request ();
use IO::Socket::INET ();
use IO::Select ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use Net::WebSocket::Endpoint ();
use Net::WebSocket::Frame::text ();
use Net::WebSocket::Frame::binary ();
use Net::WebSocket::Frame::continuation ();
use Net::WebSocket::Handshake::Server ();
use Net::WebSocket::ParseFilehandle ();
use Net::WebSocket::Serializer::Server ();

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

    _handshake_as_server($sock);

    _set_sig($sock);

    my $parser = Net::WebSocket::ParseFilehandle->new($sock);

    $sock->blocking(0);

    my $s = IO::Select->new($sock);

    my $sent_ping;

    my $ept = Net::WebSocket::Endpoint->new(
        serializer => 'Net::WebSocket::Serializer::Server',
        parser => $parser,
        out => $sock,
    );

    $ept->set_data_handler( sub {
        my ($frame) = @_;

        my $answer = 'Net::WebSocket::Frame::' . $frame->get_type();
        $answer = $answer->new(
            fin => $frame->get_fin(),
            rsv => $frame->get_rsv(),
            payload_sr => \$frame->get_payload(),
        );

        print { $sock } $answer->to_bytes();
    } );

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

#----------------------------------------------------------------------

use constant MAX_CHUNK_SIZE => 64000;

use constant CRLF => "\x0d\x0a";

sub _handshake_as_server {
    my ($inet) = @_;

    my $buf = q<>;

    #Read the server handshake.
    my $idx;
    while ( sysread $inet, $buf, MAX_CHUNK_SIZE, length $buf ) {
        $idx = index($buf, CRLF . CRLF);
        last if -1 != $idx;
    }

    my $hdrs_txt = substr( $buf, 0, $idx + 2 * length(CRLF), q<> );

    die "Extra garbage! ($buf)" if length $buf;

    my $req = HTTP::Request->parse($hdrs_txt);

    my $method = $req->method();
    die "Must be GET, not “$method”" if $method ne 'GET';

    #Forgo validating headers. Life’s too short, and it’s a demo.

    my $key = $req->header('Sec-WebSocket-Key');

    my $handshake = Net::WebSocket::Handshake::Server->new(
        key => $key,
    );

    print { $inet } $handshake->create_header_text() . CRLF;

    return;
}

use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV ALRM TERM );

sub _set_sig {
    my ($inet) = @_;

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = ($the_sig eq 'INT') ? 'ENDPOINT_UNAVAILABLE' : 'SERVER_ERROR';

            my $frame = Net::WebSocket::Serializer::Server->create_close($code);

            print { $inet } $frame->to_bytes();

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    return;
}
