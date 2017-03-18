package Net::WebSocket::Parser;

=encoding utf-8

=head1 NAME

Net::WebSocket::Parser - Parse WebSocket from a filehandle

=head1 SYNOPSIS

    my $parse = Net::WebSocket::Parser->new( $filehandle, $pre_buffer );

    while ( my $msg = $parse->get_next_message( \&_control_frame_handler ) ) {
        print $msg->get_payload();
    }

    while ( my $frame = $parse->get_next_frame() ) {
        ...
    }

The extra parameter to C<new()>, C<$pre_buffer>, is whatever you may need to
parse first and may have already been read from the filehandle. For example, if
you’re the client and you read the first 2 KiB from the server, and if the
server has sent frames immediately after its handshake, you’ll probably have
already read at least part of those initial frames from the server into
C<$pre_buffer>.

A message consists of 1 or more frames. A multi-frame message is said
to be “fragmented”. Control messages cannot be fragmented.

Note that C<get_next_message()> accepts a coderef as an optional argument;
this coderef is invoked as a callback whenever the received frame is a control
frame. You probably should always include this with a call to
C<get_next_message()>, as the WebSocket peer is free to send a ping or even
to close the connection among message fragments.

In the event that you want to avoid buffering an entire fragmented message,
you should use C<get_next_frame()> and manually examine each frame’s
C<get_type()> and C<get_fin()> results to determine when the message is done.

=head1 CUSTOM FRAMES SUPPORT

To support reception of custom frame types you’ll probably want to subclass
this module and define a specific custom constant for each supported opcode:

    package My::WebSocket::Parser;

    use parent qw( Net::WebSocket::Parser );

    use constant OPCODE_CLASS_3 => 'My::WebSocket::Frame::booya';

… where C<My::WebSocket::Frame::booya> is itself a subclass of
C<Net::WebSocket::Base::DataFrame>.

You can also use this to override the default
classes for built-in frame types; e.g., C<OPCODE_CLASS_10()> will override
L<Net::WebSocket::Frame::pong> as the class will be used for pong frames
that this module receives.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Base::Parser
    Net::WebSocket::Base::ReadFilehandle
);

1;
