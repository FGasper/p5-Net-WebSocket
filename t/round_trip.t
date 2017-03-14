#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Carp::Always;   #XXX

use Test::More;

plan tests => 1;

use Net::WebSocket::ParseFilehandle ();

my $start = 'We have come to dedicate a portion of that field as a final resting-place to those who here gave their lives that that nation might live. It is altogether fitting and proper that we should do this; yet, in a larger sense, we cannot dedicate, we cannot consecrate, we cannot hallow this ground. The brave men, living and dead, who struggled here have consecrated it far beyond our poor power to add or detract. The world will little note …';

my $start_copy = $start;

my $ser = t::SerializeString->new( \$start_copy );

pipe( my $rdr, my $wtr );

while (length $start_copy) {
    my $msg = $ser->create_text(25);
    print {$wtr} $_->to_bytes() for $msg->get_frames();
}

close $wtr;

my $parse = Net::WebSocket::ParseFilehandle->new( $rdr );

my $received = q<>;

while ( my $msg = $parse->get_next_frame() ) {
    $received .= $msg->get_payload();
}

is(
    $received,
    $start,
    'round-trip',
);

#----------------------------------------------------------------------

package t::SerializeString;

use parent qw( Net::WebSocket::SerializeString::Client );

use constant MAX_FRAGMENT => 10;

1;
