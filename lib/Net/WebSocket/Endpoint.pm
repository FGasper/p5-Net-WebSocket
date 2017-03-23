package Net::WebSocket::Endpoint;

=encoding utf-8

=head1 NAME

Net::WebSocket::Endpoint

=head1 DESCRIPTION

See L<Net::WebSocket::Endpoint::Server>.

=cut

use strict;
use warnings;

use Net::WebSocket::Frame::close ();
use Net::WebSocket::Frame::ping ();
use Net::WebSocket::Frame::pong ();
use Net::WebSocket::Message ();
use Net::WebSocket::PingStore ();
use Net::WebSocket::X ();

use constant DEFAULT_MAX_PINGS => 10;

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !length $opts{$_} } qw( parser out );
    #die "Missing: [@missing]" if @missing;

    my $out_blocking = $opts{'out'}->blocking();

    if (!$out_blocking && !IO::WriteQueue->can('new')) {
        Module::Load::load('IO::WriteQueue');
    }

    my $self = {
        _fragments => [],

        _max_pings => $class->DEFAULT_MAX_PINGS(),

        _ping_store => Net::WebSocket::PingStore->new(),

        _write_func => ($out_blocking ? '_write_frame_now' : '_enqueue_write'),

        _frames_queue => [],
        _write_queue => !$out_blocking && IO::WriteQueue->new($opts{'out'}),

        (map { defined($opts{$_}) ? ( "_$_" => $opts{$_} ) : () } qw(
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

    $self->_verify_not_closed();

    if ( my $frame = $self->{'_parser'}->get_next_frame() ) {
        if ($frame->is_control_frame()) {
            $self->_handle_control_frame($frame);
        }
        else {
            if ($self->{'_on_data_frame'}) {
                $self->{'_on_data_frame'}->($frame);
            }

            #Failure cases:
            #   - continuation without prior fragment
            #   - non-continuation within fragment

            if ( $frame->get_type() eq 'continuation' ) {
                if ( !@{ $self->{'_fragments'} } ) {
                    $self->_got_continuation_during_non_fragment($frame);
                }
            }
            elsif ( @{ $self->{'_fragments'} } ) {
                $self->_got_non_continuation_during_fragment($frame);
            }

            if ($frame->get_fin()) {
                return Net::WebSocket::Message::create_from_frames(
                    splice( @{ $self->{'_fragments'} } ),
                    $frame,
                );
            }
            else {
                push @{ $self->{'_fragments'} }, $frame;
            }
        }
    }

    return undef;
}

sub check_heartbeat {
    my ($self) = @_;

    my $ping_counter = $self->{'_ping_store'}->get_count();

    my $write_func = $self->{'_write_func'};

    if ($ping_counter == $self->{'_max_pings'}) {
        my $close = Net::WebSocket::Frame::close->new(
            $self->FRAME_MASK_ARGS(),
            code => 'POLICY_VIOLATION',
        );

        $self->$write_func($close);

        $self->{'_closed'} = 1;
    }

    my $ping_message = $self->{'_ping_store'}->add();

    my $ping = Net::WebSocket::Frame::ping->new(
        payload_sr => \$ping_message,
        $self->FRAME_MASK_ARGS(),
    );

    $self->$write_func($ping);

    return;
}

sub shutdown {
    my ($self, $reason) = @_;

    my $close = Net::WebSocket::Frame::close->new(
        $self->FRAME_MASK_ARGS(),
        code => 'ENDPOINT_UNAVAILABLE',
        reason => $reason,
    );

    my $write_func = $self->{'_write_func'};

    $self->$write_func($close);

    $self->{'_closed'} = 1;

    return;
}

sub is_closed {
    my ($self) = @_;
    return $self->{'_closed'} ? 1 : 0;
}

sub frames_to_write {
    my ($self) = @_;

    return 0 + @{ $self->{'_frames_queue'} };
}

sub process_write_queue {
    my ($self) = @_;

    $self->_verify_not_closed();

    while ( my $qi = $self->{'_frames_queue'}[0] ) {
        if ( $self->_write_now_then_callback( @$qi ) ) {
            shift @{ $self->{'_frames_queue'} };
        }
        else {
            last;
        }
    }

    return;
}

#----------------------------------------------------------------------

sub on_ping {
    my ($self, $frame) = @_;

    my $write_func = $self->{'_write_func'};

    $self->$write_func(
        Net::WebSocket::Frame::pong->new(
            payload_sr => \$frame->get_payload(),
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

sub _got_continuation_during_non_fragment {
    my ($self, $frame) = @_;

    my $msg = sprintf('Received continuation outside of fragment!');

    #For now … there may be some multiplexing extension
    #that allows some other behavior down the line,
    #but let’s enforce standard protocol for now.
    my $err_frame = Net::WebSocket::Frame::close->new(
        code => 'PROTOCOL_ERROR',
        reason => $msg,
        $self->FRAME_MASK_ARGS(),
    );

    my $write_func = $self->{'_write_func'};

    $self->$write_func($err_frame);

    die Net::WebSocket::X->create( 'ReceivedBadControlFrame', $msg );
}

sub _got_non_continuation_during_fragment {
    my ($self, $frame) = @_;

    my $msg = sprintf('Received %s; expected continuation!', $frame->get_type());

    #For now … there may be some multiplexing extension
    #that allows some other behavior down the line,
    #but let’s enforce standard protocol for now.
    my $err_frame = Net::WebSocket::Frame::close->new(
        code => 'PROTOCOL_ERROR',
        reason => $msg,
        $self->FRAME_MASK_ARGS(),
    );

    my $write_func = $self->{'_write_func'}

    $self->$write_func($err_frame);

    die Net::WebSocket::X->create( 'ReceivedBadControlFrame', $msg );
}

sub _verify_not_closed {
    my ($self) = @_;

    die "Already closed!" if $self->{'_closed'};

    return;
}

sub _handle_control_frame {
    my ($self, $frame) = @_;

    my ($resp_frame, $error, $ignore_sigpipe);

    my $type = $frame->get_type();

    if ($type eq 'close') {
        $self->{'_received_close'} = 1;
        $self->{'_closed'} = 1;

        my ($code, $reason) = $frame->get_code_and_reason();

        $resp_frame = Net::WebSocket::Frame::close->new(
            code => $code,
            reason => $reason,
            $self->FRAME_MASK_ARGS(),
        );

        my $write_func = $self->{'_write_func'};

        $self->$write_func( $resp_frame );

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

sub _write_now_then_callback {
    my ($self, $frame, $todo_cr) = @_;

    if ($self->can('_before_send_frame')) {
        $self->_before_send_frame($frame);
    }

    if ($self->{'_write_queue'}) {
        $self->{'_write_queue'}->add( $frame->to_bytes(), $todo_cr );

    local $!;

  WRITE: {
        syswrite( $self->{'_out'}, $frame->to_bytes() ) or do {
            if ($!) {
                redo WRITE if $!{'EINTR'};
                die "write err: [$!]";  #XXX FIXME
            }
            else {
                die Net::WebSocket::X->create('EmptyRead');
            }
        };
    }

    return;
}

1;
