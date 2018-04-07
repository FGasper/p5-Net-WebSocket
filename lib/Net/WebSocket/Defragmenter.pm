package Net::WebSocket::Defragmenter;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Net::WebSocket::Defragmenter

=head1 SYNOPSIS

    my $defragger = Net::WebSocket::Defragmenter->new(
        parser => $parser_obj,  #i.e., isa Net::WebSocket::Parser

        #Optional; these two receive the Net::WebSocket::Frame object.
        on_control_frame => sub { ... },
        on_data_frame => sub { ... },

        #Optional; receives a type string and a human-readable message.
        #An exception is thrown after this callback runs.
        on_protocol_error => sub { ... },
    );

    my $msg_or_undef = $defragger->get_next_message();

=head1 DESCRIPTION

You ordinarily shouldn’t instantiate this class because
L<Net::WebSocket::Endpoint> already uses it.

This class implements WebSocket’s defragmentation logic.
It’s mostly meant for internal use but is documented for cases
where L<Net::WebSocket::Endpoint> may not be usable or desirable.

=cut

=head1 METHODS

=head2 I<CLASS>->new( %OPTS )

See SYNOPSIS above.

=cut

sub new {
    my ($class, %opts) = @_;

    my %self = (
        _fragments => [],

        ( map { ( "_$_" => $opts{$_} ) } (
            'parser',
            'on_control_frame',
            'on_data_frame',
            'on_protocol_error',
        ) ),
    );

    return bless \%self, $class;
}

=head2 I<OBJ>->get_next_message()

Reads a frame from C<parser>.

Returns a L<Net::WebSocket::Message> object if there is a message
ready to return; otherwise returns undef.

An exception (L<Net::WebSocket::X>) is thrown on fragmentation errors.

=cut

sub get_next_message {
    my ($self) = @_;

    my $_msg_frame;

    if ( $_msg_frame = $self->{'_parser'}->get_next_frame() ) {
        if ($_msg_frame->is_control()) {
            if ($self->{'_on_control_frame'}) {
                $self->{'_on_control_frame'}->($_msg_frame);
            }
        }
        else {
            if ($self->{'_on_data_frame'}) {
                $self->{'_on_data_frame'}->($_msg_frame);
            }

            #Failure cases:
            #   - continuation without prior fragment
            #   - non-continuation within fragment

            if ( $_msg_frame->get_type() eq 'continuation' ) {
                if ( !@{ $self->{'_fragments'} } ) {
                    $self->_on_protocol_error(
                        'ReceivedBadControlFrame',
                        sprintf('Received continuation outside of fragment!'),
                    );
                }
            }
            elsif ( @{ $self->{'_fragments'} } ) {
                $self->_on_protocol_error(
                    'ReceivedBadDataFrame',
                    sprintf('Received %s; expected continuation!', $_msg_frame->get_type())
                );
            }

            if ($_msg_frame->get_fin()) {
                return Net::WebSocket::Message->new(
                    splice( @{ $self->{'_fragments'} } ),
                    $_msg_frame,
                );
            }
            else {
                push @{ $self->{'_fragments'} }, $_msg_frame;
            }
        }

        $_msg_frame = undef;
    }

    return defined($_msg_frame) ? q<> : undef;
}

sub _on_protocol_error {
    my ($self, $type, $msg) = @_;

    if ( $self->{'_on_protocol_error'} ) {
        $self->{'_on_protocol_error'}->( $type, $msg );
    }

    die Net::WebSocket::X->create( $type, $msg );
}

1;
