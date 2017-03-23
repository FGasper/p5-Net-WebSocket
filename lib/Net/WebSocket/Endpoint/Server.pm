package Net::WebSocket::Endpoint::Server;

=encoding utf-8

=head1 NAME

Net::WebSocket::Endpoint::Server

=head1 SYNOPSIS

    my $ept = Net::WebSocket::Endpoint::Server->new(
        parser => $parser_obj,
        out => $out_fh,

        #optional, # of pings to send before we send a close
        max_pings => 5,

        on_data_frame => sub {
            my ($frame) = @_;

            #...
        }
    );

    if ( _we_timed_out_waiting_for_read_readiness() ) {
        $ept->check_heartbeat();
    }
    else {

        #This should only be called when reading won’t produce an error.
        #For example, in non-blocking I/O you’ll need a select() in front
        #of this. (Blocking I/O can just call it and wait!)
        $ept->get_next_message();

        #Check for this at the end of each cycle.
        _custom_logic_to_finish_up() if $ept->is_closed();
    }

=head1 DESCRIPTION

This module, like its twin, L<Net::WebSocket::Endpoint::Client>, attempts
to wrap up “obvious” bits of a WebSocket endpoint’s workflow into a
reusable component.

The basic workflow is shown in the SYNOPSIS; descriptions of the individual
methods follow:

=head1 METHODS

=head2 I<CLASS>->new( %OPTS )

Instantiate the class. Nothing is actually done here. Options are:

=over

=item * C<parser> (required) - An instance of L<Net::WebSocket::Parser>

=item * C<out> (required) - The endpoint’s output filehandle

=item * C<max_pings> (optional) - The maximum # of pings to send before
we send a C<close> frame (which ends the session).

=item * C<on_data_frame> (optional) - A callback that receives every data
frame that C<get_next_message()> receives. Use this to facilitate chunking.

If you want to avoid buffering a large message, you can do this:

    on_data_frame => sub {
        #... however you’re going to handle this chunk

        $_[0] = (ref $_[0])->new(
            payload_sr => \q<>,
            fin => $_[0]->get_fin(),
        );
    },

=back

=head2 I<OBJ>->get_next_message()

The “workhorse” method. It returns a data message if one is available
and is the next frame; otherwise, it returns undef.

This method also handles control frames that arrive before or among
message frames:

=over

=item * close: Respond with the identical close frame.

=item * ping: Send the appropriate pong frame.

=item * pong: Set the internal ping counter to zero. If the pong is
unrecognized (i.e., we’ve not sent the payload in a ping), then we send
a PROTOCOL_ERROR close frame.

=back

This method may not be called after a close frame has been sent (i.e.,
if the C<is_closed()> method returns true).

=head2 I<OBJ>->check_heartbeat()

Ordinarily, sends a distinct ping frame to the remote server
and increments the ping counter. Once a sent ping is
received back (i.e., a pong), the ping counter gets reset.

If the internal ping counter has already reached C<max_pings>, then we
<<<<<<< HEAD
send a PROTOCOL_ERROR close frame.
=======
send a PROTOCOL_ERROR close frame. Further I/O attempts on this object
will prompt an appropriate exception to be thrown.
>>>>>>> master

=head2 I<OBJ>->is_closed()

Return 1 or 0 to indicate whether we have tried to send a close frame.

=head1 EXTENSIONS

This module has several controls for supporting WebSocket extensions:

=over

=item * C<get_next_message()>’s returned messages will always contain
a C<get_frames()> method, which you can use to read the reserved bits
of the individual data frames.

=item * You can create C<on_*> methods on a subclass of this module
to handle different types of control frames. (e.g., C<on_foo(FRAME)>)
to handle frames of type C<foo>.) The C<parser> object that you pass
to the constructor has to be aware of such messages; for more details,
see the documentation for L<Net::WebSocket::Parser>.

=back

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Endpoint
    Net::WebSocket::Masker::Server
);

1;
