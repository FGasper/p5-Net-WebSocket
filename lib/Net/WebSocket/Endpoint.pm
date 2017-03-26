package Net::WebSocket::Endpoint;

=encoding utf-8

=head1 NAME

Net::WebSocket::Endpoint

=head1 DESCRIPTION

See L<Net::WebSocket::Endpoint::Server>.

=cut

use strict;
use warnings;

use Call::Context ();
use IO::SigGuard ();

use Net::WebSocket::Frame::close ();
use Net::WebSocket::Frame::ping ();
use Net::WebSocket::Frame::pong ();
use Net::WebSocket::Message ();
use Net::WebSocket::PingStore ();
use Net::WebSocket::X ();

use constant DEFAULT_MAX_PINGS => 3;

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !length $opts{$_} } qw( parser );
    #die "Missing: [@missing]" if @missing;

    my $self = {
        _fragments => [],

        _max_pings => $class->DEFAULT_MAX_PINGS(),

        _ping_store => Net::WebSocket::PingStore->new(),

        _frames_queue => [],

        (map { defined($opts{$_}) ? ( "_$_" => $opts{$_} ) : () } qw(
            parser
            max_pings

            on_data_frame

            out
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

    my $write_func = $self->_get_write_func();

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
    my ($self, %opts) = @_;

    my $close = Net::WebSocket::Frame::close->new(
        $self->FRAME_MASK_ARGS(),
        code => $opts{'code'} || 'ENDPOINT_UNAVAILABLE',
        reason => $opts{'reason'},
    );

    my $write_func = $self->_get_write_func();

    $self->$write_func($close);

    $self->{'_closed'} = 1;

    return;
}

sub is_closed {
    my ($self) = @_;
    return $self->{'_closed'} ? 1 : 0;
}

sub get_write_queue_size {
    my ($self) = @_;

    return ($self->{'_partially_written_frame'} ? 1 : 0) + @{ $self->{'_frames_queue'} };
}

sub shift_write_queue {
    my ($self) = @_;

    return shift @{ $self->{'_frames_queue'} };
}

sub process_write_queue {
    my ($self) = @_;

    $self->_verify_not_closed();

    if ($self->{'_partially_written_frame'}) {
        if ( $self->_write_bytes_no_prehook( $self->{'_partially_written_frame'} ) ) {
            undef $self->{'_partially_written_frame'};
        }
    }
    else {
        my $qi = shift @{ $self->{'_frames_queue'} } or die 'process_write_queue() on empty!';

        $self->_write_now( $qi );
    }

    return;
}

#----------------------------------------------------------------------

sub on_ping {
    my ($self, $frame) = @_;

    my $write_func = $self->_get_write_func();

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

sub _get_write_func {
    my ($self) = @_;

    return $self->{'_out'} ? '_write_now' : '_enqueue_write';
}

sub _enqueue_write {
    my $self = shift;

    push @{ $self->{'_frames_queue'} }, $_[0];

    return;
}

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

    my $write_func = $self->_get_write_func();

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

    my $write_func = $self->_get_write_func();

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

        my $write_func = $self->_get_write_func();

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

sub _write_now {
    my ($self, $frame, $todo_cr) = @_;

    if ($self->can('_before_send_frame')) {
        $self->_before_send_frame($frame);
    }

    return $self->_write_bytes_no_prehook($frame->to_bytes(), $todo_cr);
}

sub _write_bytes_no_prehook {
    my $self = $_[0];

    local $!;

    my $wrote = IO::SigGuard::syswrite( $self->{'_out'}, $_[1] );

    #Full success:
    if ($wrote == length $_[1]) {
        $_[2]->() if $_[2];
        return 1;
    }

    #Partial write; we need to come back to this one.
    $self->{'_partially_written_frame'} = substr( $_[1], $wrote );

    return;
}

1;
