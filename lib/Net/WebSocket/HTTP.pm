package Net::WebSocket::HTTP;

use strict;
use warnings;

use Call::Context ();

#TODO: Publish separately.
sub split_tokens {
    my ($value) = @_;

    Call::Context::must_be_list();

    $value =~ s<\A[ \t]+><>;
    $value =~ s<[ \t]+\z><>;

    my $inval;

    my @tokens;
    for my $p ( split m<[ \t]*,[ \t]*>, $value ) {
        if ($p =~ tr~()<>@,;:\\"/[]?={} \t~~) {
            $inval = $p;
        }

        die "“$inval” is not a valid HTTP token!" if defined $inval;

        push @tokens, $p;
    }

    return @tokens;
}

1;
