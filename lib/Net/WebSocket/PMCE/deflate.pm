package Net::WebSocket::PMCE::deflate;

#----------------------------------------------------------------------
# PMCEs work only at the level of the *message*. (6.1 & 6.2) Fragmentation
# happens within the confines of the PMCE; however, permessage-deflate
# also describes:
#
#   Even when only part of the payload is available, a fragment can be
#   built by compressing the available data and choosing the block type
#   appropriately so that the end of the resulting compressed data is
#   aligned at a byte boundary.  Note that for non-final fragments, the
#   removal of 0x00 0x00 0xff 0xff MUST NOT be done. (7.2.1)
#
# So, we have two workflows:
#
#   1) Take a message payload and construct a compressed message.
#
#   2) Take a message fragment and build a frame for it, distinguishing
#      between final and non-final fragments.
#
# For #2 we should *always* preserve a sliding window until the final
# fragment, as the spec mandates assembly of the entire message payload
# prior to decompression.
#
#----------------------------------------------------------------------
# The original idea here was to apply DEFLATE to frames and messages
# that are already assembled. Probably a better approach is to subclass
# the text, binary, and continuation frame objects to apply DEFLATE
# right away.
#
# The reason for this is that the RFC appears to assume that we
# assemble frames with an awareness of the compression.
#
# Note in particular that (7.2.1):
# for non-final fragments, the removal of 0x00 0x00 0xff 0xff MUST NOT be done
#
# In fact, the DEFLATE is apparently meant only to apply to creation of a
# *message*. That’s potentially useful: maybe a factory?
#
# Need to learn more about how DEFLATE works before working more on this.
# And/or, look at other implementations. For example, how do they handle
# fragmentation? Something like:
#
# $deflate->compress(
#
# my $msg_iter = $deflate->start_message(
#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Net::WebSocket::PMCE::deflate - WebSocket’s C<permessage-deflate> extension

=head1 SYNOPSIS

    use Net::WebSocket::PMCE::deflate ();

    my $deflate = Net::WebSocket::PMCE::deflate->new( ... );

    my $decompressed = $pmce->inflate($payload);

    #NB: a static function!
    Net::WebSocket::PMCE::deflate::validate_max_window_bits($bits);

=head1 DESCRIPTION

This class implements C<permessage-deflate> as defined in
L<RFC 7692|https://tools.ietf.org/html/rfc7692>.

If you want a base class to use to implement other per-message compress
extensions (PMCEs), look at L<Net::WebSocket::PMCE>.

=head1 STATUS

This module is an ALPHA release. Changes to the API are not unlikely;
be sure to check the changelog before updating, and please report any
issues you find.

=head1 STATIC FUNCTIONS

=cut

use strict;
use warnings;

use parent 'Net::WebSocket::PMCE';

use Call::Context ();
use Module::Load ();

use Net::WebSocket::X ();

my $zlib_is_loaded;

my @VALID_MAX_WINDOW_BITS = qw( 8 9 10 11 12 13 14 15 );

use constant {
    TOKEN => 'permessage-deflate',

    _ZLIB_SYNC_TAIL => "\0\0\xff\xff",
    _DEBUG => 0,
};

=head2 validate_max_window_bits( BITS )

This validates a value given in either the C<server_max_window_bits>
or C<client_max_window_bits> handshake parameters. This function considers an
undefined value to be an error, so you need to check
whether C<client_max_window_bits> was given with a value or not.

=cut

sub validate_max_window_bits {
    my ($bits) = @_;

    if (defined $bits) {
        return if grep { $_ eq $bits } @VALID_MAX_WINDOW_BITS;

        die Net::WebSocket::X->create( 'BadArg', "Must be one of: [@VALID_MAX_WINDOW_BITS]" );
    }

    die Net::WebSocket::X->create( 'BadArg', "Must have a value, one of: [@VALID_MAX_WINDOW_BITS]" );
}

=head1 METHODS

This class inherits all methods from L<Net::WebSocket::PMCE> and adds
a few more:

=head2 I<CLASS>->new( %OPTS )

