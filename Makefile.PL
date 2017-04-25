
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Net::WebSocket',
    VERSION_FROM => 'lib/Net/WebSocket.pm',         # finds \$VERSION
    AUTHOR       => 'Felipe Gasper',
    ABSTRACT_FROM => 'lib/Net/WebSocket.pm',
    LICENSE      => 'perl',
    PREREQ_PM    => {
        'autodie'                  => 0,
        'parent'                   => 0,
        'overload' => 0,
        'X::Tiny'   => 0,
        'Module::Load'  => 0,
        'MIME::Base64' => 0,
        'Digest::SHA' => 0,
        'URI::Split' => 0,
        'Bytes::Random::Secure::Tiny' => 0,
        'Call::Context' => 0,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/FGasper/p5-Net-WebSocket.git',
                web  => 'https://github.com/FGasper/p5-Net-WebSocket',
            },
        },
    },
    TEST_REQUIRES => {
        'Test::More'      => 0,
        'Test::Simple'    => 0,
        'Test::Deep'    => 0,
    },
);
