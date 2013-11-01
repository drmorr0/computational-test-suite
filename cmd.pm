#!/usr/bin/perl

# cmd.pm: David R. Morrison
#
# Module that actually pieces together the command line and runs the experiments.  The command line
# parser will have a number of substitution strings and other options that allow it to determine
# what the user wants.  I'm hoping to be able to find a way to extend these via hooks
#

use warnings;
use strict;
use util;

# each substitution needs
#  1) a regex to search for in the input string
#  2) a function that stores something in the @cmd_subs array (a scalar means it's inserted every
#     time, an array does one experiment with a different replacement from the array)
#  3) a string to display for help
# this can then be extended via a hook to add in custom substitutions

our %esc_chars = (
	's' => 'Insert a random seed',
	'i' => 'Insert the instance name',
	'%' => 'Insert a percent sign',
);

our @substitutions = (
	[ '%(.?)', \&percent_sub, '%. - escape characters' ],
	[ '-\[(.*)\]', \&flag_sub, '-[asdf] - run separate experiments with -a, -s, -d, -f' ],
	[ '\<(.*)\>', \&word_sub, '<word1|word2|word3> - run separate experiments with '. 
		'word1, word2, word3' ],
);

our @hook_help_strings = ();

our ($cmd_string, $internal_cmd_string, $num_tests_per, $label_string);
our @cmd_subs;

