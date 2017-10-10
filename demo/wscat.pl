#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use IO::Events ();

use HTTP::Response;
use IO::Socket::INET ();
use Socket ();
use URI::Split ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use lib "$FindBin::Bin/lib";
use MockReader ();

use Net::WebSocket::Endpoint::Client ();
use Net::WebSocket::Frame::binary ();
use Net::WebSocket::Frame::close  ();
use Net::WebSocket::Handshake::Client ();
use Net::WebSocket::Parser ();

use Net::WebSocket::PMCE::deflate::Client ();

use Net::WebSocket::HTTP_R ();

use constant {
    MAX_CHUNK_SIZE => 64000,
    CRLF => "\x0d\x0a",
    DEBUG => 1,

    SEND_FRAME_CLASS => 'Net::WebSocket::Frame::binary',
};

#No PIPE
use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV ALRM TERM );

run( @ARGV ) if !caller;

sub run {
    my ($uri) = @_;

    -t \*STDIN or die "STDIN must be a TTY for this demo.\n";

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

    my $loop = IO::Events::Loop->new();

    my ($handle, $ept);

    my $timeout = IO::Events::Timer->new(
        owner => $loop,
        timeout => 5,
        repetitive => 1,
        on_tick => sub {
            die "Handshake timeout!\n" if !$ept;

            $ept->check_heartbeat();

            #Handle any control frames we might need to write out,
            #esp. pings.
            #TODO
        },
    );

    my @to_write;

    my $sent_handshake;
    my $got_handshake;

    my $read_obj = MockReader->new();

    my $handshake;

    my $deflate = Net::WebSocket::PMCE::deflate::Client->new();
    my $deflate_hsk = $deflate->get_handshake_object();
    my $deflate_data;

    $handle = IO::Events::Handle->new(
        owner => $loop,
        handle => $inet,
        read => 1,
        write => 1,

        on_create => sub {
            my ($self) = @_;

            $timeout->start();

            $handshake = Net::WebSocket::Handshake::Client->new(
                uri => $uri,
                extensions => [$deflate],
            );

            my $hdr = $handshake->create_header_text();
print "SENDING HEADERS:\n$hdr\n";

            $self->write( $hdr . CRLF );

            $sent_handshake = 1;
        },

        on_read => sub {
            my ($self) = @_;

            $read_obj->add( $self->read() );

            if (!$got_handshake) {
                my $idx = index($read_obj->get(), CRLF . CRLF);
                return if -1 == $idx;

                _debug('received handshake');

                my $hdrs_txt = $read_obj->read( $idx + 2 * length(CRLF) );

print "HEADERS:\n$hdrs_txt\n";
                my $resp = HTTP::Response->parse($hdrs_txt);

                Net::WebSocket::HTTP_R::handshake_consume_response(
                    $handshake,
                    $resp,
                );

                if ( $deflate->ok_to_use() ) {
                    $deflate_data = $deflate->create_data_object();
                }

                $got_handshake = 1;
            }

            $ept ||= Net::WebSocket::Endpoint::Client->new(
                parser => Net::WebSocket::Parser->new( $read_obj ),

                #NB: $handle happens already to implement a write() method.
                out => $handle,
            );

            if (my $msg = $ept->get_next_message()) {
                my $payload;

                $payload = $msg->get_payload();

                while (length $payload) {
                    syswrite( \*STDOUT, substr( $payload, 0, 65536, q<> ) ) or die "write(STDOUT): $!";
                }
            }

            $timeout->start();
        },
    );

    my $closed;

    my $stdin = IO::Events::stdin->new(
        owner => $loop,
        read => 1,
        on_read => sub {
            my ($self) = @_;

            my $frame;

            if ($deflate_data) {
                $frame = $deflate_data->create_message(
                    SEND_FRAME_CLASS(),
                    $self->read(),
                );
            }
            else {
                $frame = SEND_FRAME_CLASS()->new(
                    payload_sr => \$self->read(),
                    mask => Net::WebSocket::Mask::create(),
                );
            }

            $handle->write($frame->to_bytes());
        },

        on_close => sub {
            $closed = 1;
        },

        on_error => sub {
            print STDERR "ERROR\n";
        },
    );

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = ($the_sig eq 'INT') ? 'SUCCESS' : 'ENDPOINT_UNAVAILABLE';

            $ept->shutdown( code => $code );

            local $SIG{'PIPE'} = 'IGNORE';
            $handle->flush();

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    $loop->yield() while !$closed;

    $loop->flush();
}

sub _debug {
    print STDERR "DEBUG: $_[0]$/" if DEBUG;
}

1;
