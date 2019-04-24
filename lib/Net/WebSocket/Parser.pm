package Net::WebSocket::Parser;

=encoding utf-8

=head1 NAME

Net::WebSocket::Parser - Parse WebSocket from a filehandle

=head1 SYNOPSIS

    my $iof = IO::Framed->new($fh);

    my $parse = Net::WebSocket::Parser->new($iof);

    #See below for error responses
    my $frame = $parse->get_next_frame();

C<$iof> should normally be an instance of L<IO::Framed::Read>. You’re free to
pass in anything with a C<read()> method, but that method must implement
the same behavior as C<IO::Framed::Read::read()>.

=head1 METHODS

=head2 I<OBJ>->get_next_frame()

A call to this method yields one of the following:

=over

=item * If a frame can be read, it will be returned.

=item * If we hit an empty read (i.e., indicative of end-of-file),
empty string is returned.

=item * If only a partial frame is ready, undef is returned.

=back

=head1 I/O DETAILS

L<IO::Framed> was born out of work on this module; see that module’s
documentation for the particulars of working with it. In particular,
note the exceptions L<IO::Framed::X::EmptyRead> and
L<IO::Framed::X::ReadError>.

Again, you can use an equivalent interface for frame chunking if you wish.

=head1 CONCERNING EMPTY READS

An empty read is how we detect that a file handle (or socket, etc.) has no
more data to read. Generally we shouldn’t get this in WebSocket since it
means that a peer endpoint has gone away without sending a close frame.
It is thus recommended that applications regard an empty read on a WebSocket
stream as an error condition; e.g., if you’re using L<IO::Framed::Read>,
you should NOT enable the C<allow_empty_read()> behavior.

Nevertheless, this module (and L<Net::WebSocket::Endpoint>) do work when
that flag is enabled.

=head1 CUSTOM FRAMES SUPPORT

To support reception of custom frame types you’ll probably want to subclass
this module and define a specific custom constant for each supported opcode,
e.g.:

    package My::WebSocket::Parser;

    use parent qw( Net::WebSocket::Parser );

    use constant OPCODE_CLASS_3 => 'My::WebSocket::Frame::booya';

… where C<My::WebSocket::Frame::booya> is itself a subclass of
C<Net::WebSocket::Base::DataFrame>.

You can also use this to override the default
classes for built-in frame types; e.g., C<OPCODE_CLASS_10()> will override
L<Net::WebSocket::Frame::pong> as the class will be used for pong frames
that this module receives. That could be useful, e.g., for compression
extensions, where you might want the C<get_payload()> method to
decompress so that that detail is abstracted away.

=cut

use strict;
use warnings;

use Module::Runtime ();

use Net::WebSocket::Constants ();
use Net::WebSocket::X ();

use constant {
    OPCODE_CLASS_0 => 'Net::WebSocket::Frame::continuation',
    OPCODE_CLASS_1 => 'Net::WebSocket::Frame::text',
    OPCODE_CLASS_2 => 'Net::WebSocket::Frame::binary',
    OPCODE_CLASS_8 => 'Net::WebSocket::Frame::close',
    OPCODE_CLASS_9 => 'Net::WebSocket::Frame::ping',
    OPCODE_CLASS_10 => 'Net::WebSocket::Frame::pong',
};

sub new {
    my ($class, $reader) = @_;

    if (!(ref $reader)->can('read')) {
        die "“$reader” needs a read() method!";
    }

    return bless {
        _reader => $reader,
        _partial_frame => q<>,
    }, $class;
}

#Create these out here so that we don’t create/destroy them on each frame.
#As long as we don’t access them prior to writing to them this is fine.
my ($oct1, $oct2, $len, $mask_size, $len_len, $longs, $long);

