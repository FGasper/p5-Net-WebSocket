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

    my $deflate;

    NWDemo::handshake_as_server(
        $sock,
        sub {
            my ($req) = @_;

            my $exts = $req->header('Sec-WebSocket-Extensions');
            return if !defined $exts;

            #a list of strings
            my @extensions = ref($exts) ? @$exts : ($exts);

            #now it’s a list of objects
            @extensions = map { Net::WebSocket::Handshake::Extension->parse_string($_) } @extensions;

            my $trial_deflate = Net::WebSocket::PMCE::deflate::Server->new();

            my @headers;

            try {
                my $ext = $trial_deflate->consume_offer_header_parts(@extensions);

                $deflate = $trial_deflate;
warn $ext->to_string();
                push @headers, 'Sec-WebSocket-Extensions: ' . $ext->to_string();
            }
            catch {
warn $_;
                my $msg = try { $_->get_message() } || $_;

                #only one line
                $msg =~ s<[\r\n]+.*><>;

                push @headers, "X-Sec-WebSocket-Extensions-Error: $msg";
            };

#
#          EXTENSION:
#            for my $ext (map { HTTP::Headers::Util::split_header_words($_) } @extensions) {
#                if ($ext->[0] eq 'permessage-deflate') {
#                    my $server_max_bits;
#                    my $client_max_bits;
#
#                    my %opts = @{$ext}[ 2 .. $#$ext ];
#                    if (exists $opts{'server_max_window_bits'}) {
#                        my $err;
#                        try {
#                            Net::WebSocket::PMCE::deflate::validate_max_window_bits($opts{'server_max_window_bits'});
#                            $server_max_bits = $opts{'server_max_window_bits'};
#                        }
#                        catch {
#                            push @headers, "X-Sec-WebSocket-Extensions-Error: server_max_window_bits - " . $_->get_message();
#                        };
#
#                        next EXTENSION if !$server_max_bits;
#                    }
#
#                    if (exists $opts{'client_max_window_bits'}) {
#                        my $err;
#                        if (defined $opts{'client_max_window_bits'}) {
#                            try {
#                                    Net::WebSocket::PMCE::deflate::validate_max_window_bits($opts{'client_max_window_bits'});
#                                    $client_max_bits = $opts{'client_max_window_bits'};
#                                }
#                            }
#                            catch {
#                                push @headers, "X-Sec-WebSocket-Extensions-Error: client_max_window_bits - " . $_->get_message();
#                            };
#
#                            next EXTENSION if !$client_max_bits;
#                        }
#                    }
#
#                    if ($opts{'server_no_context_takeover'}) {
#                        push @headers, "X-Sec-WebSocket-Extensions-Error: unsupported - server_no_context_takeover";
#                        next EXTENSION;
#                    }
#
#                    push @headers, 'Sec-WebSocket-Extensions: permessage-deflate';
#                    $deflate = Net::WebSocket::PMCE::deflate->new(
#                        deflate_max_window_bits => $server_max_bits,
#                        inflate_max_window_bits => $client_max_bits,
#                    );
#                }
#                else {
#                    push @headers, 'X-Sec-WebSocket-Extensions-Error: unsupported - ' . HTTP::Headers::Util::join_header_words( @$ext );
#                }
#            }

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
            if ($deflate && $deflate->frame_is_compressed($frame)) {
                $payload = $deflate->decompress($frame->get_payload());
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

            if ($deflate) {
                $deflate->compress_frame($answer);
            }

            $framed_obj->write( $answer->to_bytes() );
        },
    );

    my $write_select = IO::Select->new($sock);

    while (!$ept->is_closed()) {
        my $cur_write_s = $framed_obj->get_write_queue_count() ? $write_select : undef;

        my ( $rdrs_ar, $wtrs_ar, $errs_ar ) = IO::Select->select( $s, $cur_write_s, $s, 10 );

        #IO::Select leaves ENOENT in $!, even on success
        #warn "select(): $!" if $!;

        if ($wtrs_ar && @$wtrs_ar) {
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
