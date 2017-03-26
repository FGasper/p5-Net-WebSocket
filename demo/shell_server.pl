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

my $loop = IO::Events::Loop->new();

my $server = IO::Events::Socket::TCP->new(
    owner => $loop,
    listen => 1,
    addr => $host,
    port => $port,
    on_read => sub {
        my $shell = (getpwuid $>)[8] or die "No shell!";

        my $did_handshake;
        my $read_buffer = q<>;
        open my $rfh, '<', \$read_buffer;

        my $ept = Net::WebSocket::Endpoint::Server->new(
            parser => Net::WebSocket::Parser->new($rfh),
        );

        my $shell_hdl;

        my $client_hdl;

        my $cpid;

        my $timeout = IO::Events::Timer->new(
            owner => $loop,
            timeout => 5,
            repetitive => 1,
            active => 1,
            on_tick => sub {
                if ($did_handshake) {
                    $ept->check_heartbeat();

                    if ($ept->is_closed()) {
                        $shell_hdl->destroy();  #kills PID and $client_hdl
                    }
                    else {

                        #Handle any control frames we might need to write out,
                        #esp. pings.
                        while ( my $frame = $ept->shift_write_queue() ) {
                            $client_hdl->write($frame->to_bytes());
                        }
                    }
                }
                else {
                    $client_hdl->destroy();
                }
            },
        );

        $client_hdl = shift()->accept(
            read => 1,
            write => 1,
            on_read => sub {
                my ($client_hdl) = @_;

                $read_buffer .= $client_hdl->read();

                if ($did_handshake) {
                    if (my $msg = $ept->get_next_message()) {

                        #printf STDERR "from client: %s\n", ($msg->get_payload() =~ s<([\x80-\xff])><sprintf '\x%02x', ord $1>gre);
                        #printf STDERR "from client: %v.02x\n", $msg->get_payload();

                        $shell_hdl->write( $msg->get_payload() );
                    }

                    while (my $frame = $ept->shift_write_queue()) {
                        $client_hdl->write($frame->to_bytes());
                    }
                }
                else {
                    my $hsk = NWDemo::get_server_handshake_from_text($read_buffer);
                    return if !$hsk;

                    #----------------------------------------------------------------------

                    $client_hdl->write( $hsk->create_header_text() . "\x0d\x0a" );
                    $did_handshake = 1;

                    my $pty = IO::Pty->new();

                    $cpid = fork or do {
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
                            exec { $shell } $shell, '--login' or die $!;
                        };
                        warn if $@;
                        exit( $@ ? 1 : 0 );
                    };

                    $shell_hdl = IO::Events::Handle->new(
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

                        on_close => sub {
                            $client_hdl->destroy();
                        },
                    );
                }
            }
        );
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
