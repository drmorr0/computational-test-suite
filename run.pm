#!/usr/bin/perl

# run.pm: David R. Morrison
#
# Module that runs all of the given experiments in the @task_list variable; the workhorse here is
# the data-processing functions, which parse the output from the command and store it in some
# format.  Currently I want to support LaTeX and CSV, but other formats could be added via hooks.

# You need to install the ParallelLoop module to use this.  To do this, run the following as root:
#   perl -MCPAN -e "install Proc::ParallelLoop"
# Answer yes to all the defaults if this is your first time running

use util;

use Proc::ParallelLoop;
use Fcntl qw(:DEFAULT :flock);

sub run
{
	pareach [@task_list], sub
	{	
		# process_hooks('pre_run');

		my $cmd = shift;
		
		my $start_time = localtime;
		flock README, LOCK_EX;
		print README "[XXXX_ID] Starting `$exec $cmd` ($start_time)\n";
		flock README, LOCK_UN;

		my $output = `echo $exec_dir/$exec $cmd\n`;

		my $done_time = localtime;
		flock README, LOCK_EX;
		print README "[XXXX_ID] Finished `$exec $cmd` ($done_time)\n";
		flock README, LOCK_UN;

		# write $output to OUTPUT file

		# process data
		# write data to DATA file

		# process_hooks('post_run');
	}, {"Max_Workers" => $num_threads} ;
}


