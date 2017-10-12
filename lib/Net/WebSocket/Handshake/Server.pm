package Net::WebSocket::Handshake::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::Handshake::Server

=head1 SYNOPSIS

    my $hsk = Net::WebSocket::Handshake::Server->new(

        #optional
        subprotocols => [ 'echo', 'haha' ],

        #optional; see below for the interface that these objects
        #need to expose.
        extensions => \@extension_objects,
    );

    $hsk->valid_method_or_die( $http_method );  #optional

    $hsk->consume_peer_headers(@headers_kv_pairs);

    #Note the need to conclude the header text manually.
    #This is by design, so you can add additional headers.
    my $resp_hdr = $hsk->create_header_text() . "\x0d\x0a";

=head1 DESCRIPTION

This class implements WebSocket handshake logic for a server.

Because Net::WebSocket tries to be agnostic about how you parse your HTTP
headers, this class doesn’t do a whole lot for you: it’ll give you the
C<Sec-WebSocket-Accept> header value given a base64
C<Sec-WebSocket-Key> (i.e., from the client), and it’ll give you
a “basic” response header text.

B<NOTE:> C<create_header_text()> does NOT provide the extra trailing
CRLF to conclude the HTTP headers. This allows you to add additional
headers beyond what this class gives you.

=head1 EXTENSION CLASSES

This class uses the following methods of the objects of the
C<extensions> array:



=head1 LEGACY INTERFACE

Prior to version 0.5 this module was a great deal less “helpful”:
it required callers to parse out and write WebSocket headers,
doing most of the validation manually. Version 0.5 added a generic
interface for entering in HTTP headers, which allows Net::WebSocket to
handle the parsing and creation of HTTP headers.

For now the legacy functionality is being left in; however,
it is considered DEPRECATED and will be removed eventually.

    my $hsk = Net::WebSocket::Handshake::Server->new(

        #base 64
        key => '..',

        #optional - same as in non-legacy interface
        subprotocols => [ 'echo', 'haha' ],

        #optional, instances of Net::WebSocket::Handshake::Extension
        extensions => \@extension_objects,
    );

    #Use this to write out the Sec-WebSocket-Accept header.
    my $b64 = $hsk->get_accept();

=cut

use strict;
use warnings;

use parent qw( Net::WebSocket::Handshake );

use Call::Context ();
use Digest::SHA ();

use Net::WebSocket::Constants ();
use Net::WebSocket::X ();

sub valid_method_or_die {
    my ($self, $method) = @_;

    if ($method ne Net::WebSocket::Constants::REQUIRED_HTTP_METHOD()) {
        die Net::WebSocket::X->new('BadHTTPMethod', $method);
    }

    return;
}

*get_accept = __PACKAGE__->can('_get_accept');

sub _consume_peer_header {
    my ($self, $name => $value) = @_;

    if ($name eq 'Sec-WebSocket-Version') {
        if ( $value ne Net::WebSocket::Constants::PROTOCOL_VERSION() ) {
            die Net::WebSocket::X->new('BadHeader', 'Sec-WebSocket-Version', $value, 'Unsupported protocol version; must be ' . Net::WebSocket::Constants::PROTOCOL_VERSION());
        }

        $self->{'_version_ok'} = 1;
    }
    elsif ($name eq 'Sec-WebSocket-Key') {
        $self->{'key'} = $value;
    }
    elsif ($name eq 'Sec-WebSocket-Protocol') {
        Module::Load::load('Net::WebSocket::HTTP');

        for my $token ( Net::WebSocket::HTTP::split_tokens($value) ) {
            if (!defined $self->{'_subprotocol'}) {
                ($self->{'_subprotocol'}) = grep { $_ eq $token } @{ $self->{'subprotocols'} };
            }
        }
    }
    else {
        $self->_consume_generic_header($name => $value);
    }

    return;
}

#Send only those extensions that we’ve deduced the client can actually use.
sub _should_include_extension_in_headers {
    my ($self, $xtn) = @_;

    return $xtn->ok_to_use();
}

sub _encode_subprotocols {
    my ($self) = @_;

    local $self->{'subprotocols'} = defined($self->{'_subprotocol'}) ? [ $self->{'_subprotocol'} ] : undef if $self->{'_no_use_legacy'};

    return $self->SUPER::_encode_subprotocols();
}

sub _valid_headers_or_die {
    my ($self) = @_;

    my @needed = $self->_missing_generic_headers();

    push @needed, 'Sec-WebSocket-Version' if !$self->{'_version_ok'};
    push @needed, 'Sec-WebSocket-Key' if !$self->{'key'};

    die "Need: [@needed]" if @needed;

    return;
}

sub _create_header_lines {
    my ($self) = @_;

    Call::Context::must_be_list();

    return (
        'HTTP/1.1 101 Switching Protocols',

        #For now let’s assume no one wants any other Upgrade:
        #or Connection: values than the ones WebSocket requires.
        'Upgrade: websocket',
        'Connection: Upgrade',

        'Sec-WebSocket-Accept: ' . $self->get_accept(),

        $self->_encode_subprotocols(),

        $self->_encode_extensions(),
    );
}

use constant _handle_unrecognized_extension => ();

1;
