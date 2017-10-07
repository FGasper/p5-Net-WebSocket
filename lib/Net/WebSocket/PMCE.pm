package Net::WebSocket::PMCE;

=encoding utf-8

=head1 NAME

Net::WebSocket::PMCE - base class for compression extensions

=head1 SYNOPSIS

    package My::PMCE;

    use parent qw( Net::WebSocket::PMCE );

    package Main;

    my $pmce = My::PMCE->new( ... );

    if ($pmce->message_is_compressed($frame)) { ... }

    $pmce->compress_message($frame);

=head1 DESCRIPTION

This is a base class for Per-Message Compression Extension modules, as
defined in L<RFC 7692|https://tools.ietf.org/html/rfc7692>.

If you’re looking for an implementation of the C<permessage-deflate>
extension, look at L<Net::WebSocket::PMCE::deflate>. Note that
C<permessage-deflate> is a specific B<example> of a PMCE;
as of this writing it’s also the only
one that seems to enjoy widespread use.

=head1 STATUS

This module is an ALPHA release. Changes to the API are not unlikely;
be sure to check the changelog before updating, and please report any
issues you find.

=head1 METHODS

Available on all instances:

=head2 I<OBJ>->message_is_compressed( MESSAGE )

MESSAGE is an instance of L<Net::WebSocket::Message>.
Output is a Perl boolean.

You can also call this as a class method, e.g.:

    Net::WebSocket::PMCE->message_is_compressed( $message_obj );

=head1 SUBCLASS INTERFACE

To make a working subclass of this module you need to provide
means of compression and decompression. It is suggested to follow
the pattern of C<Net::WebSocket::PMCE::deflate>.

=cut

use strict;
use warnings;

sub message_is_compressed {
    return ($_[1]->get_frames())[0]->has_rsv1();
}

#=head2 I<OBJ>->create_message( MESSAGE_CLASS, OCTET_STRING )
#
#Modifies the given OCTET_STRING to be compressed.
#
#Returns the OBJ (B<not> the OCTET_STRING). This facilitates the
#“chaining” pattern.
#
#=cut
#
#sub compress_payload {
#    my ($self, $msg) = @_;
#
#    my @frames = $msg->get_frames();
#    $self->_compress_payload($_) for @frames;
#
#    $frames[0]->set_rsv1();
#
#    return $self;
#}

=head1 REPOSITORY

L<https://github.com/FGasper/p5-Net-WebSocket>

=head1 AUTHOR

Felipe Gasper (FELIPE)

=head1 COPYRIGHT

Copyright 2017 by L<Gasper Software Consulting, LLC|http://gaspersoftware.com>

=head1 LICENSE

This distribution is released under the same license as Perl.

=cut

1;
