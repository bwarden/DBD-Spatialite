#!/usr/bin/perl

# Tests path containing non-latine-1 characters
# currently fails on Windows

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use t::lib::Test;
use Test::More;
BEGIN {
	if ( $] >= 5.008005 ) {
		plan( tests => (($^O eq 'cygwin') ? 15 : 27) );
	} else {
		plan( skip_all => 'Unicode is not supported before 5.8.5' );
	}
}
use Test::NoWarnings;
use File::Temp ();
use File::Spec::Functions ':ALL';

# Don't use this, it annoys the MinimumVersion scanner
# use utf8;

eval "require utf8";
die $@ if $@;

my $dir = File::Temp::tempdir( CLEANUP => 1 );
foreach my $subdir ( 'longascii', 'adatb�zis', 'name with spaces', '��� ������') {
	if ($^O eq 'cygwin') {
		next if (($subdir eq 'adatb�zis') || ($subdir eq '��� ������'));
	}
	utf8::upgrade($subdir);
	ok(
		mkdir(catdir($dir, $subdir)),
		"$subdir created",
	);

	# Open the database
	my $dbfile = catfile($dir, $subdir, 'db.db');
	eval {
		my $dbh = DBI->connect("dbi:Spatialite:dbname=$dbfile", undef, undef, {
			RaiseError => 1,
			PrintError => 0,
		} );
		isa_ok( $dbh, 'DBI::db' );
	};
	is( $@, '', "Could connect to database in $subdir" );
	diag( $@ ) if $@;
	unlink(_path($dbfile))  if -e _path($dbfile);

	# Repeat with the unicode flag on
	my $ufile = $dbfile;
	eval {
		my $dbh = DBI->connect("dbi:Spatialite:dbname=$dbfile", undef, undef, {
			RaiseError => 1,
			PrintError => 0,
			sqlite_unicode    => 1,
		} );
		isa_ok( $dbh, 'DBI::db' );
	};
	is( $@, '', "Could connect to database in $subdir" );
	diag( $@ ) if $@;
	unlink(_path($ufile))  if -e _path($ufile);
	
	# when the name of the database file has non-latin characters
	my $dbfilex = catfile($dir, "$subdir.db");
	eval {
		DBI->connect("dbi:Spatialite:dbname=$dbfilex", "", "", {RaiseError => 1, PrintError => 0});
	};
	ok(!$@, "Could connect to database in $dbfilex") or diag $@;
	unlink(_path($dbfilex))  if -e _path($dbfilex);
}


# connect to an empty filename - sqlite will create a tempfile
eval {
	my $dbh = DBI->connect("dbi:Spatialite:dbname=", undef, undef, {
		RaiseError => 1,
		PrintError => 0,
	} );
	isa_ok( $dbh, 'DBI::db' );
};
is( $@, '', "Could connect to temp database (empty filename)" );
diag( $@ ) if $@;




sub _path {  # copied from DBD::Spatialite::connect
	my $path = shift;

	if ($^O =~ /MSWin32/) {
		require Win32;
		require File::Basename;

		my ($file, $dir, $suffix) = File::Basename::fileparse($path);
		my $short = Win32::GetShortPathName($path);
		if ( $short && -f $short ) {
			# Existing files will work directly.
			$path = $short;
		} elsif ( -d $dir ) {
			$path = join '', grep { defined } Win32::GetShortPathName($dir), $file, $suffix;
		}
	}
	return $path;
}
