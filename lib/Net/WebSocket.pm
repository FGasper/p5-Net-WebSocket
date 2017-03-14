package Net::WebSocket;

our $VERSION = '0.01_01';

=encoding utf-8

=head1 NAME

Net::WebSocket - WebSocket protocol basics

=head1 DESCRIPTION

This distribution provides a set of fundamental tools for communicating via
L<https://tools.ietf.org/html/rfc6455|WebSocket>.
It is only concerned with the protocol itself;
the underlying transport mechanism is up to you: it could be a file,
a UNIX socket, ordinary TCP/IP, or whatever.

As a result of this “bare-bones” approach, Net::WebSocket can probably
fit your needs; however, it won’t interface directly with event frameworks,
so you’ll need to write your own handling layer.

This distribution provides five major areas of functionality:

=head2 1. PARSE WEBSOCKET

L<Net::WebSocket::ParseFilehandle> and L<Net::WebSocket::ParseString> expose
logic to parse a stream or a buffer into either messages or frames.

=head2 2. SERIALIZE RAW DATA

For serialization turn to these modules:

=over

=item * L<Net::WebSocket::SerializeFilehandle::Client>

=item * L<Net::WebSocket::SerializeFilehandle::Server>

=item * L<Net::WebSocket::SerializeString::Client>

=item * L<Net::WebSocket::SerializeString::Server>

=back

L<As per the specification|https://tools.ietf.org/html/rfc6455#section-5.1>,
client serializers “MUST” mask the data randomly, whereas server serializers
“MUST NOT” do this. Net::WebSocket does this for you automatically
(courtesy of L<Bytes::Random::Secure::Tiny>), but you need to distinguish
between client serializers—which do masking—and server serializers, which
don’t mask.

Recall that in some languages—like JavaScript!—the difference between
“text” and “binary” is much more significant than for us in Perl.

=head2 3. CREATE MESSAGES

A message is the smallest unit of application-level payload from WebSocket;
that is, a single group of fragmented frames is understood as one “message”.
(Likewise, a single, complete frame is also one “message”.)

This functionality, because of WebSocket’s mandatory client-to-server payload
masking, exists as part of the serialization classes. See those for more
information.

=head2 4. CREATE FRAMES

You can create a WebSocket frame directly using one of the message type
classes:

=over

=item * L<Net::WebSocket::Frame::text>

=item * L<Net::WebSocket::Frame::binary>

=item * L<Net::WebSocket::Frame::ping>

=item * L<Net::WebSocket::Frame::pong>

=item * L<Net::WebSocket::Frame::close>

=item * L<Net::WebSocket::Frame::continuation>

=back

This lets you do
some illegal things like misusing continuation frames. You shouldn’t
use this unless you’re familiar with the guts of the WebSocket protocol.

=head2 5. HANDSHAKE LOGIC

There are lots of levels at which handshake functionality may be desired;
consult the following modules for more details of what this distribution
offers for now:

=over

=item L<Net::WebSocket::Handshake::Client>

=item L<Net::WebSocket::Handshake::Server>

=back

#----------------------------------------------------------------------

=head1 IMPLEMENTATION NOTES

Net::WebSocket tries to be as light as possible and so, when it parses out
a frame, at first only a base L<Net::WebSocket::Frame> implementation is
created. An AUTOLOAD method will “upgrade” any such frame that needs the
specific methods of its class.

#----------------------------------------------------------------------

=head1 TODO

There currently is no handling of the C<Sec-WebSocket-Extensions> header.

#----------------------------------------------------------------------

=head1 SEE ALSO

L<Protocol::WebSocket> is an older WebSocket module that does two
things this distribution avoids by design:

=over

=item * Network and event logic

=item * Support for pre-RFC-6455 versions of WebSocket

=back

=head1 REPOSITORY

https://github.com/FGasper/p5-Data-WebSocket

=head1 AUTHOR

Felipe Gasper (FELIPE)

=head1 COPYRIGHT

Copyright 2017 by L<http://gaspersoftware.com|Gasper Software Consulting, LLC>

=head1 LICENSE

This distribution is released under the license as Perl.

=cut

1;
