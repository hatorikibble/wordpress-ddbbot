use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Wordpress::DDBBot',
    AUTHOR        => q{Peter Mayr <at.peter.mayr@gmail.com>},
    VERSION_FROM  => 'lib/Wordpress/DDBBot.pm',
    ABSTRACT_FROM => 'lib/Wordpress/DDBBot.pm',
    ( $ExtUtils::MakeMaker::VERSION >= 6.3002
        ? ( 'LICENSE' => 'perl' )
        : () ),
    EXE_FILES => ['bin/ddbbot'],
    PL_FILES  => {},
    PREREQ_PM => {
        'Test::More'            => 0,
        'Config::Any::JSON'     => 0,
        'JSON'                  => '2.59',
        'List::Util'            => 0,
        'Log::Log4perl'         => '1.29',
        'LWP::Simple'           => 0,
        'MooseX::Daemonize'     => '0.15',
        'MooseX::Getopt'        => 0,
        'MooseX::Log::Log4perl' => 0,
        'MooseX::Runnable'      => 0,
        'Switch'                => 0,
        'Template'              => 0,
        'URI::Escape'           => 0,
        'WordPress::XMLRPC'     => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES    => 'Wordpress-DDBBot-*' },
);
