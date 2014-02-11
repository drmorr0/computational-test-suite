#!/usr/bin/perl

# This is the core file for a suite of test scripts that are designed to be modular and easily
# extensible.  The goal is to minimize the amount of development time needed to get a new set of
# experiments running, because right now I do a lot of repeat work.  This script provides the
# following capabilities:
#
#   1) Initialization - create directory structure, determine types of experiments/how many
#      experiments to run, where to get input data, where to place output data, figure out whether
#      to append results to an existing set of experiments, etc.  Also determine if any experiments
#      should be run on a remote machine.
#   2) Run the experiments - for each test, construct the command line necessary to run the
#      experiment.  Determine whether to run experiments sequentially or on multiple cores.  Collect
#      the output and do something with it.
#   3) Parsing and cleanup - parse the output data into CSV, or LaTeX format (or other formats 
#      as desired).  Protect directory structure from writing so as to avoid accidentally
#      overwriting data.
#
# The goal is to eventually add in hooks so that I can also perform custom tasks at each stage of
# the process.  This way for each set of experiments I run, I can only focus on the parts of the
# experiment that differ or are unusual, rather than having to write or modify the entire thing from
# the ground up.
#

use warnings;
use strict;

use File::Basename;
use Getopt::Std;
use Cwd 'abs_path';

# Include the other modules in this directory regardless of where we run from
use lib dirname(abs_path(__FILE__));

use init;
use cmd;
use run;
use cleanup;
use util;

($base_dir, $inst_dir, $data_dir, $exec_dir, $exec) = ('', '', '', '', '');

# Parse command line args.  TODO make this nicer
my %args;
getopts('F:O:Pa:e:c:d:x:Yh', \%args);
if ($args{'h'}) { usage() and exit; }
if ($args{'F'}) { $out_extn = $args{'F'}; }
if ($args{'O'}) { $data_extn = $args{'O'}; }
$config_file = $args{'c'} ? $args{'c'} : "config";
$config_dir = $args{'d'} ? $args{'d'} : ".test";
$cmd_file = $args{'x'} ? $args{'x'} : "command";
$annotation = $args{'a'} ? $args{'a'} : '';
$exp_name = $args{'e'} ? $args{'e'} : '';
$always_say_yes = $args{'Y'};
my $parse_only = $args{'P'};

if ($parse_only)
{
	$exp_dir = $ARGV[0] ? $ARGV[0] : '';
	parse();
}
else
{
	$inst_file = $ARGV[0] ? $ARGV[0] : '';
	initialize($config_dir, $config_file);
	setup_cmds();
	run();
	cleanup();
}

sub usage
{
	my $exec = basename($0);
	print "usage: $exec -cdxh [instance_list]\n";
	print "\t-P: Call the data parsing module only\n";
	print "\t-D: Set the data/readme file extensions (default cts)\n";
	print "\t-O: Set the output file extensions (default out)\n";
	print "\t-c: Config file name (default config)\n";
	print "\t-d: Config file directory (default .ptest)\n";
	print "\t-x: Execution command file (default command)\n";
	print "\t-e: Experiment name\n";
	print "\t-a: Experiment annotation\n";
	print "\t-Y: always say yes to questions\n";
	print "\t-h: Display help message\n";
}




