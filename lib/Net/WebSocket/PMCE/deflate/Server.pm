package Net::WebSocket::PMCE::deflate::Server;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::PMCE::deflate
);

use constant {
    _ENDPOINT_CLASS => 'Server',
    _PEER_NO_CONTEXT_TAKEOVER_PARAM => 'client_no_context_takeover',
    _LOCAL_NO_CONTEXT_TAKEOVER_PARAM => 'server_no_context_takeover',
    _DEFLATE_MAX_WINDOW_BITS_PARAM => 'server_max_window_bits',
    _INFLATE_MAX_WINDOW_BITS_PARAM => 'client_max_window_bits',
};

#----------------------------------------------------------------------

sub _consume_extension_options {
    my ($self, $opts_hr) = @_;

    for my $ept_opt ( [ client => 'inflate' ], [ server => 'deflate' ] ) {
        my $mwb_opt = "$ept_opt->[0]_max_window_bits";

        if (exists $opts_hr->{$mwb_opt}) {
            if ($ept_opt->[0] eq 'client') {
                $self->{'_peer_supports_client_max_window_bits'} = 1;

                if (!defined $opts_hr->{$mwb_opt}) {
                    delete $opts_hr->{$mwb_opt};
                    next;
                }
            }

            my $self_opt = "$ept_opt->[1]_max_window_bits";
            $self->__validate_max_window_bits($ept_opt->[0], $opts_hr->{$mwb_opt});

            my $max = $self->{$self_opt} || ( $self->VALID_MAX_WINDOW_BITS() )[-1];

            if ($opts_hr->{$mwb_opt} < $max) {
                $self->{$self_opt} = $opts_hr->{$mwb_opt};
            }

            #If the client requested a greater server_max_window_bits than
            #we want, that’s no problem, but we’re just going to ignore it.

            delete $opts_hr->{$mwb_opt};
        }
    }

    for my $ept_opt ( [ client => 'peer' ], [ server => 'local' ] ) {
        my $nct_hdr = "$ept_opt->[0]_no_context_takeover";

        if (exists $opts_hr->{$nct_hdr}) {
            $self->__validate_no_context_takeover( $ept_opt->[0], $opts_hr->{$nct_hdr} );

            $self->{"$ept_opt->[1]_no_context_takeover"} = 1;

            delete $opts_hr->{$nct_hdr};
        }
    }

    return;
}

sub peer_supports_client_max_window_bits {
    my ($self) = @_;
    return $self->{'_peer_supports_client_max_window_bits'};
}

1;