Returns a new instance of this class.

C<%OPTS> is:

=over

=item C<deflate_max_window_bits> - optional; the number of window bits to use
for compressing messages. This should correspond with local endpoint’s
behavior; i.e., for a server, this should match the C<server_max_window_bits>
extension parameter in the WebSocket handshake.

=item C<inflate_max_window_bits> - optional; the number of window bits to use
for decompressing messages. This should correspond with remote peer’s
behavior; i.e., for a server, this should match the C<client_max_window_bits>
extension parameter in the WebSocket handshake.

=item C<local_no_context_takeover> - corresponds to either the
C<client_no_context_takeover> or C<server_no_context_takeover> parameter,
to match the local endpoint’s role. When this flag is set, the object
will do a full flush at the end of each C<compress_frame()> or
C<compress_message()> call. (It is thus advantageous to favor
C<compress_message()> when this flag is active.)

=back

=cut

sub new {
    my ($class, %opts) = @_;

    return bless \%opts, $class;
}

sub local_no_context_takeover {
    return $_[0]{'local_no_context_takeover'};
}

=head2 $decompressed = I<OBJ>->decompress( COMPRESSED_PAYLOAD )

Decompresses the given string and returns the result.

B<NOTE:> This function alters COMPRESSED_PAYLOAD.

=cut

#cf. RFC 7692, 7.2.2
sub decompress {
    my ($self) = @_;    #$_[1] = payload

    $self->{'i'} ||= $self->_create_inflate_obj();

    _debug(sprintf "inflating: %v.02x\n", $_[1]) if _DEBUG;

    $_[1] .= _ZLIB_SYNC_TAIL;

    my $status = $self->{'i'}->inflate($_[1], my $v);
    die $status if $status != Compress::Raw::Zlib::Z_OK();

    _debug(sprintf "inflate output: [%v.02x]\n", $v) if _DEBUG;

    return $v;
}

#----------------------------------------------------------------------

