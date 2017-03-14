package Net::WebSocket::Endpoint;

use strict;
use warnings;

use Net::WebSocket::Message ();
use Net::WebSocket::X ();

use constant DEFAULT_MAX_PINGS => 2;

sub new {
    my ($class, %opts) = @_;

    my @missing = grep { !length $opts{$_} } qw( parser serializer out );
    die "Missing: [@missing]" if @missing;

    my $self = {
        _sent_pings => 0,
        _max_pings => DEFAULT_MAX_PINGS,
        (map { ( "_$_" => $opts{$_} ) } qw(
            parser
            serializer
            out
            max_pings
        )),
    };

    return bless $self, $class;
}

sub get_next_message {
    my ($self) = @_;

    die "Already closed!" if $self->{'_closed'};

    if ( my $frame = $self->{'_parser'}->get_next_frame() ) {
        if ($frame->is_control_frame()) {
            if ($frame->get_type() eq 'close') {
                my $rframe = $self->{'_serializer'}->create_close(
                    $frame->get_code_and_reason(),
                );

                local $SIG{'PIPE'} = 'IGNORE';

                syswrite(
                    $self->{'_out'},
                    $rframe->to_bytes(),
                );

                $self->{'_closed'} = 1;

                die Net::WebSocket::X->create('ReceivedClose', $frame);
            }
            elsif ($frame->get_type() eq 'ping') {
                syswrite(
                    $self->{'_out'},
                    $self->{'_serializer'}->create_pong(
                        $frame->get_payload(),
                    )->to_bytes(),
                );
            }
            elsif ($frame->get_type() eq 'pong') {
                $self->{'_sent_pings'}--;
            }
            else {
                die "Unrecognized control frame ($frame)";
            }
        }
        elsif (!$frame->get_fin()) {
            push @{ $self->{'_fragments'} }, $frame;
        }
        else {
            return Net::WebSocket::Message::create_from_frames(
                splice( @{ $self->{'_fragments'} } ),
                $frame,
            );
        }
    }

    return undef;
}

sub timeout {
    my ($self) = @_;

    if ($self->{'_sent_pings'} == $self->{'_max_pings'}) {
        my $close = $self->{'_serializer'}->create_close('POLICY_VIOLATION');
        syswrite( $self->{'_out'}, $close->to_bytes() );
        $self->{'_closed'} = 1;
    }

    my $ping = $self->{'_serializer'}->create_ping(
        payload_sr => \"$self->{'_sent_pings'} of $self->{'_max_pings'}",
    );
    syswrite( $self->{'_out'}, $ping->to_bytes() );

    $self->{'_sent_pings'}++;

    return;
}

sub is_closed {
    my ($self) = @_;
    return $self->{'_closed'} ? 1 : 0;
}

1;
