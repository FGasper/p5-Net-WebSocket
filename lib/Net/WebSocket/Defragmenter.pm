package Net::WebSocket::Defragmenter;

use strict;
use warnings;

# This class isn’t meant for public consumption (yet).

sub new {
    my ($class, %opts) = @_;

    my %self = (
        _fragments => [],

        _parser => $opts{'parser'},

        ( map { ( "_$_" => $opts{$_} ) } (
            'parser',
            'on_control_frame',
            'on_data_frame',
            'on_protocol_error',
        ) ),
    );

    return bless \%self, $class;
}

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
