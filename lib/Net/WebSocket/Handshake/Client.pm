package Net::WebSocket::Handshake::Client;

=encoding utf-8

=head1 NAME

Net::WebSocket::Handshake::Client

=head1 SYNOPSIS

    my $hsk = Net::WebSocket::Handshake::Client->new(

        #required
        uri => 'ws://haha.test',

        #optional
        subprotocols => [ 'echo', 'haha' ],

        #optional, to imitate a web client
        origin => ..,

        #optional, base 64 .. auto-created if not given
        key => '..',

        #optional, instances of Net::WebSocket::Handshake::Extension
        extensions => \@extension_objects,
    );

    #Note the need to conclude the header text manually.
    #This is by design, so you can add additional headers.
    my $hdr = $hsk->create_header_text() . "\x0d\x0a";

    my $b64 = $hsk->get_key();

    #Validates the value of the “Sec-WebSocket-Accept” header;
    #throws Net::WebSocket::X::BadAccept if not.
    $hsk->validate_accept_or_die($accent_value);

=head1 DESCRIPTION

This class implements WebSocket handshake logic for a client.

Because Net::WebSocket tries to be agnostic about how you parse your HTTP
headers, this class doesn’t do a whole lot for you: it’ll create a base64
key for you and create “starter” headers for you. It also can validate
the C<Sec-WebSocket-Accept> header value from the server.

B<NOTE:> C<create_header_text()> does NOT provide the extra trailing
CRLF to conclude the HTTP headers. This allows you to add additional
headers beyond what this class gives you.

=cut

use strict;
use warnings;

use parent qw( Net::WebSocket::Handshake );

use URI::Split ();

use Net::WebSocket::Constants ();
use Net::WebSocket::X ();

use constant SCHEMAS => (
    'ws', 'wss',
    'http', 'https',
);

sub new {
    my ($class, %opts) = @_;

    if (length $opts{'uri'}) {
        @opts{ 'uri_schema', 'uri_auth', 'uri_path', 'uri_query' } = URI::Split::uri_split($opts{'uri'});
    }

    if (!$opts{'uri_schema'} || !grep { $_ eq $opts{'uri_schema'} } SCHEMAS()) {
        die Net::WebSocket::X->create('BadArg', uri => $opts{'uri'});
    }

    if (!length $opts{'uri_auth'}) {
        die Net::WebSocket::X->create('BadArg', uri => $opts{'uri'});
    }

    @opts{ 'uri_host', 'uri_port' } = split m<:>, $opts{'uri_auth'};

    $opts{'key'} ||= _create_key();

    return $class->SUPER::new(%opts);
}

sub valid_status_or_die {
    my ($self, $code, $reason) = @_;

    if ($code ne Net::WebSocket::Constants::REQUIRED_HTTP_STATUS()) {
        die Net::WebSocket::X->create('BadHTTPStatus', $code, $reason);
    }

    return;
}

sub get_key {
    my ($self) = @_;

    return $self->{'key'};
}

#----------------------------------------------------------------------
#Legacy:

sub validate_accept_or_die {
    my ($self, $received) = @_;

    my $should_be = $self->_get_accept();

    return if $received eq $should_be;

    die Net::WebSocket::X->create('BadAccept', $should_be, $received );
}

#----------------------------------------------------------------------

sub _create_header_lines {
    my ($self) = @_;

    my $path = $self->{'uri_path'};

    if (!length $path) {
        $path = '/';
    }

    if (length $self->{'uri_query'}) {
        $path .= "?$self->{'uri_query'}";
    }

    return (
        "GET $path HTTP/1.1",
        "Host: $self->{'uri_host'}",

        #For now let’s assume no one wants any other Upgrade:
        #or Connection: values than the ones WebSocket requires.
        'Upgrade: websocket',
        'Connection: Upgrade',

        "Sec-WebSocket-Key: $self->{'key'}",
        'Sec-WebSocket-Version: ' . Net::WebSocket::Constants::PROTOCOL_VERSION(),

        $self->_encode_extensions(),

        $self->_encode_subprotocols(),

        ( $self->{'origin'} ? "Origin: $self->{'origin'}" : () ),
    );
}

sub _valid_headers_or_die {
    my ($self) = @_;

    my @needed = $self->_missing_generic_headers();
    push @needed, 'Sec-WebSocket-Accept' if !$self->{'_accept_header_ok'};

    if (@needed) {
        die Net::WebSocket::X->create('MissingHeaders', @needed);
    }

    return;
}

sub _consume_peer_header {
    my ($self, $name => $value) = @_;

    for my $hdr_part ( qw( Accept Protocol Extensions ) ) {
        if ($name eq "Sec-WebSocket-$hdr_part") {
            if ( $self->{"_got_$name"} ) {
                die Net::WebSocket::X->create('BadHeader', $name, $value, 'duplicate');    #XXX TODO - specific?
            }

            $self->{"_got_$name"}++;
        }
    }

    if ($name eq 'Sec-WebSocket-Accept') {
        $self->validate_accept_or_die($value);
        $self->{'_accept_header_ok'} = 1;
    }
    elsif ($name eq 'Sec-WebSocket-Protocol') {
        if (!grep { $_ eq $value } @{ $self->{'subprotocols'} }) {
            die Net::WebSocket::X->create('BadHeader', $name, $value, 'Unrecognized subprotocol'); #XXX TODO - specific?
        }

        $self->{'_subprotocol'} = $value;
    }
    else {
        $self->_consume_generic_header($name => $value);
    }

    return;
}

sub _validate_received_protocol {
    my ($self, $value) = @_;

    Module::Load::load('Net::WebSocket::HTTP');

    my @split = Net::WebSocket::HTTP::split_tokens($value);
    if (@split > 1) {
        die Net::WebSocket::X->new('BadHeader', 'Sec-WebSocket-Protocol', $value);
    }

    if (!grep { $value eq $_ } @{ $self->{'subprotocols'} }) {
        die "Unrecognized subprotocol: “$value”";   #TODO XXX
    }

    return;
}

sub _handle_unrecognized_extension {
    my ($self, $xtn_obj) = @_;

    die "Unrecognized extension: " . $xtn_obj->to_string(); #XXX TODO
}


sub _create_key {
    Module::Load::load('MIME::Base64') if !MIME::Base64->can('encode');

    #NB: Not cryptographically secure, but it should be good enough
    #for the purpose of a nonce.
    my $sixteen_bytes = pack 'S8', map { rand 65536 } 1 .. 8;

    my $b64 = MIME::Base64::encode_base64($sixteen_bytes);
    chomp $b64;

    return $b64;
}

#Send all extensions to the server in the request.
use constant _should_include_extension_in_headers => 1;

1;
