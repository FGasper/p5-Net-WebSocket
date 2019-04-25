#----------------------------------------------------------------------
# We’d ordinarily use IO::Framed for this, but IO::Handle already reads
# from the filehandle. So, this implements the needed read() interface
# to imitate IO::Framed::Read for Net::WebSocket::Parser.

package MockReader;

sub new {
    my ($class) = @_;

    my $self = q<>;

    return bless \$self, $class;
}

sub add {
    ${ $_[0] } .= $_[1];

    return;
}

sub get {
    return ${ $_[0] };
}

sub read {
    my $chunk = substr( ${ $_[0] }, 0, $_[1], q<> );

    #Important not to return empty-string to mimic a real read() call.
    return length($chunk) ? $chunk : undef;
}

1;
