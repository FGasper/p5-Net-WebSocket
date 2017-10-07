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
            my $self_opt = "$ept_opt->[1]_max_window_bits";
            $self->__validate_max_window_bits($opts_hr->{$mwb_opt});

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
            $self->__validate_no_context_takeover( 'client', $opts_hr->{$nct_hdr} );

            $self->{"$ept_opt->[1]_no_context_takeover"} = 1;

            delete $opts_hr->{$nct_hdr};
        }
    }

    return;
}

#=head2 I<CLASS>->new( %OPTS )
#
#Returns a new instance of this class.
#
#C<%OPTS> recognizes the C<server_max_window_bits>,
#C<client_max_window_bits>, and C<server_no_context_takeover> parameters
#from the WebSocket handshake. The same values that are valid from that
#handshake are valid here. It is assumed that you’ve validated these
#already.
#
#=cut
#
#sub new {
#    my ($class, %opts) = @_;
#
#    if (!defined $opts{'client_max_window_bits'}) {
#        delete $opts{'client_max_window_bits'};
#    }
#
#    return $class->SUPER::new(%opts);
#}
#
#sub _validate_client_max_window_bits {
#    return if !defined $_[1];
#    return $_[0]->SUPER::_validate_client_max_window_bits($_[1]);
#}
#
#
#=head2 my $ext = I<OBJ>->consume_offer_extensions( EXTENSIONS )
#
#NONONO
#
#EXTENSIONS is a list of L<Net::WebSocket::Handshake::Extension>
#instances, a parse of the C<Sec-WebSocket-Extensions> header(s) from
#the client.
#
#This returns undef if none of the EXTENSIONS corresponds to this
#module, or a single L<Net::WebSocket::Handshake::Extension> instance
#if one of them does. That instance’s string representation should go
#into the response’s C<Sec-WebSocket-Extensions> header.
#
#=cut
#
#sub consume_peer_extensions {
#    my ($self, @extensions) = @_;
#
#    return $self->_consume_header_parts(
#        \@extensions,
#        sub {
#            my $opts_hr = shift;
#
#            my @return_opts;
#
#            if (exists $opts_hr->{'server_max_window_bits'}) {
#                #TODO: validate_max_window_bits()
#
#                push @return_opts, (
#                    local_max_window_bits => $opts_hr->{'server_max_window_bits'},
#                );
#
##                #Client mandates this for us.
##                #If we didn’t limit our deflate window before,
##                #or if the window was bigger than what the client
##                #wants, then take the client’s value.
##                if (!$self->{'deflate_max_window_bits'} || ($self->{'deflate_max_window_bits'} > $opts_hr->{'server_max_window_bits'})) {
##                    $self->{'deflate_max_window_bits'} = delete $opts_hr->{'server_max_window_bits'};
##                }
##
##                delete $opts_hr->{'server_max_window_bits'};
#            }
#
#            if (exists $opts_hr->{'client_max_window_bits'}) {
#                #TODO: validate_max_window_bits()
#
##                #Client allows us this optimization.
##                #If we didn’t limit our inflate window before,
##                #or if the window was bigger than what the client
##                #is actually compressing with, then take the client’s value.
##                if (!$self->{'inflate_max_window_bits'} || ($self->{'inflate_max_window_bits'} > $opts_hr->{'client_max_window_bits'})) {
##                    $self->{'inflate_max_window_bits'} = delete $opts_hr->{'client_max_window_bits'};
##                }
##
##                delete $opts_hr->{'client_max_window_bits'};
#            }
#
#            if (exists $opts_hr->{'server_no_context_takeover'}) {
#                if (defined $opts_hr->{'server_no_context_takeover'}) {
#                    warn 'server_no_context_takeover should have no value!';
#                }
#
#                $self->{'local_no_context_takeover'} = 1;
#
#                delete $opts_hr->{'server_no_context_takeover'};
#            }
#
#            if (exists $opts_hr->{'client_no_context_takeover'}) {
#                if (defined $opts_hr->{'client_no_context_takeover'}) {
#                    warn 'client_no_context_takeover should have no value!';
#                }
#
#                #The server doesn’t do anything differently …
#                #but is there some memory usage optimization
#                #we could do?
#
#                delete $opts_hr->{'client_no_context_takeover'};
#            }
#        },
#    );
#
#    return undef if !$use_ext;
#}

1;
