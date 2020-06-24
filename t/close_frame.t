#!/usr/bin/env perl

use Net::WebSocket::Constants ();
use Net::WebSocket::Frame::close ();

use Test::More;
use Test::Deep;
use Test::Fatal;
use Test::Exception;
use Test::FailWarnings;

plan tests => 37;

my $frame = Net::WebSocket::Frame::close->new();

is_deeply(
    [ $frame->get_code_and_reason() ],
    [ Net::WebSocket::Constants::status_name_to_code('EMPTY_CLOSE'), q<> ],
    "no code nor reason",
);

while ( my ($k, $v) = each %{ Net::WebSocket::Constants::STATUS() } ) {
    next if $k eq 'EMPTY_CLOSE';

    my $frame = Net::WebSocket::Frame::close->new(
        code => $k,
        reason => "Because $k",
    );

    is_deeply(
        [ $frame->get_code_and_reason() ],
        [ $v, "Because $k" ],
        "$k with code and reason",
    );

    $frame = Net::WebSocket::Frame::close->new(
        code => $k,
    );

    is_deeply(
        [ $frame->get_code_and_reason() ],
        [ $v, q<> ],
        "$k with just code",
    );
}

{
    my @w;

    local $SIG{'__WARN__'} = sub { push @w, @_ };

    Net::WebSocket::Frame::close->new( code => undef, reason => undef );

    is_deeply( \@w, [], 'undef code && undef reason -> no warnings' );
}

{
    my @w;

    local $SIG{'__WARN__'} = sub { push @w, @_ };

    Net::WebSocket::Frame::close->new( code => undef, reason => q<> );

    is_deeply( \@w, [], 'undef code && empty reason -> no warnings' );
}

{
    my @w;

    local $SIG{'__WARN__'} = sub { push @w, @_ };

    Net::WebSocket::Frame::close->new( code => q<>, reason => q<> );

    is_deeply( \@w, [], 'empty code && empty reason -> no warnings' );
}

{
    my @w;

    local $SIG{'__WARN__'} = sub { push @w, @_ };

    Net::WebSocket::Frame::close->new( code => undef, reason => undef );

    is_deeply( \@w, [], 'empty code && undef reason -> no warnings' );
}

for my $code ( 1000, 4000, 4999 ) {
    lives_ok(
        sub { Net::WebSocket::Frame::close->new( code => $code ) },
        "code $code: OK",
    );
}

for my $code ( 999, 5000, '500a' ) {
    my $err = exception { Net::WebSocket::Frame::close->new( code => $code ) };

    cmp_deeply(
        $err,
        all(
            Isa('Net::WebSocket::X::BadArg'),
            methods(
                get_message => all(
                    re( qr<$code> ),
                ),
            ),
        ),
        "code $code: bad",
    ) or diag explain $err;
}
