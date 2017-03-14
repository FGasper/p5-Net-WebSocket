package Net::WebSocket::X::ReceivedClose;

use strict;
use warnings;

use parent qw( Net::WebSocket::X::Base );

sub _new {
    my ($class, $frame) = @_;

    my $txt;
    if ( my @code_reason = $frame->get_code_and_reason() ) {
        $txt = "Received close frame: [@code_reason]";
    }
    else {
        $txt = "Received close frame (empty)";
    }

    return $class->SUPER::_new( $txt, frame => $frame );
}

1;
