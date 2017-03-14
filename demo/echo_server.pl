#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use HTTP::Request ();
use IO::Socket::INET ();
use IO::Select ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use Net::WebSocket::Frame::text ();
use Net::WebSocket::Frame::binary ();
use Net::WebSocket::Frame::continuation ();
use Net::WebSocket::Frame::close ();
use Net::WebSocket::Frame::ping ();
use Net::WebSocket::Frame::pong ();
use Net::WebSocket::Handshake::Server ();
use Net::WebSocket::ParseFilehandle ();

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

    _handshake_as_server($sock);

    _set_sig($sock);

    my $parser = Net::WebSocket::ParseFilehandle->new($sock);

    $sock->blocking(0);

    my $s = IO::Select->new($sock);

    my $sent_ping;

    while (1) {
        #print STDERR "SELECT $$\n";

        #my @ready = $s->can_read(10);
        my ( $rdrs_ar, undef, $errs_ar ) = IO::Select->select( $s, undef, $s, 10 );

        if (!$rdrs_ar && !$errs_ar) {
            #print STDERR "10 SECONDS WITH NO INPUT\n";
            if ($sent_ping) {
                #print STDERR "ALREADY SENT PING\n";
                warn "No respose to ping!";
                my $close = Net::WebSocket::Frame::close->new( code => 'POLICY_VIOLATION' );
                print {$sock} $close->to_bytes();
                close $sock;
                last;
            }

            #print STDERR "SENDING PING\n";
            my $ping = Net::WebSocket::Frame::ping->new( payload_sr => \'Hello??' );
            print {$sock} $ping->to_bytes() or die $!;

            $sent_ping = 1;
            #print STDERR "SENT PING\n";
            next;
        }

        if ( $rdrs_ar ) {
            if ( my $frame = $parser->get_next_frame() ) {
                if ($frame->is_control_frame()) {
                    _handle_control_frame($frame, $sock);

                    last if $frame->get_type() eq 'close';

                    if ($frame->get_type() eq 'pong') {
#print STDERR "Got pong\n";
                        $sent_ping = 0;
                    }
                }
                else {
                    my $answer = 'Net::WebSocket::Frame::' . $frame->get_type();
                    $answer = $answer->new(
                        fin => $frame->get_fin(),
                        rsv => $frame->get_rsv(),
                        payload_sr => \$frame->get_payload(),
                    );

                    print {$sock} $answer->to_bytes() or die $!;
                }
            }
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

    syswrite $inet, $handshake->create_header_text() . CRLF;

    return;
}

use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV PIPE ALRM TERM );
sub _set_sig {
    my ($inet) = @_;

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = ($the_sig eq 'INT') ? 'ENDPOINT_UNAVAILABLE' : 'SERVER_ERROR';

            my $frame = Net::WebSocket::Frame::close->new(
                code => $code,
            );

            syswrite( $inet, $frame->to_bytes() );

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    return;
}

sub _handle_control_frame {
    my ($frame, $out_fh) = @_;

    if ($frame->get_type() eq 'close') {
        syswrite( $out_fh, Net::WebSocket::Frame::close->new(
            payload_sr => \$frame->get_payload(),
        )->to_bytes() );

        my ($code, $reason) = $frame->get_code_and_reason();
    }
    elsif ($frame->get_type() eq 'ping') {
        syswrite( $out_fh, Net::WebSocket::Frame::pong->new(
            payload_sr => \$frame->get_payload(),
        )->to_bytes() );
    }

    return;
}
