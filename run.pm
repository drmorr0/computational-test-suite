#!/usr/bin/perl

# run.pm: David R. Morrison
#
# Module that runs all of the given experiments in the @task_list variable; the workhorse here is
# the data-processing functions, which parse the output from the command and store it in some
# format.  Currently I want to support LaTeX and CSV, but other formats could be added via hooks.

# You need to install the ParallelLoop module to use this.  To do this, run the following as root:
#   perl -MCPAN -e "install Parallel::Loops"
# Answer yes to all the defaults if this is your first time running

use util;

use Parallel::Loops;
use Fcntl qw(:DEFAULT :flock);
use List::Util qw(first);

sub run
{
	my $pl = Parallel::Loops->new($num_threads);
	my %local_data = ();
	$pl->share(\%local_data);

	$pl->foreach(\@task_list, sub
	{	
		# process_hooks('pre_run');

		my $cmd = $_;
		my $id = first { $task_list[$_] eq $cmd } 0..$#task_list;
		
		my $start_time = localtime;
		flock $readmefp, LOCK_EX;
		print $readmefp "[job $id] Starting `$exec $cmd` ($start_time)\n";
		flock $readmefp, LOCK_UN;

		flock STDOUT, LOCK_EX;
		print "Staring $id: $exec $cmd\n";
		flock STDOUT, LOCK_UN;

		my $output = `$exec_dir/$exec $cmd\n`;

		# Write the raw output to a file
		open OUTPUT, ">>$exp_dir/$task_labels[$id].out";
		flock OUTPUT, LOCK_EX;
		print OUTPUT "----------\n[job $id]: $exec $cmd\n----------\n";
		print OUTPUT $output;
		print OUTPUT "----------\n";
		flock OUTPUT, LOCK_UN;
		close OUTPUT;

		my $done_time = localtime;
		flock $readmefp, LOCK_EX;
		print $readmefp "[job $id] Finished `$exec $cmd` ($done_time)\n";
		flock $readmefp, LOCK_UN;

		# Store the processed data in the local array
		$local_data{$id} = [ parse_output($output) ];

		# process_hooks('post_run');
	});

	# Once all of the tasks are complete, we then dump the data into a hash indexed by label
	foreach my $id (sort keys %local_data)
	{
		print $local_data[$id][0];
		$data{$task_labels[$id]} = $local_data{$id};
	}

	&{$write_func_name}();
}

sub parse_output
{
	# process_hooks('pre_parse');
	return (1, 2, 3, 4);	
	# process_hooks('post_parse');
}

sub write_data_CSV
{
	foreach my $key (sort keys %data)
	{
		print $datafp "$key, ";
		foreach my $i (0 .. $#{$data{$key}})
			{ print $datafp "$data{$key}[$i], "; }
		print $datafp "\n";
	}
};



1;


