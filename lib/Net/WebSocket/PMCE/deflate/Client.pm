package Net::WebSocket::PMCE::deflate::Client;

use strict;
use warnings;

use parent qw(
    Net::WebSocket::PMCE::deflate
);

use constant {
    _PEER_NO_CONTEXT_TAKEOVER_PARAM => 'server_no_context_takeover',
    _LOCAL_NO_CONTEXT_TAKEOVER_PARAM => 'client_no_context_takeover',
    _DEFLATE_MAX_WINDOW_BITS_PARAM => 'client_max_window_bits',
    _INFLATE_MAX_WINDOW_BITS_PARAM => 'server_max_window_bits',
};

sub _create_extension_header_parts {
    my ($self) = @_;

    my @parts = $self->SUPER::_create_extension_header_parts();

    #Let’s always advertise support for this feature.
    if (!defined $self->{'deflate_max_window_bits'}) {
        push @parts, _DEFLATE_MAX_WINDOW_BITS_PARAM() => undef;
    }

    return @parts;
}

sub _consume_extension_options {
    my ($self, $opts_hr) = @_;

    if (exists $opts_hr->{'server_max_window_bits'}) {
        #TODO: validate_max_window_bits()

        if ( $opts_hr->{'server_max_window_bits'} > $self->inflate_max_window_bits() ) {
            die 'server_max_window_bits greater than client stipulated!';
        }

        $self->{'inflate_max_window_bits'} = $opts_hr->{'server_max_window_bits'};
        delete $opts_hr->{'server_max_window_bits'};
    }

    if (exists $opts_hr->{'client_max_window_bits'}) {
        #TODO: validate_max_window_bits()

        #We always support this.
        #if (!exists $self->{'inflate_max_window_bits'}) {
        #    die 'server requested client_max_window_bits without client support!';
        #}

        my $max = $self->deflate_max_window_bits();

        if ($opts_hr->{'client_max_window_bits'} < $max) {
            $self->{'deflate_max_window_bits'} = $opts_hr->{'client_max_window_bits'};
        }

        #If the server requested a greater client_max_window_bits than
        #we gave, that’s no problem, but we’re just going to ignore it.

        delete $opts_hr->{'client_max_window_bits'};
    }

    if (exists $opts_hr->{'client_no_context_takeover'}) {
        $self->__validate_no_context_takeover( $opts_hr->{'client_no_context_takeover'} );

        $self->{'local_no_context_takeover'} = 1;

        delete $opts_hr->{'client_no_context_takeover'};
    }

    if (exists $opts_hr->{'server_no_context_takeover'}) {
        $self->__validate_no_context_takeover( $opts_hr->{'server_no_context_takeover'} );
        delete $opts_hr->{'server_no_context_takeover'};
    }
    elsif ($self->{'peer_no_context_takeover'}) {
        die 'server didn’t accept server_no_context_takeover';
    }

    return;
}

##TODO: exception objects
#sub consume_response_header_parts {
#    my ($self, @extensions) = @_;
#
#    return $self->_consume_header_parts(
#        \@extensions,
#        sub {
#            my $opts_hr = shift;
#
#
#        },
#    );
#}

1;
