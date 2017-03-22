package Net::WebSocket::Parser;

=encoding utf-8

=head1 NAME

Net::WebSocket::Parser - Parse WebSocket from a filehandle

=head1 SYNOPSIS

    my $parse = Net::WebSocket::Parser->new( $filehandle, $pre_buffer );

    #See below for error responses
    my $frame = $parse->get_next_frame();

The extra parameter to C<new()>, C<$pre_buffer>, is whatever you may need to
parse first and may have already been read from the filehandle. For example, if
you’re the client and you read the first 2 KiB from the server, and if the
server has sent frames immediately after its handshake, you’ll probably have
already read at least part of those initial frames from the server into
C<$pre_buffer>.

=head1 METHODS

=head2 I<OBJ>->get_next_frame()

A call to this methods yields one of the following:

=over

=item * If a frame can be read, it will be returned.

=item * If only a partial frame is ready, undef is returned.

=item * If the filehandle is an OS-level filehandle and an error other than EINTR
occurs, L<Net::WebSocket::X::ReadFilehandle> is thrown.
Also note that EAGAIN produces an exception if and only if that error occurs
on the initial read. (See below.)

=item * If nothing at all is returned, and there is no error,
L<Net::WebSocket::X::EmptyRead> is thrown. (This likely means that
the filehandle/socket is closed.)

=head1 I/O DETAILS

This reads from the filehandle exactly as many bytes as are needed at a
given time: the first read is two bytes, after which the number of bytes
that those two bytes indicate are read.

For this to work, each non-blocking read must follow a
call to C<select()> to ensure that the filehandle is ready to
yield data. Otherwise you’ll deal with spurious EAGAIN errors and the like.
The intent here is that you should not need to ignore any OS errors.

If EINTR is received, we retry the read.

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