# Populate the @task_list array with all of the commands we're going to run (in however many
# duplicates we're doing them).  This array will then get parallelized.
sub setup_cmds 
{
	# process_hooks('pre_cmd');
	
	$cmd_string = ''; $label_string = ''; $num_tests_per = -1;
	# Read in a command from the specified command file
	if (-e "$config_dir/$cmd_file")
	{
		die "ERROR: $config_dir/$cmd_file is not readable!\n" unless 
			-r "$config_dir/$cmd_file";
		require "$config_dir/$cmd_file";
	}
	make_cmd($cmd_string);
	$label_string = 'job___ID__';  # TODO

	# This complicated bit of logic iteratively looks through the specified command string and
	# fills in all the different possible combinations of values.  It starts with the un-substituted
	# command and then substitutes in for __1__, __2__, etc. one at a time.  Each time it performs
	# a substitution, it adds the command back on to the @task_list.  The end result is a list of 
	# commands on the task list
	@task_list = ($internal_cmd_string);

	foreach my $i (0 .. @cmd_subs)
	{
		my $num_tasks = $#task_list;
		foreach (0 .. $num_tasks)
		{
			my $task_string = shift @task_list;
			my $sub_str = '__'.$i.'__';

			# If it's an array, add a value with each possibility from the array
			if (ref($cmd_subs[$i]) eq 'ARRAY')
			{
				foreach my $el (@{$cmd_subs[$i]})
				{
					my $new_task_string = $task_string;
					$new_task_string =~ s/$sub_str/$el/;
					push @task_list, $new_task_string;
				}
			}

			# Otherwise, just fill in one value
			else
			{
				$task_string =~ s/$sub_str/$cmd_subs[$i]/;
				push @task_list, $task_string;
			}
		}
	}

	# Fill in the instance names for each of the tasks
	foreach (0 .. $#task_list)
	{
		my $task_string = shift @task_list;
		if ($task_string =~ /__INSTANCE__/)
		{
			if (not @inst_list) 
				{ print "No instances available.  Aborting.\n"; exit; }

			foreach my $inst (@inst_list)
			{ 
				my $local_task_string = $task_string;
				$local_task_string =~ s|__INSTANCE__|$inst_dir/$inst|g; 
				push @task_list, $local_task_string;
			}
		}
	}

	# Fill in the random seeds and duplicates for each of the tasks
	my $id = 0;
	foreach (0 .. $#task_list)
	{
		my $task_string = shift @task_list;
		foreach (1 .. $num_tests_per)
		{
			if ($task_string =~ /__SEED__/)
			{
				my $local_task_string = $task_string;
				my $seed = get_seed();
				$local_task_string =~ s/__SEED__/$seed/g;
				push @task_list, $local_task_string;
			}
			my $label = $label_string; $label =~ s/__ID__/$id/g;  # TODO
			push @task_labels, $label;
			$id++;
		}
	}

	# At this point, any hooks can do further processing to the variables in the @task_list to
	# handle custom escape characters or other refinements of the commands.  The result at the very
	# end should be a list of commands that can be run as-is
	
	# process_hooks('post_cmd');

	if (prompt('This experiment will contain '. scalar @task_list .' tests.  Continue?') eq 'n') 
		{ exit; }
}

# Set up the initial command string, either from the command line or a file
sub make_cmd
{
	my $save_changes = 0;

	if ($cmd_string eq '')
	{
CMD_INPUT:
		print "Enter the command-line arguments to be passed to $exec (? for help, q to quit)\n";
		print "$exec ";
		$cmd_string = <STDIN>; trim $cmd_string;
		$save_changes = 1;

		if ($cmd_string eq '?') { print_help_string(); goto CMD_INPUT; }
		elsif ($cmd_string eq 'q') { exit; }
	}
	else
	{
		my $key = prompt("Using command string:\n  $exec $cmd_string.\nOk?", qw(y n q));
		if ($key eq 'n') { goto CMD_INPUT; }
		elsif ($key eq 'q') { exit; }
	}


	# Fill in markers using the user-provided processing functions.  The markers take the form __#__
	# in the $internal_cmd_string, and the entry in the @cmd_subs array specifies what one or more
	# values should be substituted for the markers.
	$internal_cmd_string = $cmd_string;

	my $ind = 0;
	my $marker = '__'.$ind.'__';
	foreach my $i (0 .. $#substitutions)
	{
		while ($internal_cmd_string =~ s/$substitutions[$i][0]/$marker/)
		{
			if (not $substitutions[$i][1]($1)) { goto CMD_INPUT; }
			$ind += 1; $marker = '__'.$ind.'__';
		}
	}

	# Figure out how many times to run each command
	if ($num_tests_per < 0)
	{
NUM_TESTS:
		print "How many tests to do for each instance? ";
		$num_tests_per = <STDIN>; trim $num_tests_per;
		$save_changes = 1;
		if (not ($num_tests_per =~ /\d+/ && $num_tests_per > 0)) 
			{ print "Invalid number.\n"; goto NUM_TESTS; }
	}
	else
	{
		my $key = prompt("Running $num_tests_per tests per instance.  Ok?", qw(y n q));
		if ($key eq 'n') { goto NUM_TESTS; }
		elsif ($key eq 'q') { exit; }
	}
	if ($save_changes) { save_cmd($cmd_string); }
}

# Print out a help string specifying what special command string values are parsed
sub print_help_string
{
	foreach (keys %esc_chars)
		{ print "  %$_ - $esc_chars{$_}\n"; }
	foreach my $i (1 .. $#substitutions)
		{ print "  $substitutions[$i][2]\n"; }
	foreach (@hook_help_strings) { print "  $_\n"; }
	print "\n";
}

# Default handlers - escape sequences, we accept %s (random seed), %i (instance), and %% (%)
sub percent_sub
{
	(print "Unrecognized escape sequence %$_[0].\n" and return 0) unless $_[0] ~~ %esc_chars;

	if ($_[0] eq 's') { push @cmd_subs, '__SEED__'; }
	if ($_[0] eq 'i') { push @cmd_subs, '__INSTANCE__'; }
	if ($_[0] eq '%') { push @cmd_subs, '%'; }

	return 1;
}

# Fill in with all possible (single-character) flags, specified in -[asdf]
sub flag_sub
{
	push(@cmd_subs, [ map {"-$_"} split('', $_[0]) ]);
	return 1;
}

# Replace <word1|word2> with word1, word2
sub word_sub
{
	push(@cmd_subs, [ split(/\|/, $_[0]) ]);
	return 1;
}

# Write the command string data to a file
sub save_cmd
{
	my $cmd_string = shift;
	if (prompt("Save command string?") eq 'n') { return; }

SAVE_CMD:
	print "Enter filename to save command string (default: $cmd_file): ";
	my $filename = <STDIN>; trim $filename;
	if ($filename eq '') { $filename = $cmd_file; }

	if (-e "$config_dir/$cmd_file" && 
		prompt("$config_dir/$cmd_file already exists.  Overwrite?") eq 'n')
		{ goto SAVE_CMD; }

	open CMD, ">$config_dir/$cmd_file" or 
		(print "Could not save $config_dir/$cmd_file ($!).\n" and goto SAVE_CMD);
	print CMD "\$cmd_string = \"$cmd_string\";\n";
	print CMD "\$num_tests_per = $num_tests_per;\n";
	print CMD "1;";
	close CMD;
}


1;
