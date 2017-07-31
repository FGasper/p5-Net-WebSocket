package Net::WebSocket::PMCE::deflate::Server;

use strict;
use warnings;

use parent qw( Net::WebSocket::PMCE::deflate );

use Net::WebSocket::Handshake::Extension ();

=head2 my $ext = I<OBJ>->consume_offer_header_parts( EXTENSIONS )

EXTENSIONS is a list of L<Net::WebSocket::Handshake::Extension>
instances, a parse of the C<Sec-WebSocket-Extensions> header(s) from
the client.

This returns undef if none of the EXTENSIONS corresponds to this
module, or a single L<Net::WebSocket::Handshake::Extension> instance
if one of them does. That instance’s string representation should go
into the response’s C<Sec-WebSocket-Extensions> header.

=cut

sub consume_offer_header_parts {
    my ($self, @extensions) = @_;

    my @headers;

    my $use_ext = $self->_consume_header_parts(
        \@extensions,
        sub {
            my $opts_hr = shift;

            if (exists $opts_hr->{'server_max_window_bits'}) {
                #TODO: validate_max_window_bits()

                #Client mandates this for us.
                #If we didn’t limit our deflate window before,
                #or if the window was bigger than what the client
                #wants, then take the client’s value.
                if (!$self->{'deflate_max_window_bits'} || ($self->{'deflate_max_window_bits'} > $opts_hr->{'server_max_window_bits'})) {
                    $self->{'deflate_max_window_bits'} = delete $opts_hr->{'server_max_window_bits'};
                }

                delete $opts_hr->{'server_max_window_bits'};
            }

            if (exists $opts_hr->{'client_max_window_bits'}) {
                #TODO: validate_max_window_bits()

                #Client allows us this optimization.
                #If we didn’t limit our inflate window before,
                #or if the window was bigger than what the client
                #is actually compressing with, then take the client’s value.
                if (!$self->{'inflate_max_window_bits'} || ($self->{'inflate_max_window_bits'} > $opts_hr->{'client_max_window_bits'})) {
                    $self->{'inflate_max_window_bits'} = delete $opts_hr->{'client_max_window_bits'};
                }

                delete $opts_hr->{'client_max_window_bits'};
            }

            if (exists $opts_hr->{'server_no_context_takeover'}) {
                if (defined $opts_hr->{'server_no_context_takeover'}) {
                    warn 'server_no_context_takeover should have no value!';
                }

                $self->{'local_no_context_takeover'} = 1;

                delete $opts_hr->{'server_no_context_takeover'};
            }

            if (exists $opts_hr->{'client_no_context_takeover'}) {
                if (defined $opts_hr->{'client_no_context_takeover'}) {
                    warn 'client_no_context_takeover should have no value!';
                }

                #The server doesn’t do anything differently …
                #but is there some memory usage optimization
                #we could do?

                delete $opts_hr->{'client_no_context_takeover'};
            }
        },
    );

    return undef if !$use_ext;

    return Net::WebSocket::Handshake::Extension->new(
        $self->TOKEN(),

        ( $self->{'peer_no_context_takeover'}
            ? ( client_no_context_takeover => undef )
            : ()
        ),

        ( $self->{'local_no_context_takeover'}
            ? ( server_no_context_takeover => undef )
            : ()
        ),

        ( $self->{'deflate_max_window_bits'}
            ? ( server_max_window_bits => $self->{'deflate_max_window_bits'} )
            : ()
        ),

        ( $self->{'inflate_max_window_bits'}
            ? ( client_max_window_bits => $self->{'inflate_max_window_bits'} )
            : ()
        ),
    );
}

1;
