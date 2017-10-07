package NWDemo;

use strict;
use warnings;
use autodie;

use HTTP::Request ();

use IO::SigGuard ();

use Net::WebSocket::Handshake::Server ();
use Net::WebSocket::Frame::close ();

use constant MAX_CHUNK_SIZE => 64000;

use constant CRLF => "\x0d\x0a";

#Shortens the given text.
sub get_server_handshake_from_text {
    my $idx = index($_[0], CRLF . CRLF);
    return undef if -1 == $idx;

    my $hdrs_txt = substr( $_[0], 0, $idx + 2 * length(CRLF), q<> );

    die "Extra garbage! ($_[0])" if length $_[0];

    my $req = HTTP::Request->parse($hdrs_txt);

    my $method = $req->method();
    die "Must be GET, not “$method” ($hdrs_txt)" if $method ne 'GET';

    #Forgo validating headers. Life’s too short, and it’s a demo.

    my $key = $req->header('Sec-WebSocket-Key');

    return (
        $req,
        Net::WebSocket::Handshake::Server->new(
            key => $key,
        ),
    );
}

sub handshake_as_server {
    my ($inet, $req_handler) = @_;

    my $buf = q<>;
    my ($req, $hsk);
    while ( IO::SigGuard::sysread($inet, $buf, MAX_CHUNK_SIZE, length $buf ) ) {
        ($req, $hsk) = get_server_handshake_from_text($buf);
        last if $hsk;
    }

    die "read(): $!" if $!;

    my $hdr_text = $hsk->create_header_text();

    my @extra_headers;
    if ($req_handler) {
        $hdr_text .= $_ . CRLF for $req_handler->($req);
    }

use Data::Dumper;
$Data::Dumper::Useqq = 1;
print STDERR Dumper($hdr_text);

    print { $inet } $hdr_text . CRLF or die "send(): $!";

    return;
}

use constant ERROR_SIGS => qw( INT HUP QUIT ABRT USR1 USR2 SEGV ALRM TERM );

sub set_signal_handlers_for_server {
    my ($inet) = @_;

    for my $sig (ERROR_SIGS()) {
        $SIG{$sig} = sub {
            my ($the_sig) = @_;

            my $code = ($the_sig eq 'INT') ? 'ENDPOINT_UNAVAILABLE' : 'SERVER_ERROR';

            my $frame = Net::WebSocket::Frame::close->new(
                code => $code,
            );

            print { $inet } $frame->to_bytes();

            $SIG{$the_sig} = 'DEFAULT';

            kill $the_sig, $$;
        };
    }

    return;
}

1;
