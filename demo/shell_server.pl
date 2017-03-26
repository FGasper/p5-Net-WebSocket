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

use IO::Pty ();

#for setsid()
use POSIX ();

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

    my $pty = IO::Pty->new();

    my $shell = (getpwuid $>)[8] or die "No shell!";

    my $cpid = fork or do {
        eval {
            my $slv = $pty->slave();
            open \*STDIN, '<&=', $slv;
            open \*STDOUT, '>&=', $slv;
            open \*STDERR, '>&=', $slv;

            #Necessary for CTRL-C and CTRL-\ to work.
            POSIX::setsid();

            #Any advantage to these??
            #setpgrp;
            #$pty->make_slave_controlling_terminal();

            #Dunno if all shells have a “--login” switch …
            exec { $shell } $shell, '--login';
        };
        warn if $@;
        exit( $@ ? 1 : 0 );
    };

    my $loop = IO::Events::Loop->new();

    my $client_hdl;

    my $shell_hdl = IO::Events::Handle->new(
        owner => $loop,
        handle => $pty,
        read => 1,
        write => 1,

        on_read => sub {
            my ($self) = @_;
            my $frame = Net::WebSocket::Frame::text->new(
                payload_sr => \$self->read(),
            );

            #printf STDERR "to client: %s\n", ($frame->to_bytes() =~ s<([\x80-\xff])><sprintf '\x%02x', ord $1>gre);
            #printf STDERR "to client: %v.02x\n", $frame->get_payload();

            $client_hdl->write($frame->to_bytes());
        },

        pid => $cpid,
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

                #printf STDERR "from client: %s\n", ($msg->get_payload() =~ s<([\x80-\xff])><sprintf '\x%02x', ord $1>gre);
                #printf STDERR "from client: %v.02x\n", $msg->get_payload();

                $shell_hdl->write( $msg->get_payload() );
            }
        },
    );

    try {
        $loop->yield() while 1;
    }
    catch {
        if ( !try { $_->isa('Net::WebSocket::X::ReceivedClose') } ) {
            local $@ = $_;
            die;
        }

        $loop->flush();
    };
}
