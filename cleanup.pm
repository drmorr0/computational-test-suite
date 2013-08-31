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
	close $readme;
}

1;
