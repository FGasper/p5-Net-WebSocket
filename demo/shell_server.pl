#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use Socket;

use lib '/Users/Felipe/code/p5-IO-SigGuard/lib';

use IO::Socket::INET ();
use IO::Events ();

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

#This is a “lazy” example. A more robust, production-level
#solution would not need to fork() unless there were privilege
#drops or some such that necessitate separate processes per session.

#For an example of a non-forking server in Perl, look at Net::WAMP’s
#router example.

while ( my $sock = $server->accept() ) {
    fork and next;

    $sock->autoflush(1);

    NWDemo::handshake_as_server($sock);

    NWDemo::set_signal_handlers_for_server($sock);

    my $parser = Net::WebSocket::Parser->new($sock);

    $sock->blocking(0);

    my $sent_ping;

    socketpair(my $csock, my $psock, AF_UNIX, SOCK_STREAM, PF_UNSPEC);

    my $cpid = fork or do {
        eval {
            close $psock;
            open \*STDIN, '<&=', $csock;
            open \*STDOUT, '>&=', $csock;
            open \*STDERR, '>&=', $csock;

            exec '/bin/bash';
        };
        warn if $@;
        exit( $@ ? 1 : 0 );
    };

    close $csock;

    my $loop = IO::Events::Loop->new();

    my $client_hdl;

    my $shell_hdl = IO::Events::Handle->new(
        owner => $loop,
        handle => $psock,
        read => 1,
        write => 1,

        on_read => sub {
            my ($self) = @_;
            my $frame = Net::WebSocket::Frame::text->new(
                payload_sr => \$self->read(),
            );

use Data::Dumper;
print STDERR Dumper( "sending to client", $frame->get_payload() );
            $client_hdl->write($frame->to_bytes());
        },
    );

    my $read_buf = q<>;
    open my $rfh, '<', \$read_buf;

    my $ept = Net::WebSocket::Endpoint::Server->new(
        parser => Net::WebSocket::Parser->new($rfh),
        out => $sock,
    );

    $client_hdl = IO::Events::Handle->new(
        owner => $loop,
        handle => $sock,
        read => 1,
        write => 1,

        on_read => sub {
            my ($self) = @_;

            $read_buf .= $self->read();

            if (my $msg = $ept->get_next_message()) {
                $shell_hdl->write( $msg->get_payload() );
            }
        },
    );

#    for my $sig (ERROR_SIGS()) {
#        $SIG{$sig} = sub {
#            my ($the_sig) = @_;
#
#            my $code = ($the_sig eq 'INT') ? 'SUCCESS' : 'ENDPOINT_UNAVAILABLE';
    $loop->yield() while 1;
#
#            $ept->shutdown( code => $code );
#
#            while ( my $frame = $ept->shift_write_queue() ) {
#                $handle->write($frame->to_bytes());
#            }
#
#            local $SIG{'PIPE'} = 'IGNORE';
#            $handle->flush();
#
#            $SIG{$the_sig} = 'DEFAULT';
#
#            kill $the_sig, $$;
#        };
#    }

    $loop->yield() while 1;
}
