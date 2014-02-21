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
use List::MoreUtils qw(uniq);
use JSON;
use Capture::Tiny 'capture';
use Data::Dumper;

sub run
{
	my $pl = Parallel::Loops->new($num_threads);
	$pl->share(\%data);

	# Run each command in parallel; dump the resulting data into the local_data array;
	# we'll sort it out after we're all done; since this is being done in parallel, we
	# have to lock output streams before we write to them
	$pl->foreach(\@task_list, sub
	{	
		my $task = $_;

		# Find the id of this command
		my $id = first { $task_list[$_] eq $task } 0..$#task_list;
		
		# process_hooks('pre_run', {'cmd' => $task});

		# Get the data order for this command
		/__ORDER_(\d+?)__ (.*)/ or die "Invalid command format";
		my $order = $1;
		$data{'task', $id, 'order'} = $order;
		my $cmd = $2;

		# Slot in the appropriate instance filename and random seed
		$cmd =~ s/__INST_\{(.*?)\}__/$data{'inst',$1,'filename'}/g;
		my $inst_name = $1;
		$data{'task', $id, 'instance'} = $inst_name;
		$data{'task', $id, 'seed'} = get_seed();
		$cmd =~ s/__SEED__/$data{'task', $id, 'seed'}/g;

		# Add an entry into the readme file
		my $start_time = localtime;
		flock $readmefp, LOCK_EX;
		print $readmefp "[job $id] Starting `$exec $cmd` ($start_time)\n";
		flock $readmefp, LOCK_UN;

		# Progress notification to STDOUT
		flock STDOUT, LOCK_EX;
		print "Starting task $id: $exec $cmd\n";
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
		my $id_length = length($#task_list);
		my $output_filename = sprintf("$inst_name.%0$id_length"."d.$out_extn", $id);
		
		open OUTPUT, ">>$exp_dir/$output_filename" or die("Could not write to
			$exp_dir/$output_filename\n");
		flock OUTPUT, LOCK_EX;
		print OUTPUT "----------\n";
		print OUTPUT "[job $id]: $exec $cmd\n";
		print OUTPUT '$data{\'task\','.$id.',\'instance\'} = '.$inst_name."\n";
		print OUTPUT '$data{\'task\','.$id.',\'order\'} = '.$order."\n";
		print OUTPUT '$data{\'task\','.$id.',\'seed\'} = '.$data{'task',$id,'seed'}."\n";
		print OUTPUT "----------\n";
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

		foreach my $key (keys %from_json)
			{ $data{'task',$id,$inst_name,$order,$key} = $from_json{$key}; }

		# process_hooks('post_run');
	});

	&{$write_func_name}();
}

sub parse
{
	open $datafp, ">$exp_dir/$data_name.$data_extn" or die("Could not open $exp_dir/$data_name.$data_extn for writing");
	opendir DATADIR, $exp_dir or die("Could not open $exp_dir for reading");
	my @datafiles = grep /.*\.$out_extn/, readdir DATADIR;
	my @column_headings;
	my $max_order_num = -1;
	foreach (@datafiles)
	{
		if (!/.*\.(\d+)\.$out_extn/) { die ("Invalid output file"); }
		my $job_id = $1;

		local $/;
		open DATAFILE, "$exp_dir/$_" or die "Could not open file $exp_dir/$_";
		my $output = <DATAFILE>;
		if (!($output =~ /output_metadata.*{'name'} = (.*)/)) 
			{ die "Invalid output file format"; }
		my $inst_name = $1;
		if (!($output =~ /output_metadata.*{'order'} = (\d+)/)) 
			{ die "Invalid output file format"; }
		my $order = $1;

		$output_metadata[$id] = { 'name' => $inst_name, 'order' => $order };

		my %from_json = parse_output($id, $output);
		$data{$inst_name}{$order} = { %from_json };
		push @column_headings, keys %from_json;
		if ($order > $max_order_num) { $max_order_num = $order; }
		close DATAFILE;
	}
	close DATADIR;
	@column_headings = uniq @column_headings;

	&{$write_func_name}($max_order_num, @column_headings);
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
	my @tasks = grep /task$;.*$;.*$;.*/, keys %data;
	my %columns;
	foreach (@tasks)
	{
		if (/task$;.*$;.*$;(.*)/)
			{ $columns{$1} = 1; }
	}	

	my @columns = sort keys %columns;
	my @order = sort { $data{$a} <=> $h{$b} } grep /order$;.*/, keys %data;

	# First, print out the order of the experiments
	foreach (@order)
	{
		if (/order$;(.*)/)
		{ 
			$clean = $1; 
			$clean =~ s/__INST__//g;
			$clean =~ s/__SEED__//g;
			trim $clean;
			foreach (1 .. $num_tests_per)
				{ print $datafp "$clean, "; }
		}
	}
	print $datafp "\n";

	# Next, write the column headings
	print $datafp "Instance, ";
	foreach my $col_name (@columns)
	{
		foreach my $i (0 .. $#order)
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

		if ($data{'inst', $instance, 'meta'})
			{ print $datafp $data{'inst', $instance, 'meta'}; }
		foreach my $column (@columns)
		{
			foreach my $i (0 .. $#order)
			{ 
				foreach my $key (grep /task$;\d+?$;$instance$;$i$;$column/, keys %data)
					{ print $datafp "$data{$key}, "; }
			}
		}

		print $datafp "\n";
	}
}



1;


