package Net::WebSocket::ReadFilehandle;

use strict;
use warnings;

use Net::WebSocket::X ();

sub new {
    my ($class, $fh, $start_buf) = @_;

    die "Need filehandle!" if !UNIVERSAL::isa($fh, 'GLOB');

    if (!length $start_buf) {
        $start_buf = q<>;
    }

    return bless { _fh => $fh, _start_buf => $start_buf }, $class;
}

sub _read {
    my ($self, $len) = @_;

    die "Useless zero read!" if $len == 0;

    my $buf = q<>;

    if (length $self->{'_start_buf'}) {
        if ($len < length $self->{'_start_buf'}) {
            substr(
                $buf, 0, 0,
                substr( $self->{'_start_buf'}, 0, $len, q<> ),
            );

            return $buf;
        }
        else {
            substr(
                $buf, 0, 0,
                substr( $self->{'_start_buf'}, 0, length($self->{'_start_buf'}), q<> ),
            );

            $len -= length($self->{'_start_buf'});
        }
    }

    local $!;

    sysread( $self->{'_fh'}, $buf, $len, length $buf ) or do {
        die Net::WebSocket::X->create('ReadFilehandle', $!) if $!;
    };

    return $buf;
}

1;
