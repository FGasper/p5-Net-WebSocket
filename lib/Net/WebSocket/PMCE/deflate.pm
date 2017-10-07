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

use Carp::Always;

use Call::Context ();
use Module::Load ();

use Net::WebSocket::Handshake::Extension ();
use Net::WebSocket::X ();

use constant {
    token => 'permessage-deflate',
};

use constant VALID_MAX_WINDOW_BITS => qw( 8 9 10 11 12 13 14 15 );

#=head2 validate_max_window_bits( BITS )
#
#This validates a value given in either the C<server_max_window_bits>
#or C<client_max_window_bits> handshake parameters. This function considers an
#undefined value to be an error, so you need to check
#whether C<client_max_window_bits> was given with a value or not.
#
#=cut
#
#sub validate_max_window_bits {
#    my ($bits) = @_;
#
#    if (defined $bits) {
#        return if grep { $_ eq $bits } @VALID_MAX_WINDOW_BITS;
#
#        die Net::WebSocket::X->create( 'BadArg', "Must be one of: [@VALID_MAX_WINDOW_BITS]" );
#    }
#
#    die Net::WebSocket::X->create( 'BadArg', "Must have a value, one of: [@VALID_MAX_WINDOW_BITS]" );
#}

=head1 METHODS

This class inherits all methods from L<Net::WebSocket::PMCE> and adds
a few more:

=head2 I<CLASS>->new( %OPTS )

Returns a new instance of this class.

C<%OPTS> is:

=over

=item C<deflate_max_window_bits> - optional; the number of window bits to use
for compressing messages.

=item C<inflate_max_window_bits> - optional; the number of window bits to use
for decompressing messages.

=item C<local_no_context_takeover> - boolean; when this flag is set, the Data
object will do a full flush at the end of each C<compress()> call.

=item C<peer_no_context_takeover> - boolean; whether to ask the peer not to
use context takeover when it compresses messages.

=back

=cut

sub new {
    my ($class, %opts) = @_;

    my @errs = $class->_get_parameter_errors(%opts);
    die "@errs" if @errs;

    return bless \%opts, $class;
}

sub deflate_max_window_bits {
    my ($self) = @_;

    return $self->{'deflate_max_window_bits'} || ( $self->VALID_MAX_WINDOW_BITS() )[-1];
}

sub inflate_max_window_bits {
    my ($self) = @_;

    return $self->{'inflate_max_window_bits'} || ( $self->VALID_MAX_WINDOW_BITS() )[-1];
}

sub local_no_context_takeover {
    my ($self) = @_;

    return !!$self->{'local_no_context_takeover'};
}

sub peer_no_context_takeover {
    my ($self) = @_;

    return !!$self->{'peer_no_context_takeover'};
}

#Convenience
sub create_data_object {
    my ($self) = @_;

    #TODO: rename classes
    my $class = __PACKAGE__ . '::Data::' . $self->_ENDPOINT_CLASS();
    Module::Load::load($class);

    return $class->new( %$self );
}

sub get_handshake_object {
    my ($self) = @_;

    return Net::WebSocket::Handshake::Extension->new(
        $self->_create_header(),
    );
}

#----------------------------------------------------------------------

sub _create_header {
    my ($self) = @_;

    Call::Context::must_be_list();

    my @parts = $self->token();

    if (exists $self->{'deflate_max_window_bits'}) {
        push @parts, $self->{_DEFLATE_MAX_WINDOW_BITS_PARAM()} => $self->{'deflate_max_window_bits'};
    }

    if (exists $self->{'inflate_max_window_bits'}) {
        push @parts, $self->{_INFLATE_MAX_WINDOW_BITS_PARAM()} => $self->{'inflate_max_window_bits'};
    }

    if ($self->{'local_no_context_takeover'}) {
        push @parts, $self->{_LOCAL_NO_CONTEXT_TAKEOVER_PARAM()} => undef;
    }
    if ($self->{'peer_no_context_takeover'}) {
        push @parts, $self->{_PEER_NO_CONTEXT_TAKEOVER_PARAM()} => undef;
    }

    return @parts;
}


=head2 I<OBJ>->consume_peer_extensions( EXTENSIONS )

Alters the given object as per the peer’s request. Ordinarily
this should be fine, but if for some reason you want to reject the peer’s
requested options you can inspect the object after this.

