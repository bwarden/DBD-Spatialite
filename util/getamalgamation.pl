use LWP::Simple;
use File::Path;
use Archive::Zip;

sub get_amalgamation {
        my ($dir_root,$site_root) = @_;
        my $download_file = "";
        # Download the Spatialite amalgamation if it isn't there, already.
        eval { mkpath($dir_root) };
        if ($@) {
                die "Couldn't create $dir_root: $@\n";
        }
        print "Downloading amalgation.\n";

        # find out what's current amalgamation ZIP file
        my $download_page = get($site_root . "/sources.html");
        if($download_page =~ /(libspatialite-amalgamation.*?\.zip)/) {
                $download_file = $1;
        } else {
                die "Couldn't find the amalgamation archive name.\n";
        }
        my $amalgamation_url = $site_root . "/" . $download_file;
        my $zip_dir = $download_file;
        $zip_dir =~ s/\.zip//;
        # and download it
        my $download_status = getstore($amalgamation_url, "tmp.zip");
        die "Error $download_status on $amalgamation_url" unless is_success($download_status);

        my $zf = Archive::Zip->new("tmp.zip");

        my @files = (
                "sqlite3.c",
                "headers/spatialite/sqlite3.h",
                "spatialite.c",
                "headers/spatialite/sqlite3ext.h",
                "headers/spatialite/spatialite.h",
                "headers/spatialite/gaiaaux.h",
                "headers/spatialite/gaiaexif.h",
                "headers/spatialite/gaiageo.h"
        );
        foreach(@files) {
                my $fn = $_;
                my ($lfn) = reverse(split(/\//,$fn,-1));
                my $afn = $zip_dir . "/" . $fn;
                print "Extracting " . $afn . "\n";
                $zf->extractMember($afn,$dir_root . '/' . $lfn);
        }
        unlink("tmp.zip")
}
get_amalgamation("../amalgamation/stable/","http://www.gaia-gis.it/spatialite");
get_amalgamation("../amalgamation/edge/","http://www.gaia-gis.it/spatialite-2.4.0-4");

