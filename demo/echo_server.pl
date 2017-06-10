#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use lib '/Users/Felipe/code/p5-IO-SigGuard/lib';

use IO::Socket::INET ();
use IO::Select ();

use IO::Framed::ReadWrite ();

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

use Net::WebSocket::PMCE::deflate ();

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

    my $use_deflate;

    NWDemo::handshake_as_server(
        $sock,
        sub {
            my ($req) = @_;

            my $exts = $req->header('Sec-WebSocket-Extension');
            return if !defined $exts;

            my @extensions = ref($exts) ? @$exts : ($exts);

            use HTTP::Headers::Util;

            my @headers;

          EXTENSION:
            for my $ext (map { HTTP::Headers::Util::split_header_words($_) } @extensions) {
                if ($ext->[0] eq 'permessage-deflate') {
                    my %opts = @{$ext}[ 2 .. $#$ext ];
                    if ($opts{'server_max_window_bits'}) {
                        push @headers, "X-Sec-WebSocket-Extension-Error: unsupported - server_max_window_bits";
                        next EXTENSION;
                    }
                    if ($opts{'server_no_context_takeover'}) {
                        push @headers, "X-Sec-WebSocket-Extension-Error: unsupported - server_no_context_takeover";
                        next EXTENSION;
                    }

                    push @headers, 'Sec-WebSocket-Extension: permessage-deflate';
                    $use_deflate = 1;
                }
                else {
                    push @headers, 'X-Sec-WebSocket-Extension-Error: unsupported - ' . HTTP::Headers::Util::join_header_words( @$ext );
                }
            }

            return @headers;
        },
    );

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

        on_data_frame => sub {
            my ($frame) = @_;

            my $payload;
            if ($use_deflate && Net::WebSocket::PMCE::deflate::frame_is_compressed($frame)) {
                $payload = Net::WebSocket::PMCE::deflate::get_decompressed_payload($frame);
            }
            else {
                $payload = $frame->get_payload();
            }

            my $answer = 'Net::WebSocket::Frame::' . $frame->get_type();
            $answer = $answer->new(
                fin => $frame->get_fin(),
                rsv => $frame->get_rsv(),
                payload_sr => \$payload,
            );

            if ($use_deflate) {
                Net::WebSocket::PMCE::deflate::compress_frame($answer);
            }

            $framed_obj->write( $answer->to_bytes() );
        },
    );

    my $write_select = IO::Select->new($sock);

    while (!$ept->is_closed()) {
        my $cur_write_s = $framed_obj->get_write_queue_count() ? $write_select : undef;

        my ( $rdrs_ar, $wtrs_ar, $errs_ar ) = IO::Select->select( $s, $cur_write_s, $s, 10 );

        if ($wtrs_ar && @$wtrs_ar) {
            $framed_obj->flush_write_queue();
        }

        if (@$errs_ar) {
            $s->remove($sock);
            last;
        }

        if (!@$rdrs_ar && !($wtrs_ar && @$wtrs_ar) && !@$errs_ar) {
            $ept->check_heartbeat();
            last if $ept->is_closed();
            next;
        }

        if ( @$rdrs_ar ) {
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
