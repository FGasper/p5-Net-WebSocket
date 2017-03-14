#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

package main;

use Try::Tiny;

use Digest::SHA ();
use HTTP::Response;
use IO::Select ();
use IO::Socket::INET ();
use MIME::Base64 ();
use Socket ();
use URI::Split ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use Net::WebSocket::Endpoint ();
use Net::WebSocket::Handshake::Client ();
use Net::WebSocket::ParseFilehandle ();
use Net::WebSocket::SerializeFilehandle::Client ();

use constant MAX_CHUNK_SIZE => 64000;

use constant CRLF => "\x0d\x0a";

use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV ALRM TERM );

run( @ARGV ) if !caller;

sub run {
    my ($uri) = @_;

    my ($uri_scheme, $uri_authority) = URI::Split::uri_split($uri);

    if (!$uri_scheme) {
        die "Need a URI!\n";
    }

    if ($uri_scheme !~ m<\Awss?\z>) {
        die sprintf "Invalid schema: “%s” ($uri)\n", $uri_scheme;
    }

    my $inet;

    my ($host, $port) = split m<:>, $uri_authority;

    if ($uri_scheme eq 'ws') {
        my $iaddr = Socket::inet_aton($host);

        $port ||= 80;
        my $paddr = Socket::pack_sockaddr_in( $port, $iaddr );

        socket( $inet, Socket::PF_INET(), Socket::SOCK_STREAM(), 0 );
        connect( $inet, $paddr );
    }
    elsif ($uri_scheme eq 'wss') {
        require IO::Socket::SSL;

        $inet = IO::Socket::SSL->new(
            PeerHost => $host,
            PeerPort => $port || 443,
            SSL_hostname => $host,
        );

        die "IO::Socket::SSL: [$!][$@]\n" if !$inet;
    }
    else {
        die "Unknown scheme ($uri_scheme) in URI: “$uri”";
    }

    my $buf_sr = _handshake_as_client( $inet, $uri );

    _mux_after_handshake( \*STDIN, \*STDOUT, $inet, $$buf_sr );

    exit 0;
}

sub _handshake_as_client {
    my ($inet, $uri) = @_;

    my $handshake = Net::WebSocket::Handshake::Client->new(
        uri => $uri,
    );

    my $hdr = $handshake->create_header_text();

    #Write out the client handshake.
    syswrite( $inet, $hdr . CRLF );

    my $handshake_ok;

    my $buf = q<>;

    #Read the server handshake.
    my $idx;
    while ( sysread $inet, $buf, MAX_CHUNK_SIZE, length $buf ) {
        $idx = index($buf, CRLF . CRLF);
        last if -1 != $idx;
    }

    my $hdrs_txt = substr( $buf, 0, $idx + 2 * length(CRLF), q<> );

    my $req = HTTP::Response->parse($hdrs_txt);

    my $code = $req->code();
    die "Must be 101, not “$code”" if $code != 101;

    my $upg = $req->header('upgrade');
    $upg =~ tr<A-Z><a-z>;
    die "“Upgrade” must be “websocket”, not “$upg”!" if $upg ne 'websocket';

    my $conn = $req->header('connection');
    $conn =~ tr<A-Z><a-z>;
    die "“Upgrade” must be “upgrade”, not “$conn”!" if $conn ne 'upgrade';

    my $accept = $req->header('Sec-WebSocket-Accept');
    $handshake->validate_accept_or_die($accept);

    return \$buf;
}

my $sent_ping;

sub _mux_after_handshake {
    my ($from_caller, $to_caller, $inet, $buf) = @_;

    my $serializer = Net::WebSocket::SerializeFilehandle::Client->new(
        $from_caller,
    );

    my $parser = Net::WebSocket::ParseFilehandle->new(
        $inet,
        $buf,
    );

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = ($the_sig eq 'INT') ? 'SUCCESS' : 'ENDPOINT_UNAVAILABLE';

            my $frame = $serializer->create_close($code);

            syswrite( $inet, $frame->to_bytes() );

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    my $ept = Net::WebSocket::Endpoint->new(
        out => $inet,
        parser => $parser,
        serializer => $serializer,
    );

    if ( -t $from_caller ) {
        $_->blocking(0) for ($from_caller, $inet);

        my $s = IO::Select->new( $from_caller, $inet );

        while (1) {
            my ($rdrs_ar, undef, $excs_ar) = IO::Select->select( $s, undef, $s, 10 );

            for my $err (@$excs_ar) {
                $s->remove($err);

                if ($err == $inet) {
                    warn "Error in socket reader!";
                }
                elsif ($err == $from_caller) {
                    warn "Error in input reader!";
                }
                else {
                    die "Improper select() error: [$err]";
                }
            }

            for my $rdr (@$rdrs_ar) {
                if ($rdr == $from_caller) {
                    _chunk_to_remote($serializer, $inet);
                }
                elsif ($rdr == $inet) {
                    if ( my $msg = $ept->get_next_message() ) {
                        syswrite( $to_caller, $msg->get_payload() );
                    }
                }
                else {
                    die "Improper reader: [$rdr]";
                }
            }

            if (!$rdrs_ar && !$excs_ar) {
                $ept->timeout();
                last if $ept->is_closed();
            }
        }
    }
    else {
        _chunk_to_remote($serializer, $inet);

        my $close_frame = $serializer->create_close('SUCCESS');

        syswrite( $inet, $close_frame->to_bytes() );

        shutdown $inet, Socket::SHUT_WR();

        try {
            while ( my $msg = $ept->get_next_message() ) {
                syswrite( $to_caller, $msg->get_payload() );
            }
        }
        catch {
            my $ok;
            if ( try { $_->isa('Net::WebSocket::X::ReceivedClose') } ) {
                if ( $_->get('frame')->get_payload() eq $close_frame->get_payload() ) {
                    $ok = 1;
                }
            }

            warn $_ if !$ok;
        };

        close $inet;

        close $from_caller;
    }

    return;
}

sub _chunk_to_remote {
    my ($serializer, $out_fh) = @_;

    my $msg = $serializer->flush_binary();
    syswrite( $out_fh, $msg->to_bytes() );

    return;
}
