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

use Net::WebSocket::Endpoint::Client ();
use Net::WebSocket::Frame::binary ();
use Net::WebSocket::Frame::close  ();
use Net::WebSocket::Handshake::Client ();
use Net::WebSocket::Parser ();

use Net::WebSocket::PMCE::deflate ();

use constant {
    MAX_CHUNK_SIZE => 64000,
    CRLF => "\x0d\x0a",
    DEBUG => 1,
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

    my $use_deflate;

    my $read_obj = My::Reader->new();

    my $handshake;

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
            );

            my $hdr = $handshake->create_header_text();

            $hdr .= "Sec-WebSocket-Extensions: permessage-deflate" . CRLF;

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

                #TODO: Make it picky
                $use_deflate = ($req->header('Sec-WebSocket-Extensions') eq 'permessage-deflate');
                _debug("deflate? [$use_deflate]");

                $got_handshake = 1;
            }

            $ept ||= Net::WebSocket::Endpoint::Client->new(
                out => $handle,
                parser => Net::WebSocket::Parser->new( $read_obj ),
            );

            if (my $msg = $ept->get_next_message()) {
                my $payload;

                if ($use_deflate && Net::WebSocket::PMCE::deflate::message_is_compressed($msg)) {
                    $payload = Net::WebSocket::PMCE::deflate::get_decompressed_payload($msg);
                }
                else {
                    $payload = $msg->get_payload();
                }

                syswrite( \*STDOUT, substr( $payload, 0, 64, q<> ) ) while length $payload;
            }

            #Handle any control frames we might need to write out.
            while ( my $msg = $ept->get_next_message() ) {
                $self->write($msg->to_bytes());
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

            my $frame = Net::WebSocket::Frame::binary->new(
                payload_sr => \$self->read(),
                mask => Net::WebSocket::Mask::create(),
            );

            if ($use_deflate) {
                Net::WebSocket::PMCE::deflate::compress_frame($frame);
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

            #$framed_obj->flush_write_queue();
            #TODO

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

#----------------------------------------------------------------------
# We’d ordinarily use IO::Framed for this, but IO::Handle already reads
# from the filehandle. So, this implements the needed read() interface
# to imitate IO::Framed::Read for Net::WebSocket::Parser.

package My::Reader;

sub new {
    my ($class) = @_;

    my $self = q<>;

    return bless \$self, $class;
}

sub add {
    ${ $_[0] } .= $_[1];

    return;
}

sub get {
    return ${ $_[0] };
}

sub read {
    return substr( ${ $_[0] }, 0, $_[1], q<> );
}

1;
