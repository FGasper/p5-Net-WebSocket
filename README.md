# NAME

Net::WebSocket - WebSocket in Perl

# SYNOPSIS

    use Net::WebSocket::Handshake::Client ();
    use Net::WebSocket::HTTP_R ();

    my $handshake = Net::WebSocket::Handshake::Client->new(
        uri => $uri,
    );

    syswrite $inet, $handshake->to_string() or die $!;

    #You can parse HTTP headers however you want;
    #Net::WebSocket makes no assumptions about this.
    my $resp = HTTP::Response->parse($hdrs_txt);

    #If you use an interface that’s compatible with HTTP::Response,
    #then you can take advantage of this convenience function;
    #otherwise you’ll need to do a bit more work.
    Net::WebSocket::HTTP_R::handshake_parse_response( $handshake, $resp );

    #See below about IO::Framed
    my $iof = IO::Framed->new($inet);

    my $parser = Net::WebSocket::Parser->new($iof);

    my $ept = Net::WebSocket::Endpoint::Client->new(
        parser => $parser,
        out => $iof,
    );

    $iof->write(
        $ept->create_message( 'text', 'Hello, world' )->to_bytes()
    );

    #Determine that $inet can be read from …

    my $msg = $ept->get_next_message();

    #… or, if we timeout while waiting for $inet to be ready for reading:

    $ept->check_heartbeat();
    exit if $ept->is_closed();

# BETA QUALITY

This is a beta release. It should be safe for production, but there could
still be small changes to the API. Please check the changelog before
upgrading.

# DESCRIPTION

