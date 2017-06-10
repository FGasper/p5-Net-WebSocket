package Net::WebSocket::PMCE::deflate;

use strict;
use warnings;

use IO::Compress::Deflate ();
use IO::Uncompress::Inflate ();

use constant CONSTRUCTOR_NEEDS => ();

sub new {
    my ($class, %opts) = @_;

    my @lack = grep { !length $opts{$_} } CONSTRUCTOR_NEEDS();
    die "Need: [@lack]" if @lack;

    return bless \%opts, $class;
}

sub frame_is_compressed {
    my ($frame) = @_;

    return $frame->has_rsv1();
}

sub message_is_compressed {
    my ($msg) = @_;

    return frame_is_compressed( ($msg->get_frames())[0] );
}

sub compress_frame {
    my ($frame) = @_;

    _compress_frame_payload($frame);

    $frame->set_rsv1();

    return $frame;
}

sub compress_message {
    my ($msg) = @_;

    my @frames = $msg->get_frames();
    _compress_frame_payload($_) for @frames;

    $frames[0]->set_rsv1();

    return $msg;
}

sub get_decompressed_payload {
    my ($msg_or_frame) = @_;

    IO::Uncompress::Inflate::inflate(
        \$msg_or_frame->get_payload(),
        \(my $v),
    ) or die "inflate(): $IO::Uncompress::Inflate::InflateError";

    return $v;
}

sub _compress_frame_payload {
    my ($frame) = @_;

    IO::Compress::Deflate::deflate(
        \$frame->get_payload(),
        \(my $v),
    ) or die "inflate(): $IO::Compress::Deflate::DeflateError";

    $frame->set_payload_sr( \$v );

    return;
}

1;

__END__

Context takeover: technique for compressing/sending
increases amount of memory needed to decompress

server_no_context_takeover
    - “Don’t you use context takeover, Mr. Server!!”
    - “I swear I will not use context takeover, Mr. Client.”
    - if client sends, server must send back
    - if client doesn’t send, server *can* send back
    - server *should* support feature

client_no_context_takeover
    - “BTW, Mr. Server, I won’t use context takeover.”
    - “Don’t you use context takeover, Mr. Client!!”
    - if server sends, client MUST observe/support

server_max_window_bits = [8 .. 15]
    - “Don’t you use more bits than N for sliding window size, Mr. Server!”
    - “I swear I will not use more than N bits.”
    - (15 is the max/default anyway)
    - server responds with <= value

client_max_window_bits = empty | [8 .. 15]
    - server MUST NOT send if client didn’t
    - if empty, that just indicates support for the option

1;
