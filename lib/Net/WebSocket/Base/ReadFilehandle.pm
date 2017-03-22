package Net::WebSocket::Base::ReadFilehandle;

use strict;
use warnings;

use Try::Tiny;

use Net::WebSocket::X ();

sub new {
    my ($class, $fh, $start_buf) = @_;

    die "Need filehandle!" if !UNIVERSAL::isa($fh, 'GLOB');

    if (!length $start_buf) {
        $start_buf = q<>;
    }

    #Determine if this is an OS-level filehandle;
    #if it is, then we read with sysread(); otherwise we use read().
    my $fileno = try { fileno $fh };
    undef $fileno if defined($fileno) && $fileno == -1;

    return bless {
        _fh => $fh,
        _start_buf => $start_buf,
        _is_io => defined $fileno,
    }, $class;
}

my $bytes_read;

sub _read {
    my ($self, $len) = @_;

    die "Useless zero read!" if $len == 0;

    my $buf = q<>;

    if (length $self->{'_start_buf'}) {
        if ($len < length $self->{'_start_buf'}) {
            return $buf . substr( $self->{'_start_buf'}, 0, $len, q<> );
        }
        else {
            $buf .= substr( $self->{'_start_buf'}, 0, length($self->{'_start_buf'}), q<> );

            $len -= length($self->{'_start_buf'});
        }
    }

    local $!;

    if ($self->{'_is_io'}) {
        {
            $bytes_read = sysread( $self->{'_fh'}, $buf, $len, length $buf );

            if ($!{'EINTR'}) {

                #“man 2 read” says EINTR means no bytes were read,
                #but let’s assume that could be wrong, just in case:
                $len -= $bytes_read;

                redo;
            }
        }

        if (!$bytes_read) {

            #If “_reading_frame” is set, then we’re in the middle of reading
            #a frame, in which context we don’t want to die() on EAGAIN because
            #we accept the risk of incomplete reads there in exchange for
            #speed and simplicity. (Most of the time a full frame should indeed
            #be ready anyway.)
            if (!$self->{'_reading_frame'} || !$!{'EAGAIN'}) {
                die Net::WebSocket::X->create('ReadFilehandle', $!) if $!;
            }
        }
    }
    else {
        $bytes_read = read( $self->{'_fh'}, $buf, $len, length $buf );
    }

    return $buf;
}

1;
