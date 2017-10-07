package Net::WebSocket::PMCE::deflate::Data;

use strict;
use warnings;

use Module::Load ();

use Net::WebSocket::Message ();
use Net::WebSocket::PMCE ();

use constant {
    INITIAL_FRAME_RSV => 0b100,  #RSV1
    _ZLIB_SYNC_TAIL => "\0\0\xff\xff",
    _DEBUG => 0,
};

=head2 I<CLASS>->new( %OPTS )

%OPTS is:

=over

=item C<deflate_max_window_bits> - optional; the number of window bits to use
for compressing messages. This should correspond with the local endpoint’s
behavior; i.e., for a server, this should match the C<server_max_window_bits>
extension parameter in the WebSocket handshake.

=item C<inflate_max_window_bits> - optional; the number of window bits to use
for decompressing messages. This should correspond with the remote peer’s
behavior; i.e., for a server, this should match the C<client_max_window_bits>
extension parameter in the WebSocket handshake.

=item C<local_no_context_takeover> - corresponds to either the
C<client_no_context_takeover> or C<server_no_context_takeover> parameter,
to match the local endpoint’s role. When this flag is set, the object
will do a full flush at the end of each C<compress()> call.

=back

=cut

sub new {
    my ($class, %opts) = @_;

    #Validate deflate_max_window_bits/inflate_max_window_bits?

    my $compress_func = '_compress_';
    $compress_func .= $opts{'local_no_context_takeover'} ? 'full' : 'sync';
    $compress_func .= '_flush_chomp';

    $opts{'final_frame_compress_func'} = $compress_func;

    return bless \%opts, $class;
}

*message_is_compressed = *Net::WebSocket::PMCE::message_is_compressed;

#----------------------------------------------------------------------

=head2 $msg = I<OBJ>->create_message( FRAME_CLASS, PAYLOAD )

Creates an unfragmented, compressed message. The message will be an
instance of the class that C<Net::WebSocket::Message::create_from_frames()>
would instantiate; e.g., if FRAME_CLASS is C<Net::WebSocket::Frame::text>,
the message will be of type C<Net::WebSocket::Message::text>.

=cut

sub create_message {
    my ($self, $frame_class) = @_;    #$_[2] = payload

    my $compress_func = $self->{'final_frame_compress_func'};

    my $payload_sr = \($self->$compress_func( $_[2] ));

    return Net::WebSocket::Message::create_from_frames(
        $frame_class->new(
            payload_sr => $payload_sr,
            rsv => $self->INITIAL_FRAME_RSV(),
            $self->FRAME_MASK_ARGS(),
        ),
    );
}

#----------------------------------------------------------------------

=head2 $msg = I<OBJ>->create_message( FRAME_CLASS )

Returns an instance of L<Net::WebSocket::PMCE::deflate::Streamer> based
on this object.

=cut

sub create_streamer {
    my ($self, $frame_class) = @_;

    Module::Load::load('Net::WebSocket::PMCE::deflate::Streamer');

    return Net::WebSocket::PMCE::deflate::Streamer->new($self, $frame_class);
}

#----------------------------------------------------------------------

=head2 $decompressed = I<OBJ>->decompress( COMPRESSED_PAYLOAD )

Decompresses the given string and returns the result.

B<NOTE:> This function alters COMPRESSED_PAYLOAD.

=cut

#cf. RFC 7692, 7.2.2
sub decompress {
    my ($self) = @_;    #$_[1] = payload

    $self->{'i'} ||= $self->_create_inflate_obj();

    _DEBUG && _debug(sprintf "inflating: %v.02x\n", $_[1]);

    $_[1] .= _ZLIB_SYNC_TAIL;

    my $status = $self->{'i'}->inflate($_[1], my $v);
    die $status if $status != Compress::Raw::Zlib::Z_OK();

    _DEBUG && _debug(sprintf "inflate output: [%v.02x]\n", $v);

    return $v;
}

#----------------------------------------------------------------------

my $_payload_sr;

#cf. RFC 7692, 7.2.1
#Use for fragments.
sub _compress_sync_flush {
    return $_[0]->_compress( $_[1], Compress::Raw::Zlib::Z_SYNC_FLUSH() );
}

#Preserves sliding window to the next message.
#Use for final fragments when !!local_context_takeover
sub _compress_sync_flush_chomp {
    return _chomp_0000ffff_or_die( $_[0]->_compress( $_[1], Compress::Raw::Zlib::Z_SYNC_FLUSH() ) );
}

#Flushes the sliding window.
#Use for final fragments when !local_context_takeover
sub _compress_full_flush_chomp {
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

    _DEBUG && _debug(sprintf "to deflate: [%v.02x]", $$_payload_sr);

    my $out;

    my $dstatus = $self->{'d'}->deflate( $$_payload_sr, $out );
    die "deflate: $dstatus" if $dstatus != Compress::Raw::Zlib::Z_OK();

    _DEBUG && _debug(sprintf "post-deflate output: [%v.02x]", $out);

    $dstatus = $self->{'d'}->flush($out, $_[2]);
    die "deflate flush: $dstatus" if $dstatus != Compress::Raw::Zlib::Z_OK();

    _DEBUG && _debug(sprintf "post-flush output: [%v.02x]", $out);

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

my $zlib_is_loaded;

sub _load_zlib_if_needed {
    $zlib_is_loaded ||= do {
        Module::Load::load('Compress::Raw::Zlib');
        1;
    };

    return;
}

sub _create_inflate_obj {
    my ($self) = @_;

    my $window_bits = $self->{'inflate_max_window_bits'} || 15; #XXX TODO

    _load_zlib_if_needed();

    my ($inflate, $istatus) = Compress::Raw::Zlib::Inflate->new(
        -WindowBits => -$window_bits,
        -AppendOutput => 1,
    );
    die "Inflate: $istatus" if $istatus != Compress::Raw::Zlib::Z_OK();

    return $inflate;
}

sub _create_deflate_obj {
    my ($self) = @_;

    my $window_bits = $self->{'deflate_max_window_bits'} || 15; #XXX TODO

    _load_zlib_if_needed();

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
