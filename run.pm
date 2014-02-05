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
use List::Util qw(first max);
use JSON;
use Capture::Tiny 'capture';

sub run
{
	my $pl = Parallel::Loops->new($num_threads);
	my @local_data = ();
	$pl->share(\@local_data);

	# Run each command in parallel; dump the resulting data into the local_data array;
	# we'll sort it out after we're all done; since this is being done in parallel, we
	# have to lock output streams before we write to them
	$pl->foreach(\@task_list, sub
	{	
		# process_hooks('pre_run');

		my $cmd = $_;

		# Find the id of this command
		my $id = first { $task_list[$_] eq $cmd } 0..$#task_list;
		
		# Add an entry into the readme file
		my $start_time = localtime;
		flock $readmefp, LOCK_EX;
		print $readmefp "[job $id] Starting `$exec $cmd` ($start_time)\n";
		flock $readmefp, LOCK_UN;

		# Progress notification to STDOUT
		flock STDOUT, LOCK_EX;
		print "Starting $id: $exec $cmd\n";
		flock STDOUT, LOCK_UN;

		# Run the command
		my ($output, $error, $status) = capture {system("$exec_dir/$exec $cmd")};

		my $exit_code = $status >> 8;
		my $signal = $status & 127;

		# Record any errors that appear
		if ($status != 0 || $error ne '')
		{
			flock STDOUT, LOCK_EX;
			print "\nWARNING: Job $id halted with exit code $exit_code, signal $signal\n";
			print "WARNING: Job $id error message:\n$error\n\n";
			flock STDOUT, LOCK_UN;
			my $error_time = localtime;
			flock README, LOCK_EX;
			print $readmefp "[job $id] halted with exit code $exit_code, ".
				"signal $signal ($error_time)\n";
			print $readmefp "[job $id] Error message: $error\n";
			flock README, LOCK_UN;
		}

		# Write the raw output to a file
		my $id_length = length($#task_list) + 1;
		my $output_filename = sprintf("$output_metadata[$id]{'name'}.%0$id_length"."d.out", $id);
		
		open OUTPUT, ">>$exp_dir/$output_filename";
		flock OUTPUT, LOCK_EX;
		print OUTPUT "----------\n[job $id]: $exec $cmd\n----------\n";
		print OUTPUT $output;
		print OUTPUT "----------\n";
		flock OUTPUT, LOCK_UN;
		close OUTPUT;

		# Add a second entry to the readme
		my $done_time = localtime;
		flock $readmefp, LOCK_EX;
		print $readmefp "[job $id] Finished `$exec $cmd` ($done_time)\n";
		flock $readmefp, LOCK_UN;

		# Look for data in a JSON format to parse
		my %from_json = parse_output($id, $output);

		# Store the processed data in the local array
		my $inst_name = $output_metadata[$id]{'name'};
		my $inst_order = $output_metadata[$id]{'order'};
		push @local_data, [ ($inst_name, $inst_order, %from_json) ];

		# process_hooks('post_run');
	});

	# Now we're not inside a parallel loop any more so we can dump the data into the data hash table
	# The structure of this table is complicated, and perhaps should be simplified in the future.
	# For right now, it's a 3D table.  The first dimension is indexed by instance name.  The second
	# dimension tells what order things should be written out in ('init' is always first, followed
	# by the numbers 0,...,max).  The third dimension is the headings gotten from the JSON output
	# from the program, and are interpreted as column headings
	foreach my $entry (@local_data)
	{
		($name, $order, %from_json) = @{$entry};
		$data{$name}{$order} = { %from_json };
	}

	&{$write_func_name}();
}

sub parse_output
{
	($id, $output) = @_;
	# process_hooks('pre_parse');
	
	my $order = $output_metadata[$id]{'order'};
	my $inst_name = $output_metadata[$id]{'name'};

	my @json = $output =~ /(?s)\bDATA_START\b(.*?)\bDATA_END\b/g;

	my $json_data;
	foreach (@json)
	{
		trim($_);
		$json_data = decode_json($_);
	}

	# process_hooks('post_parse');

	return %{$json_data};
}

# Write the data to a CSV file
sub write_data_CSV
{
	my @instances = sort keys %data;
	my @columns = sort keys %{$data{$instances[0]}{0}};
	my @exps = keys $data{$instances[0]};
	my $max_exp_num = max(map { /^\d+$/ ? $_ : () } @exps);

	# First write the column headings
	print $datafp "Instance, ";
	foreach my $col_name (@columns)
	{
		foreach my $i (0 .. $max_exp_num)
		{
			print $datafp "$col_name, ";
		}
	}
	print $datafp "\n";

	# Next write the data for each instance.  The high-level grouping is the column name,
	# and the low-level grouping is the imposed experiment order
	foreach my $instance (@instances)
	{
		print $datafp "$instance, ";
		foreach my $i (0 .. $#{$data{$instance}{'init'}})
			{ print $datafp "$data{$instance}{'init'}[$i], "; }
	
		foreach my $column (@columns)
		{
			foreach my $i (0 .. $max_exp_num)
			{
				print $datafp "$data{$instance}{$i}{$column}, ";
			}
		}
	
		print $datafp "\n";
	}
}



1;


