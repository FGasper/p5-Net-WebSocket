package IO::Syswrite;

use strict;
use warnings;

#As light as possible?
my $wrote;

sub write_all {
    $wrote = 0;

  WRITE: {
        $wrote += syswrite( $_[0], $_[1], length($_[1]) - $wrote, $wrote ) || do {
            #die Net::WebSocket::X->create('WriteError', OS_ERROR => $!) if $!;

            if ($!) {
                redo WRITE if $!{'EINTR'};  #EINTR => file pointer unchanged
                return undef;
            }

            die "empty write without error??";  #unexpected!
        };
    }

    return $wrote;
}

1;
