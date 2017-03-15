package Net::WebSocket::Parser;

use strict;
use warnings;

use Module::Load ();

use Net::WebSocket::Frame ();
use Net::WebSocket::X ();

sub get_next_frame {
    my ($self) = @_;

    if (!exists $self->{'_buffer'}) {
        $self->{'_buffer'} = q<>;
    }

    #It is really, really inconvenient that Perl has no “or” operator
    #that considers q<> falsey but '0' truthy. :-/
    #That aside, if indeed all we read is '0', then we know that’s not
    #enough, and we can return.
    my $first2 = $self->_read_with_buffer(2) or return undef;

    #Now that we’ve read our header bytes, we’ll read some more.
    #There may not actually be anything to read, though, in which case
    #some readers will error (e.g., EAGAIN from a non-blocking filehandle).
    #From a certain ideal we’d return #on each individual read to allow
    #the reader to wait until there is more data ready; however, for
    #practicality (and speed) let’s go ahead and try to read the rest of
    #the frame. That means we need to set some flag to let the reader know
    #not to die() if there’s no more data currently, as we’re probably
    #expecting more soon to complete the frame.
    local $self->{'_reading_frame'} = 1;

    my $oct2 = unpack('xC', $first2 );

    my $len = $oct2 & 0x7f;

    my $mask_size = ($oct2 & 0x80) && 4;

    my $len_len = ($len == 0x7e) ? 2 : ($len == 0x7f) ? 8 : 0;
    my $len_buf = q<>;

    my ($longs, $long);

    if ($len_len) {
        $len_buf = $self->_read_with_buffer($len_len) or do {
            substr( $self->{'_buffer'}, 0, 0, $first2 );
            return undef;
        };

        if ($len_len == 2) {
            ($longs, $long) = ( 0, unpack('n', $len_buf) );
        }
        else {
            ($longs, $long) = ( unpack('NN', $len_buf) );
        }
    }
    else {
        ($longs, $long) = ( 0, $len );
    }

    my $mask_buf;
    if ($mask_size) {
        $mask_buf = $self->_read_with_buffer($mask_size) or do {
            substr( $self->{'_buffer'}, 0, 0, $first2 . $len_buf );
            return undef;
        };
    }
    else {
        $mask_buf = q<>;
    }

    my $payload = q<>;

    for ( 1 .. $longs ) {
syswrite( \*STDERR, "long" . length($self->{'_buffer'}) . "\n" );

        #32-bit systems don’t know what 2**32 is.
        #MacOS, at least, also chokes on 2**31 (Is their size_t signed??),
        #even on 64-bit.
        for ( 1 .. 4 ) {
            $self->_append_chunk( 2**30, \$payload ) or do {
                substr( $self->{'_buffer'}, 0, 0, $first2 . $len_buf . $mask_buf . $payload );
                return undef;
            };
        }
    }

    if ($long) {
        $self->_append_chunk( $long, \$payload ) or do {
            substr( $self->{'_buffer'}, 0, 0, $first2 . $len_buf . $mask_buf . $payload );
            return undef;
        };
    }

    $self->{'_buffer'} = q<>;

    return Net::WebSocket::Frame::create_from_parse(\$first2, \$len_len, \$mask_buf, \$payload);
}

sub has_partial_frame {
    my ($self) = @_;

    return length($self->{'_buffer'}) ? 1 : 0;
}

#This will only return exactly the number of bytes requested.
#If fewer than we want are available, then we return undef.
sub _read_with_buffer {
    my ($self, $length) = @_;

    #Prioritize the case where we read everything we need.

    if ( length($self->{'_buffer'}) < $length ) {
        my $deficit = $length - length($self->{'_buffer'});
        my $read = $self->_read($deficit);

        if (length($read) < $deficit) {
            $self->{'_buffer'} .= $read;
            return undef;
        }

        return substr($self->{'_buffer'}, 0, length($self->{'_buffer'}), q<>) . $read;
    }

    return substr( $self->{'_buffer'}, 0, $length, q<> );
}

sub _append_chunk {
    my ($self, $length, $buf_sr) = @_;

    my $start_buf_len = length $$buf_sr;

    my $cur_buf;

    while (1) {
        my $read_so_far = length($$buf_sr) - $start_buf_len;

        $cur_buf = $self->_read_with_buffer($length - $read_so_far);
        return undef if !defined $cur_buf;

        $$buf_sr .= $cur_buf;

        last if (length($$buf_sr) - $start_buf_len) >= $length;
    }

    return 1;
}

1;
