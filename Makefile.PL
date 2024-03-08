# From ExtUtils::MakeMaker 6.48 and DBI 1.43
use 5.006;
use strict;
use ExtUtils::MakeMaker;
use Config;
use File::Find;
use ExtUtils::CChecker;

# Some dependencies need to be more aggressive on Windows
sub WINLIKE () {
	return 1 if $^O eq 'MSWin32';
	return 1 if $^O eq 'cygwin';
	return '';
}

# Make setting optional MakeMaker parameters more readable
sub OPTIONAL {
	return () unless $ExtUtils::MakeMaker::VERSION ge shift;
	return @_;
}

our %args = map { split /\s*=\s*/ } @ARGV;
my $LDFLAGS = $args{ LDFLAGS };
my $CCFLAGS = $args{ CCFLAGS };

# Because DBI generates a postamble at configure-time, we need
# the required version of DBI very early.
my $DBI_required = 1.57;
eval {
	require DBI;
};
if ( $@ or DBI->VERSION < $DBI_required ) {
	print "DBI 1.57 is required to configure this module, please install it or upgrade your CPAN/CPANPLUS shell\n";
	exit(0);
}

# See if we have a C compiler
# The following code is adapted from Module::Install::Can
SCOPE: {
	# Fix Cygwin bug on maybe_command();
	if ( $^O eq 'cygwin' ) {
		require ExtUtils::MM_Cygwin;
		require ExtUtils::MM_Win32;
		if ( ! defined(&ExtUtils::MM_Cygwin::maybe_command) ) {
			*ExtUtils::MM_Cygwin::maybe_command = sub {
				my ($self, $file) = @_;
				if ($file =~ m{^/cygdrive/}i and ExtUtils::MM_Win32->can('maybe_command')) {
					ExtUtils::MM_Win32->maybe_command($file);
				} else {
					ExtUtils::MM_Unix->maybe_command($file);
				}
			}
		}
	}

	sub can_run {
		my $cmd = shift;
		my $_cmd = $cmd;
		return $_cmd if (-x $_cmd or $_cmd = MM->maybe_command($_cmd));

		for my $dir ( (split /$Config::Config{path_sep}/, $ENV{PATH}), '.' ) {
			next if $dir eq '';
			my $abs = File::Spec->catfile($dir, $_[1]);
			return $abs if (-x $abs or $abs = MM->maybe_command($abs));
		}

		return;
	}

	sub can_cc {
		my @chunks = split(/ /, $Config::Config{cc}) or return;

		# $Config{cc} may contain args; try to find out the program part
		while ( @chunks ) {
			return can_run("@chunks") || (pop(@chunks), next);
		}

		return;
	}

	unless ( can_cc() ) {
		print "We can't locate a C compiler from your Config.pm.\n";
		exit(0);
	}
}

my $cc = ExtUtils::CChecker->new;

# We always use a static spatialite/sqlite compile

#####################################################################
# Prepare Compiler Options

my @CC_LIBS = ();
#push @CC_LIBS, "-lgeos_c -lproj";

$cc->find_libs_for(
  diag => "Spatialite libraries could not be found.  Please install Spatialite, or else specify where it can be found via the CC_LIBPATH and CC_INCPATH parameters.",
  libs => [ "","spatialite"],
  source => q[
    #include <stdlib.h>
	  #include <sqlite3.h>
	  #include <spatialite.h>
    int main(void)
    {
      (void) spatialite_initialize();
      return 0;
    }
  ]);
$cc->find_libs_for(
	diag => "GEOS libraries could not be found.  Please install GEOS, or else specify where it can be found via the CC_LIBPATH and CC_INCPATH parameters.",
  libs => [ "","geos_c","geos geos_c"],
  source => q[
    #include <stdlib.h>
	  #include <geos_c.h>
    int main(void)
    {
      (void) GEOSversion();
      return 0;
    }
  ]);
$cc->find_libs_for(
	diag => "PROJ6 libraries could not be found.  Please install PROJ6, or else specify where it can be found via the LDFLAGS and CCFLAGS parameters.",
  libs => [ "","proj"],
  source => q[
    #include <stdlib.h>
	  #include <proj.h>
    int main(void)
    {
      PJ *P;
      if (!(P = proj_create(PJ_DEFAULT_CTX, "+proj=merc +ellps=clrk66 +lat_ts=33")))
        exit(1);
      return 0;
    }
  ]);

$cc->find_libs_for(
	diag => "iconv is not available in libc, and can not be found. Please install iconv, or else specify where it can be found via the CC_LIBPATH and CC_IPATH parameters.",
  libs => [ "","iconv"],
  source => q[
    #include <stdlib.h>
	  #include <iconv.h>
    int main(void)
    {
      (void) iconv_open("", "");
      return 0;
    }
  ]);
push @CC_LIBS, @{$cc->extra_linker_flags};


my @CC_INC = (
	'-I.',
	'-I$(DBI_INSTARCH_DIR)',
);

