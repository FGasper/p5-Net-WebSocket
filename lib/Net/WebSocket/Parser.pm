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

    my $buffer = q<>;

    my $first2 = $self->_read_with_buffer(0, 2) or return undef;

    my $oct2 = unpack('xC', $first2 );

    my $len = $oct2 & 0x7f;

    my $mask_size = ($oct2 & 0x80) && 4;

    my $len_len = ($len == 126) ? 2 : ($len == 127) ? 8 : 0;

    my ($longs, $long);

    if ($len_len) {
        my $len_buf = $self->_read_with_buffer(2, $len_len) or return undef;

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

    my $mask_buf = $mask_size ? ($self->_read_with_buffer(2 + $len_len, $mask_size) || return undef) : q<>;

    my $payload = q<>;

    my $pos = 2 + $len_len + $mask_size;

    for ( 1 .. $longs ) {
        $self->_append_chunk( \$pos, 2**31, \$payload ) or return undef;
        $self->_append_chunk( \$pos, 2**31, \$payload ) or return undef;
    }

    if ($long) {
        $self->_append_chunk( \$pos, $long, \$payload ) or return undef;
    }

    $self->{'_buffer'} = q<>;

    return Net::WebSocket::Frame::create_from_parse(\$first2, \$len_len, \$mask_buf, \$payload);
}

#This will only return exactly the number of bytes requested.
#If fewer than we want are available, then we return undef.
sub _read_with_buffer {
    my ($self, $buffer_start, $length) = @_;

    my $return;

    #Buffer has nothing to help us
    if (length $self->{'_buffer'} <= $buffer_start) {
        $return = $self->_read($length);

        if (length($return) < $length) {
            if (length $return) {
                substr( $self->{'_buffer'}, $buffer_start ) = $return;
            }

            return undef;
        }
    }

    #Buffer has something
    else {
        $return = substr( $self->{'_buffer'}, $buffer_start, $length );

        #Buffer has only some things we need
        if (length($return) < $length) {
            my $deficit = $buffer_start + $length - length($self->{'_buffer'});
            my $read = $self->_read($deficit);

            if (length($read) < $deficit) {
                $self->{'_buffer'} .= $read;
                return undef;
            }

            $return .= $read;
        }
    }

    return $return;
}

sub _append_chunk {
    my ($self, $pos_sr, $length, $buf_sr) = @_;

    my $start_buf_len = length $$buf_sr;

    my $cur_buf;

    while (1) {
        my $read_so_far = length($$buf_sr) - $start_buf_len;

        $cur_buf = $self->_read_with_buffer($$pos_sr, $length - $read_so_far);
        return undef if !length $cur_buf;

        $$buf_sr .= $cur_buf;

        last if (length($$buf_sr) - $start_buf_len) >= $length;
    }

    $$pos_sr += $length;

    return 1;
}

1;
