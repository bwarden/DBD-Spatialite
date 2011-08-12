#!/usr/bin/perl

# Tests spatial table initialization

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use t::lib::Test;
use Test::More tests => 2;
use Test::NoWarnings;

my $dbh = connect_ok();
$dbh->do(<<'END_SQL');
SELECT InitSpatialMetadata()
END_SQL
