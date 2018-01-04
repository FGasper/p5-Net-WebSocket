package Net::WebSocket::Frame::text;

=encoding utf-8

=head1 NAME

Net::WebSocket::Frame::text

=head1 SYNOPSIS

B<NOTE:> Before you instantiate this class directly, look at
L<Net::WebSocket::Endpoint>’s C<create_message()> convenience
method to make your life easier.

    my $frm = Net::WebSocket::Frame::text->new(

        #This flag defaults to on
        fin => 1,

        #For servers, this must be empty (default).
        #For clients, this must be four random bytes.
        mask => q<>,

        payload => $payload_text,
    );

    $frm->get_type();           #"text"

    $frm->is_control();   #0

    my $mask = $frm->get_mask_bytes();

    my $payload = $frm->get_payload();

    my $serialized = $frm->to_bytes();

    $frm->set_fin();    #turns on

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Base::DataFrame
);

use constant get_opcode => 1;

1;
