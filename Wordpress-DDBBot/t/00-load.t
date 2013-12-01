#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Wordpress::DDBBot' ) || print "Bail out!\n";
}

diag( "Testing Wordpress::DDBBot $Wordpress::DDBBot::VERSION, Perl $], $^X" );