#Used by subclasses
sub _consume_header_parts {
    my ($self, $extensions_ar, $foreach_cr) = @_;

    my $use_ext;

    for my $ext_ar (@$extensions_ar) {
        next if $ext_ar->[0] ne TOKEN();
        $use_ext = 1;

        my %opts = @{$ext_ar}[ 1 .. $#$ext_ar ];

        $foreach_cr->(\%opts);

        if (%opts) {
            my @list = %opts;
            warn "Unrecognized: @list";
        }
    }

    return $use_ext;
}

#----------------------------------------------------------------------

my $_payload_sr;

#cf. RFC 7692, 7.2.1
sub compress_sync_flush {
    _load_zlib_if_needed();

    return $_[0]->_compress( $_[1], Compress::Raw::Zlib::Z_SYNC_FLUSH() );
}

sub compress_sync_flush_chomp {
    _load_zlib_if_needed();

    return _chomp_0000ffff_or_die( $_[0]->_compress( $_[1], Compress::Raw::Zlib::Z_SYNC_FLUSH() ) );
}

sub compress_full_flush_chomp {
    _load_zlib_if_needed();

    return _chomp_0000ffff_or_die( $_[0]->_compress( $_[1], Compress::Raw::Zlib::Z_FULL_FLUSH() ) );
}

sub _chomp_0000ffff_or_die {
    if ( substr($_[0], -4) eq _ZLIB_SYNC_TAIL ) {
        substr($_[0], -4) = q<>;
    }
    else {
        die sprintf('deflate/flush didn’t end with expected SYNC tail (00.00.ff.ff): %v.02x', $_[0]);
    }

    return $_[0];
}

sub _compress {
    my ($self) = @_;

    $_payload_sr = \$_[1];

    $self->{'d'} ||= $self->_create_deflate_obj();

    _debug(sprintf "to deflate: [%v.02x]", $$_payload_sr) if _DEBUG;

    my $out;

    my $dstatus = $self->{'d'}->deflate( $$_payload_sr, $out );
    die "deflate: $dstatus" if $dstatus != Compress::Raw::Zlib::Z_OK();

    _debug(sprintf "post-deflate output: [%v.02x]", $out) if _DEBUG;

    $dstatus = $self->{'d'}->flush($out, $_[2]);
    die "deflate flush: $dstatus" if $dstatus != Compress::Raw::Zlib::Z_OK();

    _debug(sprintf "post-flush output: [%v.02x]", $out) if _DEBUG;

    #NB: The RFC directs at this point that:
    #
    #If the resulting data does not end with an empty DEFLATE block
    #with no compression (the "BTYPE" bits are set to 00), append an
    #empty DEFLATE block with no compression to the tail end.
    #
    #… but I don’t know the protocol well enough to detect that??
    #
    #NB:
    #> perl -MCompress::Raw::Zlib -e' my $deflate = Compress::Raw::Zlib::Deflate->new( -WindowBits => -8, -AppendOutput => 1, -Level => Compress::Raw::Zlib::Z_NO_COMPRESSION ); $deflate->deflate( "", my $out ); $deflate->flush( $out, Compress::Raw::Zlib::Z_SYNC_FLUSH()); print $out' | xxd
    #00000000: 0000 00ff ff                             .....

#    if ( $_[2] == Compress::Raw::Zlib::Z_FULL_FLUSH() ) {
#        if ( substr($out, -4) eq _ZLIB_SYNC_TAIL ) {
#            substr($out, -4) = q<>;
#        }
#        else {
#            die sprintf('deflate/flush didn’t end with expected SYNC tail (00.00.ff.ff): %v.02x', $out);
#        }
#    }

    return $out;
}

#----------------------------------------------------------------------

sub _load_zlib_if_needed {
    $zlib_is_loaded ||= do {
        Module::Load::load('Compress::Raw::Zlib');
        1;
    };

    return;
}

sub _create_inflate_obj {
    my ($self) = @_;

    my $window_bits = $self->{'inflate_max_window_bits'} || $VALID_MAX_WINDOW_BITS[-1];

    my ($inflate, $istatus) = Compress::Raw::Zlib::Inflate->new(
        -WindowBits => -$window_bits,
        -AppendOutput => 1,
    );
    die "Inflate: $istatus" if $istatus != Compress::Raw::Zlib::Z_OK();

    return $inflate;
}

sub _create_deflate_obj {
    my ($self) = @_;

    my $window_bits = $self->{'deflate_max_window_bits'} || $VALID_MAX_WINDOW_BITS[-1];

    my ($deflate, $dstatus) = Compress::Raw::Zlib::Deflate->new(
        -WindowBits => -$window_bits,
        -AppendOutput => 1,
    );
    die "Deflate: $dstatus" if $dstatus != Compress::Raw::Zlib::Z_OK();

    return $deflate;
}

sub _debug {
    print STDERR "$_[0]$/";
}

1;

=head1 REPOSITORY

L<https://github.com/FGasper/p5-Net-WebSocket>

=head1 AUTHOR

Felipe Gasper (FELIPE)

=head1 COPYRIGHT

Copyright 2017 by L<Gasper Software Consulting, LLC|http://gaspersoftware.com>

=head1 LICENSE

This distribution is released under the same license as Perl.

=cut

__END__

Context takeover: technique for compressing/sending
increases amount of memory needed to decompress

server_no_context_takeover
    - “Don’t you use context takeover, Mr. Server!!”
    - “I swear I will not use context takeover, Mr. Client.”
    - if client sends, server must send back
    - if client doesn’t send, server *can* send back
    - server *should* support feature

client_no_context_takeover
    - “BTW, Mr. Server, I won’t use context takeover.”
    - “Don’t you use context takeover, Mr. Client!!”
    - if server sends, client MUST observe/support

server_max_window_bits = [8 .. 15]
    - “Don’t you use more bits than N for sliding window size, Mr. Server!”
    - “I swear I will not use more than N bits.”
    - (15 is the max/default anyway)
    - server responds with <= value

client_max_window_bits = empty | [8 .. 15]
    - server MUST NOT send if client didn’t
    - if empty, that just indicates support for the option

1;
