package Net::WebSocket::Endpoint;

=encoding utf-8

=head1 NAME

Net::WebSocket::Endpoint

=head1 DESCRIPTION

See L<Net::WebSocket::Endpoint::Server>.

=cut

use strict;
use warnings;

use Module::Runtime ();

use Net::WebSocket::Defragmenter ();
use Net::WebSocket::Frame::close ();
use Net::WebSocket::Frame::ping ();
use Net::WebSocket::Frame::pong ();
use Net::WebSocket::Message ();
use Net::WebSocket::PingStore ();
use Net::WebSocket::X ();

use constant DEFAULT_MAX_PINGS => 3;

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !length $opts{$_} } qw( out parser );

    die "Missing: [@missing]" if @missing;

    if ( !(ref $opts{'out'})->can('write') ) {
        die "“out” ($opts{'out'}) needs a write() method!";
    }

    my $self;

    my $defragger = Net::WebSocket::Defragmenter->new(
        parser => $opts{'parser'},

        on_data_frame => $opts{'on_data_frame'},

        on_control_frame => sub {
            $self->_handle_control_frame(shift);
        },

        on_protocol_error => sub {
            ( undef, my $msg ) = @_;

            #For now … there may be some multiplexing extension
            #that allows some other behavior down the line,
            #but let’s enforce standard protocol for now.
            my $err_frame = Net::WebSocket::Frame::close->new(
                code => 'PROTOCOL_ERROR',
                reason => $msg,
                $self->FRAME_MASK_ARGS(),
            );

            $self->_write_frame($err_frame);
        },
    );

    $self = {
        _max_pings => $class->DEFAULT_MAX_PINGS(),

        _ping_store => Net::WebSocket::PingStore->new(),

        _defragger => $defragger,

        (map { defined($opts{$_}) ? ( "_$_" => $opts{$_} ) : () } qw(
            max_pings

            on_data_frame

            out
        )),
    };

    return bless $self, $class;
}

sub get_next_message {
    my ($self) = @_;

    $self->_verify_not_closed();

    return $self->{'_defragger'}->get_next_message();
}

sub create_message {
    my ($self, $frame_type, $payload) = @_;

    require Net::WebSocket::FrameTypeName;

    my $frame_class = Net::WebSocket::FrameTypeName::get_module($frame_type);
    Module::Runtime::require_module($frame_class) if !$frame_class->can('new');

    return Net::WebSocket::Message->new(
        $frame_class->new(
            payload => $payload,
            $self->FRAME_MASK_ARGS(),
        ),
    );
}

sub check_heartbeat {
    my ($self) = @_;

    my $ping_counter = $self->{'_ping_store'}->get_count();

    if ($ping_counter == $self->{'_max_pings'}) {
        $self->close(
            code => 'POLICY_VIOLATION',
            reason => "Unanswered ping(s): $ping_counter",
        );
    }
    else {
        my $ping_message = $self->{'_ping_store'}->add();

        my $ping = Net::WebSocket::Frame::ping->new(
            payload => $ping_message,
            $self->FRAME_MASK_ARGS(),
        );

        $self->_write_frame($ping);
    }

    return;
}

sub close {
    my ($self, %opts) = @_;

    my $close = Net::WebSocket::Frame::close->new(
        $self->FRAME_MASK_ARGS(),
        code => $opts{'code'} || 'ENDPOINT_UNAVAILABLE',
        reason => $opts{'reason'},
    );

    return $self->_close_with_frame($close);
}

sub _close_with_frame {
    my ($self, $close_frame) = @_;

    $self->_write_frame($close_frame);

    $self->{'_sent_close_frame'} = $close_frame;

    return $self;
}

*shutdown = *close;

sub is_closed {
    my ($self) = @_;
    return $self->{'_sent_close_frame'} ? 1 : 0;
}

sub received_close_frame {
    my ($self) = @_;
    return $self->{'_received_close_frame'};
}

sub sent_close_frame {
    my ($self) = @_;
    return $self->{'_sent_close_frame'};
}

sub die_on_close {
    my ($self) = @_;

    $self->{'_no_die_on_close'} = 0;

    return;
}

sub do_not_die_on_close {
    my ($self) = @_;

    $self->{'_no_die_on_close'} = 1;

    return;
}

#----------------------------------------------------------------------

sub on_ping {
    my ($self, $frame) = @_;

    $self->_write_frame(
        Net::WebSocket::Frame::pong->new(
            payload => $frame->get_payload(),
            $self->FRAME_MASK_ARGS(),
        ),
    );

    return;
}

sub on_pong {
    my ($self, $frame) = @_;

    $self->{'_ping_store'}->remove( $frame->get_payload() );

    return;
}

#----------------------------------------------------------------------

sub _verify_not_closed {
    my ($self) = @_;

    die Net::WebSocket::X->create('EndpointAlreadyClosed') if $self->{'_closed'};

    return;
}

sub _handle_control_frame {
    my ($self, $frame) = @_;

    my $type = $frame->get_type();

    if ($type eq 'close') {
        if (!$self->{'_sent_close_frame'}) {
            my ($code, $reason) = $frame->get_code_and_reason();

            if ($code && $code > 4999) {
                my $reason_chunk = substr( $reason, 0, 50 );
                $reason = "Invalid close code ($code, reason: $reason_chunk) received.";
                $code = 'PROTOCOL_ERROR';
            }

            $self->_close_with_frame(
                Net::WebSocket::Frame::close->new(
                    code => $code,
                    reason => $reason,
                    $self->FRAME_MASK_ARGS(),
                ),
            );
        }

        if ($self->{'_received_close_frame'}) {
            warn sprintf('Extra close frame received! (%v.02x)', $frame->to_bytes());
        }
        else {
            $self->{'_received_close_frame'} = $frame;
        }

        if (!$self->{'_no_die_on_close'}) {
            die Net::WebSocket::X->create('ReceivedClose', $frame);
        }
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

sub _write_frame {
    my ($self, $frame) = @_;

    return $self->{'_out'}->write($frame->to_bytes());
}

1;
