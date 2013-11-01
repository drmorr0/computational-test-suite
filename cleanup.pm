#!/usr/bin/perl

# cleanup.pm: David R. Morrison
#
# This controls all of the necessary cleanup (closing filehandles and such) from the perl test suite
#

use strict;
use warnings;
use util;

sub cleanup
{
	my $time = localtime;
    print $readmefp "----------------------------------------------------------------------\n";
    print $readmefp "Experiment ended on $time\n";
    print $readmefp "Experiment name: $exp_name\n";
    print $readmefp "----------------------------------------------------------------------\n";

	close $readmefp;
	close $datafp;

	# Prevent accidental overwriting
	chdir $exp_dir;
	opendir DATADIR, ".";
	my @allfiles = grep !/(^\.\.?\z|.*\.pdf|.*\.aux|.*\.log)/, readdir DATADIR;
	closedir DATADIR;
	chmod 0400, @allfiles;
	chmod 0555, "$exp_dir";
	chdir $base_dir;
}

1;
