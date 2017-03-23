package Net::WebSocket;

our $VERSION = '0.01';

=encoding utf-8

=head1 NAME

Net::WebSocket - WebSocket in Perl

=head1 SYNOPSIS

    my $handshake = Net::WebSocket::Handshake::Client->new(
        uri => $uri,
    );

    syswrite $inet, $handshake->create_header_text() . "\x0d\x0a" or die $!;

    my $req = HTTP::Response->parse($hdrs_txt);

    #XXX More is required for the handshake validation in production!
    my $accept = $req->header('Sec-WebSocket-Accept');
    $handshake->validate_accept_or_die($accept);

    my $parser = Net::WebSocket::ParseFilehandle->new(
        $inet,
        $leftover_from_header_read,     #can be nonempty on the client
    );

    my $ept = Net::WebSocket::Endpoint::Client->new(
        out => $inet,
        parser => $parser,
    );

    #Determine that $inet can be read from …

    my $msg = $ept->get_next_message();

    #… or, if we timeout while waiting for $inet be ready for reading:

    $ept->check_heartbeat();
    exit if $ept->is_closed();

=head1 ALPHA QUALITY

This is a preliminary release. It is not meant for
production work, but please do play with it and see how it works for you.
Bug reports, especially with reproducible test cases, would be very welcome!

Note that while breaking changes to the interface are unlikely,
neither are they out of the question. Change the changelog before updating!

=head1 DESCRIPTION

This distribution provides a set of fundamental tools for communicating via
L<WebSocket|https://tools.ietf.org/html/rfc6455>.
It is only concerned with the protocol itself;
the underlying transport mechanism is up to you: it could be a file,
a UNIX socket, ordinary TCP/IP, or whatever.

As a result of this “bare-bones” approach, Net::WebSocket can probably
fit your needs; however, it won’t absolve you of the need to know the
WebSocket protocol itself. It also doesn’t do I/O for you, but there are some
examples
of using L<IO::Select> for this in the distribution’s C<demo/> directory.

Net::WebSocket is not a “quick-and-cheap” WebSocket solution; rather,
it attempts to support the protocol—and only that protocol—as
completely, usefully, and flexibly as possible.

=head1 OVERVIEW

WebSocket is almost “two protocols for the price of one”: the
HTTP-derived handshake logic, then the framing logic for the actual data
exchange. The handshake portion is complex enough, and has enough support
from CPAN’s HTTP modules, that this distribution only provides a few basic tools
for doing the handshake. It’s enough to get you where you need to go, but
not much more.

Here are the main modules:

=head2 L<Net::WebSocket::Handshake::Server>

=head2 L<Net::WebSocket::Handshake::Client>

Logic for handshakes. These are probably most useful in tandem with
modules like L<HTTP::Request> and L<HTTP::Response>.


=head2 L<Net::WebSocket::Endpoint::Server>

=head2 L<Net::WebSocket::Endpoint::Client>

The highest-level abstraction that this distribution provides. It parses input
and responds to control frames and timeouts. You can use this to receive
streamed (i.e., fragmented) transmissions as well.

=head2 L<Net::WebSocket::Streamer::Server>

=head2 L<Net::WebSocket::Streamer::Client>

Useful for sending streamed (fragmented) data rather than
a full message in a single frame.

=head2 L<Net::WebSocket::Parser>

Translate WebSocket frames out of a filehandle into useful data for
your application.

=head2 Net::WebSocket::Frame::*

Useful for creating raw frames. For data frames (besides continuation),
these will be your bread-and-butter. See L<Net::WebSocket::Frame::text>
for sample usage.

=head1 IMPLEMENTATION NOTES

=head2 Masking

As per L<the specification|https://tools.ietf.org/html/rfc6455#section-5.1>,
client serializers “MUST” mask the data randomly, whereas server serializers
“MUST NOT” do this. Net::WebSocket does this for you automatically
(courtesy of L<Bytes::Random::Secure::Tiny>), but you need to distinguish
between client serializers—which mask their payloads—and server serializers,
which don’t mask.

=head2 Text vs. Binary

Recall that in some languages—like JavaScript!—the difference between
“text” and “binary” is much more significant than for us in Perl.

=head2 Parsed Frame Classes

Net::WebSocket tries to be as light as possible and so, when it parses out
a frame, at first only a base L<Net::WebSocket::Frame> implementation is
created. An AUTOLOAD method will “upgrade” any such frame that needs the
specific methods of its class.

=head1 EXTENSION SUPPORT

The WebSocket specification describes several methods of extending the
protocol, all of which Net::WebSocket supports:

=over

=item * The three reserved bits in each frame’s header.
(See L<Net::WebSocket::Frame>.)

=item * Additional opcodes: 3-7 and 11-15. You’ll need to subclass
L<Net::WebSocket::Frame> for this, and you will likely want to subclass
L<Net::WebSocket::Parser>.
If you’re using the custom classes for streaming, then you can
also subclass L<Net::WebSocket::Streamer>. See each of those modules for
more information on doing this.

B<THIS IS NOT WELL TESTED.> Proceed with caution, and please file bug
reports as needed.

=item * Apportion part of the payload data for the extension. This you
can do in your application.

=back

=head1 TODO

=over

=item * Convert all plain C<die()>s to typed exceptions.

=item * Add tests, especially for extension support.

=back

=head1 SEE ALSO

L<Protocol::WebSocket> is an older module that supports
pre-standard versions of the WebSocket protocol.

L<Net::WebSocket::Server> implements only server behaviors and
gives you more automation.

L<Net::WebSocket::EV> uses XS to call a C library.

=head1 REPOSITORY

L<https://github.com/FGasper/p5-Net-WebSocket>

=head1 AUTHOR

Felipe Gasper (FELIPE)

=head1 COPYRIGHT

Copyright 2017 by L<Gasper Software Consulting, LLC|http://gaspersoftware.com>

=head1 LICENSE

This distribution is released under the same license as Perl.

=cut

1;