my @CC_DEFINE = (
	'-DNDEBUG=1',
  "-DOMIT_FREEXL=1",
);
my @CC_FLAGS = (
	"-o \${*}.o",
  ($CCFLAGS ? ($CCFLAGS) : () ),
);
if ( $Config{d_usleep} || $Config{osname} =~ m/linux/ ) {
	push @CC_DEFINE, '-DHAVE_USLEEP=1';
}
unless ( $Config{usethreads} ) {
	push @CC_DEFINE, '-DTHREADSAFE=0';
}

my @CC_OPTIONS = (
  ($LDFLAGS ? (LDDLFLAGS    => $LDFLAGS) : () ),
	CCFLAGS      => join( ' ', @CC_FLAGS  ),
	INC          => join( ' ', @CC_INC    ),
	DEFINE       => join( ' ', @CC_DEFINE ),
	( @CC_LIBS ? (
		LIBS => join( ' ', @CC_LIBS )
	) : () ),
);




#####################################################################
# Find all C files
my @C_FILES = split(/\s/,"./dbdimp.c ./Spatialite.c");
my $O_FILES = split(/\s/,"./dbdimp.o ./Spatialite.o");
#my $LDFROM = "dbdimp.o  spatialite.o  Spatialite.o  sqlite3.o";
#####################################################################
# Hand off to ExtUtils::MakeMaker

WriteMakefile(
	NAME             => 'DBD::Spatialite',
	ABSTRACT         => 'Self Contained Spatialite Geo RDBMS in a DBI Driver',
	VERSION_FROM     => 'lib/DBD/Spatialite.pm',
	AUTHOR           => 'Lokkju Brennr <lokkju@cpan.org>',
		# Release manager (can this be an array?)
	PREREQ_PM        => {
		'File::Find'       => 0,
		'Tie::Hash'        => 0,
		'File::Spec'       => (WINLIKE ? '3.27' : '0.82'),
		'ExtUtils::CChecker'=>0,
		'DBI'              => $DBI_required,
		'Test::More'       => '0.42',
		( WINLIKE ? (
			'Win32' => '0.30',
		) : () ),
	},
	OPTIONAL( '6.48',
		MIN_PERL_VERSION => '5.006',
	),
	OPTIONAL( '6.31',
		LICENSE => 'perl',	
	),
	OPTIONAL( '6.46',
		# Use META_ADD instead of META_MERGE so that we can remove
		# any build-time dependencies that MakeMaker will put into
		# the requires field.
		META_ADD => {
			configure_requires => {
				'ExtUtils::MakeMaker' => '6.48',
				'ExtUtils::CChecker'  => 0,
				# This is not allowed to be computed
				'File::Spec'          => '0.82',
				'File::Find'          => 0,
				'DBI'                 => $DBI_required,
			},
			build_requires => {
				'File::Spec'          => (WINLIKE ? '3.27' : '0.82'),
				'Test::More'          => '0.42',
				# Bundled in /inc
				# 'Test::NoWarnings'  => '0.081',
			},
			requires => {
				'Tie::Hash' => 0,
				'DBI'       => $DBI_required,
				( WINLIKE ? (
					'Win32' => '0.30',
				) : () ),
			},
			resources => {
				license     => 'http://dev.perl.org/licenses/',
				bugtracker  => 'http://code.google.com/p/dbd-spatialite/issues/list',
				repository  => 'http://code.google.com/p/dbd-spatialite/',
			},
			no_index => {
				directory => [ qw{
					t inc util
				} ],
			}
		},
	),
	OPTIMIZE         => '-O2',
	clean            => {
		FILES => 'Spatialite.xsi config.h tv.log *.old *.o',
	},
	PL_FILES         => {},
	EXE_FILES        => [],
	C                => \@C_FILES,
	OBJECT           => ( '$(O_FILES)'),
	@CC_OPTIONS,
);

package MY;

use Config;
#use LWP::Simple;
use File::Path;
#use Archive::Zip;

sub postamble {
	require DBI;
	require DBI::DBD;
	eval {
		DBI::DBD::dbd_postamble(@_)
	};
}

sub libscan {
	my ($self, $path) = @_;
	return if $path =~ /\.pl$/;
	($path =~ m/\~$/) ? undef : $path;
}

sub test_via_harness {
	my ($self, $perl, $tests) = @_;
	if ( $^O eq 'hpux' and $Config{osvers} <= 10.20 ) {
		return qq{\tPERL_DL_NONLAZY=0 $perl "-MExtUtils::Command::MM" }
		     . qq{"-e" "test_harness(\$(TEST_VERBOSE), '\$(INST_LIB)', '\$(INST_ARCHLIB)')" $tests\n};
	} else {
		$self->SUPER::test_via_harness($perl, $tests);
	}
}

sub test_via_script {
	my ($self, $perl, $script) = @_;
	if ( $^O eq 'hpux' and $Config{osvers} <= 10.20 ) {
		return qq{\tPERL_DL_NONLAZY=0 $perl "-I\$(INST_LIB)" "-I\$(INST_ARCHLIB)" $script\n};
	} else {
		$self->SUPER::test_via_script($perl, $script);
	}
}