The alterations made in response to the different extension
options are:

=over

=item * Client

=over

=item * <client_no_context_takeover> - Sets the object’s
C<local_no_context_takeover> flag.

=item * <server_no_context_takeover> - If the object’s
C<peer_no_context_takeover> flag is set, and if
we do *not* receive this flag from the peer, then we C<die()>.
This option is ignored otherwise.

=item * <client_max_window_bits> - If given and less than the object’s
C<deflate_max_window_bits> option, then that option is reduced to the
new value.

=item * <server_max_window_bits> - If given and less than the object’s
C<inflate_max_window_bits> option, then that option is reduced to the
new value. If given and B<greater> than the object’s
C<inflate_max_window_bits> option, then we C<die()>.

=back

=item * Server

=over

=item * <client_no_context_takeover> - Sets the object’s
C<peer_no_context_takeover> flag.

=item * <server_no_context_takeover> - Sets the object’s
C<local_no_context_takeover> flag.

=item * <client_max_window_bits> - If given and less than the object’s
C<inflate_max_window_bits> option, then that option is reduced to the
new value.

=item * <server_max_window_bits> - If given and less than the object’s
C<deflate_max_window_bits> option, then that option is reduced to the
new value.

=back

=back

=cut

sub consume_peer_extensions {
    my ($self, @extensions) = @_;

    for my $ext (@extensions) {
        next if $ext->token() ne $self->token();

        my %opts = $ext->parameters();

        $self->_consume_extension_options(\%opts);

        if (%opts) {
            my ($token, @params) = ($ext->token(), %opts);
            die "Unrecognized for “$token”: @params";
        }

        $self->{'_use_ok'}++;
    }

    return $self->{'_use_ok'};
}

# 7. .. A server MUST decline an extension negotiation offer for this
# extension if any of the following conditions are met:
sub _get_parameter_errors {
    my ($class, @params_kv) = @_;

    my %params;

    my @errors;

    while ( my ($k, $v) = splice( @params_kv, 0, 2 ) ) {

        #The negotiation (offer/response) contains multiple extension
        #parameters with the same name.
        if ( exists $params{$k} ) {
            if (defined $v) {
                push @errors, "Duplicate parameter /$k/ ($v)";
            }
            else {
                push @errors, "Duplicate parameter /$k/, no value";
            }
        }

        #The negotiation (offer/response) contains an extension parameter
        #with an invalid value.
        if ( my $cr = $class->can("_validate_$k") ) {
            push @errors, $cr->($class, $v);
        }

        #The negotiation (offer/response) contains an extension parameter
        #not defined for use in an (offer/response).
        else {
            if (defined $v) {
                push @errors, "Unknown parameter /$k/ ($v)";
            }
            else {
                push @errors, "Unknown parameter /$k/, no value";
            }
        }
    }

    return @errors;
}

#Define these as no-ops because all we care about is their truthiness.
use constant _validate_local_no_context_takeover => ();
use constant _validate_peer_no_context_takeover => ();

sub _validate_deflate_max_window_bits {
    return $_[0]->__validate_max_window_bits( 'deflate', $_[1] );
}

sub _validate_inflate_max_window_bits {
    return $_[0]->__validate_max_window_bits( 'inflate', $_[1] );
}

sub __validate_no_context_takeover {
    my ($self, $endpoint, $value) = @_;

    if (defined $value) {
        return "/${endpoint}_no_context_takeover/ must not have a value.";
    }

    return;
}

sub __validate_max_window_bits {
    my ($self, $ept, $bits) = @_;

    my @VALID_MAX_WINDOW_BITS = VALID_MAX_WINDOW_BITS();

    if (defined $bits) {
        return if grep { $_ eq $bits } @VALID_MAX_WINDOW_BITS;
    }

    return Net::WebSocket::X->create( 'BadArg', "${ept}_max_window_bits" => $bits, "Must be one of: [@VALID_MAX_WINDOW_BITS]" );
}

#----------------------------------------------------------------------

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
    - “Don’t you use more than N bits for sliding window size, Mr. Server!”
    - “I swear I will not use more than N bits.”
    - (15 is the max/default anyway)
    - server responds with <= value

client_max_window_bits = empty | [8 .. 15]
    - server MUST NOT send if client didn’t
    - if empty, that just indicates support for the option

1;
