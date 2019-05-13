#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use IO::Events ();

use Getopt::Long ();
use HTTP::Response;
use Socket ();
use URI::Split ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use lib "$FindBin::Bin/lib";
use MockReader ();

use Net::WebSocket::Endpoint::Client ();
use Net::WebSocket::Handshake::Client ();
use Net::WebSocket::Parser ();

use Net::WebSocket::PMCE::deflate::Client ();

use Net::WebSocket::HTTP_R ();

use constant {
    CRLF => "\x0d\x0a",

    SEND_FRAME_TYPE => 'binary',
};

my $DEBUG;

#No PIPE
use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV ALRM TERM );

run( @ARGV ) if !caller;

sub run {
    my (@argv) = @_;

    my %cli_opts;

    Getopt::Long::Configure( 'pass_through' );
    my $ok = Getopt::Long::GetOptionsFromArray(
        \@argv,
        \%cli_opts,
        'debug',
        'header|H=s@',
        'insecure|k',
    );

    my ($uri) = @argv or die 'Need URI!';

    _debug("URI: “$uri”");

    local $SIG{'PIPE'} = 'IGNORE';

    my ($uri_scheme, $uri_authority) = URI::Split::uri_split($uri);

    if (!$uri_scheme) {
        die "Need a URI!$/";
    }

    if ($uri_scheme !~ m<\Awss?\z>) {
        die sprintf "Invalid schema: “%s” ($uri)$/", $uri_scheme;
    }

    my $inet;

    my ($host, $port) = split m<:>, $uri_authority;

    _debug("Opening $uri_scheme connection to $uri_authority …");

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
            ( $cli_opts{'insecure'} ? (SSL_verify_mode => 0) : () ),
        );

        die "IO::Socket::SSL: [$!][$@]\n" if !$inet;

    }
    else {
        die "Unknown scheme ($uri_scheme) in URI: “$uri”";
    }

    _debug("Opened connection.");

    my $loop = IO::Events::Loop->new();

    my ($handle, $ept);

    my $timeout = IO::Events::Timer->new(
        owner => $loop,
        timeout => 5,
        repetitive => 1,
        on_tick => sub {
            die "Handshake timeout!$/" if !$ept;

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

    my $stdout = IO::Events::Handle->new(
        owner => $loop,
        handle => \*STDOUT,
        write => 1,
    );

    my $stdin;

    my $closed;

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

            my @extra_headers;

            if (my $hdrs_ar = $cli_opts{'header'}) {
                for my $cur_hdr (@$hdrs_ar) {
                    my ($key, $val) = split m<\s*:\s*>, $cur_hdr, 2;
                    push @extra_headers, $key => $val;
                }
            }

            my $hdr = $handshake->to_string( headers => \@extra_headers );

            _debug("SENDING HEADERS:$/$hdr");

            $self->write( $hdr );

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

                _debug("HEADERS:$/$hdrs_txt");
                my $resp = HTTP::Response->parse($hdrs_txt);

                Net::WebSocket::HTTP_R::handshake_consume_response(
                    $handshake,
                    $resp,
                );

                if ( $deflate->ok_to_use() ) {
                    _debug('permessage-deflate extension accepted.');
                    $deflate_data = $deflate->create_data_object();
                }

                $got_handshake = 1;

                $stdin = IO::Events::Handle->new(
                    owner => $loop,
                    handle => \*STDIN,
                    read => 1,
                    on_read => sub {
                        my ($self) = @_;

                        my $frame = ( $deflate_data || $ept )->create_message(
                            SEND_FRAME_TYPE(),
                            $self->read(),
                        );

                        $handle->write($frame->to_bytes());
                    },

                    on_close => sub {
                        $ept->shutdown( code => 'SUCCESS' ) if $ept;
                        $handle->flush();

                        $closed = 1;
                    },

                    on_error => sub {
                        print STDERR "ERROR\n";
                    },
                );
            }

            $ept ||= Net::WebSocket::Endpoint::Client->new(
                parser => Net::WebSocket::Parser->new( $read_obj ),

                #NB: $handle happens already to implement a write() method.
                out => $handle,
            );

            if (my $msg = $ept->get_next_message()) {
                my $payload;

                $payload = $msg->get_payload();

                if ($deflate_data && $deflate_data->message_is_compressed($msg)) {
                    $payload = $deflate_data->decompress($payload);
                }

                $stdout->write($payload);
            }

            $timeout->start();
        },
    );

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = 'ENDPOINT_UNAVAILABLE';

            $ept->shutdown( code => $code );
            $handle->flush();

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    $loop->yield() while !$closed;

    $loop->flush();
}

sub _debug {
    print STDERR "DEBUG: $_[0]$/" if $DEBUG;
}

1;
