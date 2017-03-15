package NWDemo;

use strict;
use warnings;
use autodie;

use Net::WebSocket::Handshake::Server ();
use Net::WebSocket::Serializer::Server ();

use constant MAX_CHUNK_SIZE => 64000;

use constant CRLF => "\x0d\x0a";

sub handshake_as_server {
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
    die "Must be GET, not “$method” ($hdrs_txt)" if $method ne 'GET';

    #Forgo validating headers. Life’s too short, and it’s a demo.

    my $key = $req->header('Sec-WebSocket-Key');

    my $handshake = Net::WebSocket::Handshake::Server->new(
        key => $key,
    );

    print { $inet } $handshake->create_header_text() . CRLF;

    return;
}

use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV ALRM TERM );

sub set_signal_handlers_for_server {
    my ($inet) = @_;

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = ($the_sig eq 'INT') ? 'ENDPOINT_UNAVAILABLE' : 'SERVER_ERROR';

            my $frame = Net::WebSocket::Serializer::Server->create_close($code);

            print { $inet } $frame->to_bytes();

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    return;
}

1;
