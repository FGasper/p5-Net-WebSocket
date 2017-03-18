package Net::WebSocket::Endpoint;

=encoding utf-8

=head1 NAME

Net::WebSocket::Endpoint

=head1 DESCRIPTION

See L<Net::WebSocket::Endpoint::Server>.

=cut

use strict;
use warnings;

use Net::WebSocket::Message ();
use Net::WebSocket::X ();

use constant DEFAULT_MAX_PINGS => 2;

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !length $opts{$_} } qw( parser out );
    #die "Missing: [@missing]" if @missing;

    my $self = {
        _ping_counter => 0,
        _max_pings => DEFAULT_MAX_PINGS,
        (map { ( "_$_" => $opts{$_} ) } qw(
            parser
            out
            max_pings

            on_data_frame
            before_send_control_frame
        )),
    };

    return bless $self, $class;
}

sub get_next_message {
    my ($self) = @_;

    die "Already closed!" if $self->{'_closed'};

    if ( my $frame = $self->{'_parser'}->get_next_frame() ) {
        if ($frame->is_control_frame()) {
            $self->_handle_control_frame($frame);
        }
        else {
            if ($self->{'_on_data_frame'}) {
                $self->{'_on_data_frame'}->($frame);
            }

            if (!$frame->get_fin()) {
                push @{ $self->{'_fragments'} }, $frame;
            }
            else {
                return Net::WebSocket::Message::create_from_frames(
                    splice( @{ $self->{'_fragments'} } ),
                    $frame,
                );
            }
        }
    }

    return undef;
}

sub timeout {
    my ($self) = @_;

    if ($self->{'_ping_counter'} == $self->{'_max_pings'}) {
        my $close = $self->create_close('POLICY_VIOLATION');
        print { $self->{'_out'} } $close->to_bytes();
        $self->{'_closed'} = 1;
    }

    my $ping_message = sprintf("%s UTC: $self->{'_ping_counter'} (%s)", scalar(gmtime), rand);

    $self->{'_ping_texts'}{$ping_message} = 1;

    my $ping = $self->_SERIALIZER()->create_ping(
        payload_sr => \$ping_message,
    );
    print { $self->{'_out'} } $ping->to_bytes();

    $self->{'_ping_counter'}++;

    return;
}

sub is_closed {
    my ($self) = @_;
    return $self->{'_closed'} ? 1 : 0;
}

#----------------------------------------------------------------------

sub on_ping {
    my ($self, $frame) = @_;

    $self->_send_frame(
        $self->_SERIALIZER()->create_pong(
            $frame->get_payload(),
        ),
    );

    return;
}

sub on_pong {
    my ($self, $frame) = @_;

    #NB: We expect a response to any ping that we’ve sent; any pong
    #we receive that doesn’t actually correlate to a ping we’ve sent
    #is ignored—i.e., it doesn’t reset the ping counter. This means that
    #we could still timeout even if we’re receiving pongs.
    if (delete $self->{'_ping_texts'}{$frame->get_payload()}) {
        $self->{'_ping_counter'} = 0;
    }

    return;
}

#----------------------------------------------------------------------

sub _handle_control_frame {
    my ($self, $frame) = @_;

    my ($resp_frame, $error, $ignore_sigpipe);

    my $type = $frame->get_type();

    if ($type eq 'close') {
        $self->{'_closed'} = 1;

        $resp_frame = $self->_SERIALIZER()->create_close(
            $frame->get_code_and_reason(),
        );

        local $SIG{'PIPE'} = 'IGNORE';

        $self->_send_frame($resp_frame);

        die Net::WebSocket::X->create('ReceivedClose', $frame);
    }
    elsif ( my $handler_cr = $self->can("on_$type") ) {
        $handler_cr->( $self, $frame );
    }
    else {
        my $ref = ref $self;
        die Net::WebSocket::X->create(
            'ReceivedBadControlFrame',
            "“$ref” cannot handle a control frame of type “$type”",
        );
    }

    return;
}

sub _send_frame {
    my ($self, $frame) = @_;

    if ($self->can('_before_send_frame')) {
        $self->_before_send_frame($frame);
    }

    print { $self->{'_out'} } $frame->to_bytes();

    return;
}

1;
