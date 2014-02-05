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

sub run
{
	my $pl = Parallel::Loops->new($num_threads);
	my @local_data = ();
	$pl->share(\@local_data);

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
		my $id_length = length($#task_list) + 1;
		my $output_filename = sprintf("$output_metadata[$id]{'name'}.%0$id_length"."d.out", $id);
		
		open OUTPUT, ">>$exp_dir/$output_filename";
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
		my %from_json = parse_output($id, $output);

		my $inst_name = $output_metadata[$id]{'name'};
		my $inst_order = $output_metadata[$id]{'order'};
		push @local_data, [ ($inst_name, $inst_order, %from_json) ];

		# process_hooks('post_run');
	});

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

sub write_data_CSV
{
	my @instances = sort keys %data;
	my @columns = sort keys %{$data{$instances[0]}{0}};
	my @exps = keys $data{$instances[0]};
	my $max_exp_num = max(map { /^\d+$/ ? $_ : () } @exps);

	print $datafp "Instance, ";
	foreach my $col_name (@columns)
	{
		foreach my $i (0 .. $max_exp_num)
		{
			print $datafp "$col_name, ";
		}
	}
	print $datafp "\n";

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


