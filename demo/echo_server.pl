#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use lib '/Users/Felipe/code/p5-IO-SigGuard/lib';

use IO::Socket::INET ();
use IO::Select ();

use IO::Framed::ReadWrite ();

use HTTP::Headers::Util ();

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

use Net::WebSocket::Handshake::Extension ();
use Net::WebSocket::PMCE::deflate::Server ();

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

    my @exts;

    my $deflate_data = NWDemo::handshake_as_server( $sock );

    NWDemo::set_signal_handlers_for_server($sock);

    my $framed_obj = IO::Framed::ReadWrite->new($sock);
    $framed_obj->enable_write_queue();

    my $parser = Net::WebSocket::Parser->new($framed_obj);

    $sock->blocking(0);

    my $s = IO::Select->new($sock);

    my $sent_ping;

    my $ept = Net::WebSocket::Endpoint::Server->new(
        parser => $parser,
        out => $framed_obj,
    );

    $ept->do_not_die_on_close();

    my $write_select = IO::Select->new($sock);

    while (!$ept->is_closed()) {
        my $cur_write_s = $framed_obj->get_write_queue_count() ? $write_select : undef;

        my ( $rdrs_ar, $wtrs_ar, $errs_ar ) = IO::Select->select( $s, $cur_write_s, $s, 10 );

        #IO::Select leaves ENOENT in $!, even on success
        #warn "select(): $!" if $!;

        if ($cur_write_s && $wtrs_ar && @$wtrs_ar) {
            $framed_obj->flush_write_queue();
        }

        if ($errs_ar && @$errs_ar) {
            $s->remove($sock);
            last;
        }

        if (!$rdrs_ar) {
            $ept->check_heartbeat();
            last if $ept->is_closed();
            next;
        }

        if ( @$rdrs_ar ) {
            my $msg = $ept->get_next_message();

            #If this returns falsey, whether we get undef or q<>
            #we react the same way.
            if ( $msg ) {
                my $answer_f = 'Net::WebSocket::Frame::' . $msg->get_type();

                if ($deflate_data && $deflate_data->message_is_compressed($msg)) {
                    $answer_f = $deflate_data->create_message(
                        $answer_f,
                        $deflate_data->decompress( $msg->get_payload() ),
                    );
                }
                else {
                    $answer_f = $answer_f->new(
                        payload_sr => \$msg->get_payload(),
                    );
                }

                $framed_obj->write( $answer_f->to_bytes() );
            }
        }
    }

    print "Done: PID $$\n";

    exit;
}
