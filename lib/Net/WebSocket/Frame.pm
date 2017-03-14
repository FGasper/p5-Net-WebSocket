package Net::WebSocket::Frame;

use strict;
use warnings;

use Net::WebSocket::Constants ();
use Net::WebSocket::Mask ();
use Net::WebSocket::X ();

use constant {
    FIRST2 => 0,
    LEN_LEN => 1,
    MASK => 2,
    PAYLOAD => 3,
};

*OPCODE = *Net::WebSocket::Constants::OPCODE;

#fin, rsv, mask, payload_sr
#rsv is a bitmask of the three values, with most significant bit first.
#So, if RSV1 (4) and RSV2 (2) are on, then rsv is 4 + 2 = 6;
sub new {
    my ($class, %opts) = @_;

    my ( $fin, $rsv, $mask, $payload_sr ) = @opts{ qw( fin rsv mask payload_sr ) };

    my $type = $class->get_type();

    my $opcode = OPCODE()->{$type};

    if (!defined $fin) {
        $fin = 1;
    }

    $payload_sr ||= \do { my $v = q<> };

    if (defined $mask) {
        _validate_mask($mask);

        if (length $mask) {
            Net::WebSocket::Mask::apply($payload_sr, $mask);
        }
    }
    else {
        $mask = q<>;
    }

    my $first2 = chr $opcode;
    $first2 |= "\x80" if $fin;

    if ($rsv) {
        die "RSV must be < 0-7!" if $rsv > 7;
        $first2 |= chr( $rsv << 4 );
    }

    my ($byte2, $len_len) = $class->_assemble_length($payload_sr);

    $byte2 |= "\x80" if $mask;

    substr( $first2, 1, 0, $byte2 );

    return bless [ \$first2, \$len_len, \$mask, $payload_sr ], $class;
}

# All string refs: first2, length octets, mask octets, payload
#XXX TODO
sub create_from_parse {
    return bless \@_, __PACKAGE__;
}

sub get_mask_bytes {
    my ($self) = @_;

    return ${ $self->[MASK] };
}

#To collect the goods
sub get_payload {
    my ($self) = @_;

    my $pl = "" . ${ $self->[PAYLOAD] };

    if (my $mask = $self->get_mask_bytes()) {
        Net::WebSocket::Mask::apply( \$pl, $mask );
    }

    return $pl;
}

#For sending over the wire
sub to_bytes {
    my ($self) = @_;

    return join( q<>, map { $$_ } @$self );
}

sub get_rsv {
    my ($self) = @_;

    #0b01110000 = 0x70
    return( ord( ${ $self->[FIRST2] } & "\x70" ) >> 4 );
}

sub set_rsv {
    my ($self, $rsv) = @_;

    ${ $self->[FIRST2] } |= chr( $rsv << 4 );

    return $self;
}

#----------------------------------------------------------------------

#Unneeded?
#sub set_mask_bytes {
#    my ($self, $bytes) = @_;
#
#    if (!defined $bytes) {
#        die "Set either a 4-byte mask, or empty string!";
#    }
#
#    if (length $bytes) {
#        _validate_mask($bytes);
#
#        $self->_activate_highest_bit( $self->[FIRST2], 1 );
#    }
#    else {
#        $self->_deactivate_highest_bit( $self->[FIRST2], 1 );
#    }
#
#    if (${ $self->[MASK] }) {
#        Net::WebSocket::Mask::apply( $self->[PAYLOAD], ${ $self->[MASK] } );
#    }
#
#    $self->[MASK] = \$bytes;
#
#    if ($bytes) {
#        Net::WebSocket::Mask::apply( $self->[PAYLOAD], $bytes );
#    }
#
#    return $self;
#}

#----------------------------------------------------------------------

our $AUTOLOAD;
sub AUTOLOAD {
    my ($self) = shift;

    return if substr( $AUTOLOAD, -8 ) eq ':DESTROY';

    my $last_colon_idx = rindex( $AUTOLOAD, ':' );
    my $method = substr( $AUTOLOAD, 1 + $last_colon_idx );

    #Figure out what type this is, and re-bless.
    if (ref($self) eq __PACKAGE__) {
        my $opcode = $self->_get_opcode();
        my $type = Net::WebSocket::Constants::opcode_to_type($opcode);

        my $class = __PACKAGE__ . "::$type";
        if (!$class->can('new')) {
            Module::Load::load($class);
        }

        bless $self, $class;

        if ($self->can($method)) {
            return $self->$method(@_);
        }
    }

    my $class = (ref $self) || $self;

    die( "$class has no method “$method”!" );
}

#----------------------------------------------------------------------

sub _get_opcode {
    my ($self) = @_;

    return 0xf & ord substr( ${ $self->[FIRST2] }, 0, 1 );
}

sub _validate_mask {
    my ($bytes) = @_;

    if (length $bytes) {
        if (4 != length $bytes) {
            my $len = length $bytes;
            die "Mask must be 4 bytes long, not $len ($bytes)!";
        }
    }

    return;
}

sub _activate_highest_bit {
    my ($self, $sr, $offset) = @_;

    substr( $$sr, $offset, 1 ) = chr( 0x80 | ord substr( $$sr, $offset, 1 ) );

    return;
}

sub _deactivate_highest_bit {
    my ($sr, $offset) = @_;

    substr( $$sr, $offset, 1 ) = chr( 0x7f & ord substr( $$sr, $offset, 1 ) );

    return;
}

1;