This distribution provides a set of fundamental tools for communicating via
[WebSocket](https://tools.ietf.org/html/rfc6455).
It is only concerned with the protocol itself;
the underlying transport mechanism is up to you: it could be a file,
a UNIX socket, ordinary TCP/IP, some funky `tie()`d object, or whatever.

Net::WebSocket also “has no opinions” about how you should do I/O or HTTP
headers. There are too many different ways to accomplish HTTP header
management in particular for it to be sensible for a WebSocket library to
impose any one approach. As a result of this, Net::WebSocket can probably
fit your project with minimal overhead. There are some examples
of how you might write complete applications (client or server)
in the distribution’s `demo/` directory.

Net::WebSocket emphasizes flexibility and lightness rather than the more
monolithic approach in modules like [Mojolicious](https://metacpan.org/pod/Mojolicious).
Net::WebSocket should support anything
that the WebSocket protocol itself can do, as lightly as possible and without
prejudice as to how you want to do it: extensions, streaming, blocking or
non-blocking I/O, arbitrary HTTP headers, etc. The end result should be a
clean, light implementation that will grow (or shrink!) as your needs
dictate.

# OVERVIEW

Here are the main modules:

- [Net::WebSocket::Handshake::Server](https://metacpan.org/pod/Net::WebSocket::Handshake::Server)
- [Net::WebSocket::Handshake::Client](https://metacpan.org/pod/Net::WebSocket::Handshake::Client)

    Logic for handshakes. Every application needs one of these.
    This handles all headers and can also negotiate
    subprotocols and extensions for you.

- [Net::WebSocket::HTTP\_R](https://metacpan.org/pod/Net::WebSocket::HTTP_R)

    A thin convenience wrapper for [HTTP::Request](https://metacpan.org/pod/HTTP::Request) and [HTTP::Response](https://metacpan.org/pod/HTTP::Response),
    CPAN’s “standard” classes to represent HTTP requests and responses.
    Net::WebSocket::HTTP\_R should also work with other classes whose
    interfaces are compatible with these “standard” ones.

- [Net::WebSocket::Endpoint::Server](https://metacpan.org/pod/Net::WebSocket::Endpoint::Server)
- [Net::WebSocket::Endpoint::Client](https://metacpan.org/pod/Net::WebSocket::Endpoint::Client)

    A high-level abstraction to parse input
    and respond to control frames and timeouts. You can use this to receive
    streamed (i.e., fragmented) transmissions as well. You don’t have to use
    this module, but it will make your life easier.

- [Net::WebSocket::Parser](https://metacpan.org/pod/Net::WebSocket::Parser)

    Translate WebSocket frames out of a filehandle into useful data for
    your application.

- [Net::WebSocket::Streamer::Server](https://metacpan.org/pod/Net::WebSocket::Streamer::Server)
- [Net::WebSocket::Streamer::Client](https://metacpan.org/pod/Net::WebSocket::Streamer::Client)

    Useful for sending streamed (fragmented) data rather than
    a full message in a single frame.

- Net::WebSocket::Frame::\*

    Useful for creating raw frames. You probably shouldn’t call these
    classes directly; instead, use Endpoint’s `create_message()` method.
    But if you want to dig deeply, these will be your bread and butter.
    See [Net::WebSocket::Frame::text](https://metacpan.org/pod/Net::WebSocket::Frame::text) for sample usage.

# IMPLEMENTATION NOTES

## Handshakes

WebSocket uses regular HTTP headers for its handshakes. Because there are
many different solutions around for parsing HTTP headers, Net::WebSocket
is “agnostic” about how that’s done. The advantage is that if you’ve got
a custom solution for parsing headers then Net::WebSocket can fit into
that quite easily.

The liability of this is that you, the library user, must give headers
directly to your Handshake object. (NB: [Net::WebSocket::HTTP\_R](https://metacpan.org/pod/Net::WebSocket::HTTP_R) might
be able to do this for you.)

## Masking

As per [the specification](https://tools.ietf.org/html/rfc6455#section-5.1),
client serializers “MUST” mask the data randomly, whereas server serializers
“MUST NOT” do this. Net::WebSocket does this for you automatically,
but you need to distinguish
between client serializers—which mask their payloads—and server serializers,
which don’t mask.

This module used to do this with [Bytes::Random::Secure::Tiny](https://metacpan.org/pod/Bytes::Random::Secure::Tiny), but
that seems like overkill given that the masking is only there to accommodate
peculiarities of certain proxies. Moreover, TLS is widely available and
[free now besides](https://letsencrypt.org), and it will randomize the data
stream anyway. So, nowadays we just use Perl’s `rand()` built-in.

## Text vs. Binary

Recall that in some languages—like JavaScript!—the difference between
“text” and “binary” is much more significant than for us in Perl.

## Use of [IO::Framed](https://metacpan.org/pod/IO::Framed)

CPAN’s [IO::Framed](https://metacpan.org/pod/IO::Framed) provides a straightforward interface for chunking up
data from byte streams into frames. It also provides a write buffer for
non-blocking writes, and it (by default) retries on EINTR. You don’t have to
use it (which is why it’s not listed as a requirement), but you’ll need to
provide a compatible interface if you don’t.

See the demo scripts that use [IO::Framed](https://metacpan.org/pod/IO::Framed) for an example of when you may
need a different solution here.

# EXTENSION SUPPORT

The WebSocket specification describes several methods of extending the
protocol, all of which Net::WebSocket supports:

- The three reserved bits in each frame’s header.
(See [Net::WebSocket::Frame](https://metacpan.org/pod/Net::WebSocket::Frame).) This is used, e.g., in the
[permessage-deflate extension](https://tools.ietf.org/html/rfc7692).
(See below for its implementation in Net::WebSocket.)
- Additional opcodes: 3-7 and 11-15. You’ll need to subclass
[Net::WebSocket::Frame](https://metacpan.org/pod/Net::WebSocket::Frame) for this, and you will likely want to subclass
[Net::WebSocket::Parser](https://metacpan.org/pod/Net::WebSocket::Parser).
If you’re using the custom classes for streaming, then you can
also subclass [Net::WebSocket::Streamer](https://metacpan.org/pod/Net::WebSocket::Streamer). See each of those modules for
more information on doing this.

    **THIS IS NOT WELL TESTED.** Proceed with caution, and please file bug
    reports as needed. (I personally don’t know of any applications that
    actually use this.)

- Apportion part of the payload data for the extension. This you
can do in your application.

## permessage-deflate

Net::WebSocket fully supports the permessage-deflate (compression) extension.
See [Net::WebSocket::PMCE::deflate](https://metacpan.org/pod/Net::WebSocket::PMCE::deflate) for details.

# TODO

At this point Net::WebSocket seems to support everything the WebSocket
protocol can (usefully) do, including compression. Please file bug reports
for any issues that may crop up.

- Add more tests.

# SEE ALSO

[Mojolicious](https://metacpan.org/pod/Mojolicious) has a WebSocket implementation. It’s not as complete as
Net::WebSocket, but if you’re using Mojolicious, you might try this first.

[Protocol::WebSocket](https://metacpan.org/pod/Protocol::WebSocket) is an older module that supports
pre-standard versions of the WebSocket protocol. It’s similar to this one
in that it gives you just the protocol itself, but it doesn’t give you
things like automatic ping/pong/close, classes for each message type, etc.

[Net::WebSocket::Server](https://metacpan.org/pod/Net::WebSocket::Server) implements only server behaviors and
gives you more automation than P::WS.

[Net::WebSocket::EV](https://metacpan.org/pod/Net::WebSocket::EV) uses XS to call [wslay](http://wslay.sourceforge.net).
As of this writing it lacks support for handshake logic.

# REPOSITORY

[https://github.com/FGasper/p5-Net-WebSocket](https://github.com/FGasper/p5-Net-WebSocket)

# AUTHOR

Felipe Gasper (FELIPE)

# COPYRIGHT

Copyright 2018-2019 by [Gasper Software Consulting](http://gaspersoftware.com)

# LICENSE

This distribution is released under the same license as Perl.
