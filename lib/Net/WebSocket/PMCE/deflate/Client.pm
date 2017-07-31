package Net::WebSocket::PMCE::deflate::Client;

use strict;
use warnings;

use parent qw( Net::WebSocket::PMCE::deflate );

sub create_client_header_parts {
    my ($self) = @_;

    Call::Context::must_be_list();

    my @parts = _EXT_NAME();

    if (exists $self->{'deflate_max_window_bits'}) {
        push @parts, client_max_window_bits => $self->{'deflate_max_window_bits'};
    }

    if (exists $self->{'inflate_max_window_bits'}) {
        push @parts, server_max_window_bits => $self->{'inflate_max_window_bits'};
    }

    #Let’s advertise our support for this feature.
    push @parts, client_no_context_takeover => $self->{'local_no_context_takeover'};

    if ($self->{'peer_no_context_takeover'}) {
        push @parts, server_no_context_takeover => undef;
    }

    return @parts;
}

#TODO: exception objects
sub consume_response_header_parts {
    my ($self, @extensions) = @_;

    return $self->_consume_header_parts(
        \@extensions,
        sub {
            my $opts_hr = shift;

            if (exists $opts_hr->{'server_max_window_bits'}) {
                #TODO: validate_max_window_bits()

                if (defined $self->{'inflate_max_window_bits'}) {
                    if ( $opts_hr->{'server_max_window_bits'} > $self->{'inflate_max_window_bits'} ) {
                        die 'server_max_window_bits greater than client stipulated!';
                    }
                }

                $self->{'inflate_max_window_bits'} = $opts_hr->{'server_max_window_bits'};
                delete $opts_hr->{'server_max_window_bits'};
            }

            if (exists $opts_hr->{'client_max_window_bits'}) {
                #TODO: validate_max_window_bits()

                if (!exists $self->{'inflate_max_window_bits'}) {
                    die 'server requested client_max_window_bits without client support!';
                }

                my $max = $self->{'deflate_max_window_bits'} || $VALID_MAX_WINDOW_BITS[-1];

                if ($opts_hr->{'client_max_window_bits'} < $max) {
                    $self->{'deflate_max_window_bits'} = $opts_hr->{'client_max_window_bits'};
                }

                delete $opts_hr->{'client_max_window_bits'};
            }

            if (exists $opts_hr->{'client_no_context_takeover'}) {
                if (defined $opts_hr->{'client_no_context_takeover'}) {
                    warn 'client_no_context_takeover should have no value!';
                }

                $self->{'local_no_context_takeover'} = 1;

                delete $opts_hr->{'client_no_context_takeover'};
            }

            if ($self->{'peer_no_context_takeover'}) {
                if (!exists $opts_hr->{'server_no_context_takeover'}) {
                    die 'server didn’t accept server_no_context_takeover';
                }

                if (defined $opts_hr->{'server_no_context_takeover'}) {
                    warn 'server_no_context_takeover should have no value!';
                }

                delete $opts_hr->{'server_no_context_takeover'};
            }
        },
    );
}

1;
