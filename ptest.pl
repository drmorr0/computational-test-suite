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

use Getopt::Std;

use init;
use cmd;
use run;
use cleanup;
use util;
use Cwd;

($base_dir, $inst_dir, $data_dir, $exec_dir, $exec) = ('', '', '', '', '');

my %args;
getopts('c:d:x:', \%args);
$config_file = $args{'c'} ? $args{'c'} : "config";
$config_dir = $args{'d'} ? $args{'d'} : ".ptest";
$cmd_file = $args{'x'} ? $args{'x'} : "command";

$inst_file = $ARGV[0] ? $ARGV[0] : '';
initialize($config_dir, $config_file);
setup_cmds();
run();
cleanup();