sub get_next_frame {
    my ($self) = @_;

    local $@;

    #It is really, really inconvenient that Perl has no “or” operator
    #that considers q<> falsey but '0' truthy. :-/
    #That aside, if indeed all we read is '0', then we know that’s not
    #enough, and we can return.
    my $first2 = $self->_read_with_buffer(2);
    if (!$first2) {
        return defined($first2) ? q<> : undef;
    }

    ($oct1, $oct2) = unpack('CC', $first2 );

    $len = $oct2 & 0x7f;

    $mask_size = ($oct2 & 0x80) && 4;

    $len_len = ($len == 0x7e) ? 2 : ($len == 0x7f) ? 8 : 0;

    my ($len_buf, $mask_buf);

    if ($len_len) {
        $len_buf = $self->_read_with_buffer($len_len);

        if (!$len_buf) {
            substr( $self->{'_partial_frame'}, 0, 0, $first2 );
            return defined($len_buf) ? q<> : undef;
        };

        if ($len_len == 2) {
            ($longs, $long) = ( 0, unpack('n', $len_buf) );
        }
        else {

            #Do it this way to support 32-bit systems.
            ($longs, $long) = ( unpack('NN', $len_buf) );
        }
    }
    else {
        ($longs, $long) = ( 0, $len );
        $len_buf = q<>;
    }

    if ($mask_size) {
        $mask_buf = $self->_read_with_buffer($mask_size);
        if (!$mask_buf) {
            substr( $self->{'_partial_frame'}, 0, 0, $first2 . $len_buf );
            return defined($mask_buf) ? q<> : undef;
        };
    }
    else {
        $mask_buf = q<>;
    }

    my $payload = q<>;

    for ( 1 .. $longs ) {

        #32-bit systems don’t know what 2**32 is.
        #MacOS, at least, also chokes on sysread( 2**31, … )
        #(Is their size_t signed??), even on 64-bit.
        for ( 1 .. 4 ) {
            my $append_ok = $self->_append_chunk( 2**30, \$payload );
            if (!$append_ok) {
                substr( $self->{'_partial_frame'}, 0, 0, $first2 . $len_buf . $mask_buf . $payload );
                return defined($append_ok) ? q<> : undef;
            };
        }
    }

    if ($long) {
        my $append_ok = $self->_append_chunk( $long, \$payload );
        if (!$append_ok) {
            substr( $self->{'_partial_frame'}, 0, 0, $first2 . $len_buf . $mask_buf . $payload );
            return defined($append_ok) ? q<> : undef;
        }
    }

    $self->{'_partial_frame'} = q<>;

    my $opcode = $oct1 & 0xf;

    my $frame_class = $self->{'_opcode_class'}{$opcode} ||= do {
        my $class;
        if (my $cr = $self->can("OPCODE_CLASS_$opcode")) {
            $class = $cr->();
        }
        else {

            #Untyped because this is a coding error.
            die "$self: Unrecognized frame opcode: “$opcode”";
        }

        Module::Runtime::require_module($class) if !$class->can('new');

        $class;
    };

    return $frame_class->create_from_parse(\$first2, \$len_buf, \$mask_buf, \$payload);
}

# This will only return exactly the number of bytes requested.
# If fewer than we want are available, then we return undef.
# This incorporates the partial-frame buffer, which keeps get_next_frame()
# a bit simpler than it otherwise might be.
#
sub _read_with_buffer {
    my ($self, $length) = @_;

    # Prioritize the case where we have everything we need.
    # This will happen if, e.g., we got a partial frame on first read
    # and a subsequent read has to pick back up.

    if ( length($self->{'_partial_frame'}) < $length ) {
        my $deficit = $length - length($self->{'_partial_frame'});
        my $read = $self->{'_reader'}->read($deficit);

        if (!defined $read) {
            return undef;
        }
        elsif (!length $read) {
            return q<>;
        }

        return substr($self->{'_partial_frame'}, 0, length($self->{'_partial_frame'}), q<>) . $read;
    }

    return substr( $self->{'_partial_frame'}, 0, $length, q<> );
}

sub _append_chunk {
    my ($self, $length, $buf_sr) = @_;

    my $start_buf_len = length $$buf_sr;

    my $cur_buf;

    while (1) {
        my $read_so_far = length($$buf_sr) - $start_buf_len;

        $cur_buf = $self->_read_with_buffer($length - $read_so_far);
        return undef if !defined $cur_buf;

        return q<> if !length $cur_buf;

        $$buf_sr .= $cur_buf;

        last if (length($$buf_sr) - $start_buf_len) >= $length;
    }

    return 1;
}

1;
