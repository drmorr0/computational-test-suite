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
use List::Util 'first';
use List::MoreUtils 'uniq';
use Set::CrossProduct;

# Users can extend the command substitution capabilities in two ways, first by adding a custom
# escape character and providing a function to handle it with the 'escape_chars' hook, or by
# providing a custom substitution string with a handling function.

# Escape characters are single characters followed by a percent sign
our %esc_chars = (
	's' => 'Insert a random seed',
	'i' => 'Insert the instance name',
	'%' => 'Insert a percent sign',
);

# Other possible substitutions need:
#  1) a regex to search for in the input string
#  2) a function that stores something in the @slots array (a scalar means it's inserted every
#     time, an array does one experiment with a different replacement from the array)
#  3) a string to display for help

our @substitutions = (
	[ '%(.?)', \&percent_sub, '%. - escape characters' ],
	[ '-\[(.*?)\]', \&flag_sub, '-[asdf] - run separate experiments with -a, -s, -d, -f' ],
	[ '\<(.*?)\>', \&word_sub, '<word1|word2|word3> - run separate experiments with '. 
		'word1, word2, word3' ],
);

# The array of values that get subtituted into the command string; the slot __i__ gets filled in
# with an element from $slot_values[$i].  If $slot_values[$i] is an array, we run a different
# experiment with each entry from the array
our $command;
our @slots = ( ['__DUMMY__'] );

sub setup_cmds 
{
	# process_hooks('pre_cmd');
	
	get_command();

	# The first step in parsing the command string is to replace all of the matched substitution
	# strings with slots of the form '__i__', where i is the slot number.  To do this, we simply
	# loop through all of the substitution strings and try to apply them as many times as possible.
	# Each time we apply one, we also call the appropriate function.  The function should return a
	# value or an array that we can fill into @slots
	my $slot_ind = 1;
	foreach my $subs_string (@substitutions)
	{
		my $subs_regex = $subs_string->[0];
		my $subs_func = $subs_string->[1];

		# The order of exploration from the substitution list means that earlier substitutions will
		# get expanded inside later groups.  So for instance, <x -[asdf]|y> will expand the -[asdf]
		# into <x __1__|y> before expanding the second one.  This behavior is both desired and a
		# little bit problematic (switching around to -[a<x|y>] will expand into 
		# -a, -<, -x, -|, -y, ->
		# We could write a full-recursive solution here, but I'm not sure it's worth the work right
		# now, nor am I sure it's the desired behavior.  I can come back to it later
		#
		while ($command =~ s/$subs_regex/__${slot_ind}__/)
		{
			$subs_func->($1) or die "Could not perform substitution for $1";
			$slot_ind++;
		}
	}

	# Next, we process all of the substitutions that should impact the output order for the data
	# table (currently, this is everything except the instance name and the random seed).
	my $combinations = Set::CrossProduct->new(\@slots);
	while (my $combination = $combinations->get)
	{
		my $task = $command;

		# We need to process in reverse because later slots could contain earlier slots inside them
		foreach my $slot_ind (reverse 0 .. $#{$combination})
			{ $task =~ s/__${slot_ind}__/$combination->[$slot_ind]/; }
		push @task_list, $task;
	}
	# 
	@task_list = uniq @task_list;

	# Each task needs a data output order which is independent of some substitutions (instance name
	# and seed by default).  Rather than storing this in a separate data structure and try to do
	# complicated lookups, we just prepend the order onto the task string before doing any
	# order-independent substitutions.  We also store the order in the data hash so it can be output
	my $i = 0;
	foreach my $task (@task_list)
	{
		$data{'order', $task} = $i;
		$task = '__ORDER_'.$i++."__ $task";
	}

	# Fill in each of the instance keys in the command strings
	@task_list = map { $_->[0] =~ s/__INST__/__INST_\{$_->[1]\}__/g; $_->[0] } 
		Set::CrossProduct->new([\@task_list, \@instances])->combinations;

	@task_list = (@task_list) x $num_tests_per;
	
	# Fill in random seeds (this is somewhat clunky, but it doesn't appear to work inside the
	# parallel loop... TODO)
	@task_list = map { my $seed = get_seed(); s/__SEED__/$seed/g; $_ } @task_list;

	# process_hooks('post_cmd');
}

# Read in the command string from the user
sub get_command
{
    my $save_changes = 0;

	$command = '';
	# Read in a command from the specified command file
	if (-e "$config_dir/$cmd_file")
	{
		print "Reading from $config_dir/$cmd_file...\n";
		require "$config_dir/$cmd_file" or die "Could not read $config_dir/$cmd_file ($!)";
	}

    if ($command eq '')
    {
CMD_INPUT:
        print "Enter the command-line arguments to be passed to $exec (? for help, q to quit)\n";
        print "$exec ";
        $command = <STDIN>; trim $command;
        $save_changes = 1;

        if ($command eq '?') { print_help_string(); goto CMD_INPUT; }
        elsif ($command eq 'q') { exit; }
    }
    else
    {
        my $key = prompt("Using command string:\n  $exec $command.\nOk?", qw(y n q));
        if ($key eq 'n') { goto CMD_INPUT; }
        elsif ($key eq 'q') { exit; }
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
    if ($save_changes) { save_cmd($command); }

	return $command;
}

# Print out a help string specifying what special command string values are parsed
sub print_help_string
{
	foreach (keys %esc_chars)
		{ print "  %$_ - $esc_chars{$_}\n"; }
	foreach my $i (1 .. $#substitutions)
		{ print "  $substitutions[$i][2]\n"; }
	print "\n";
}

# Default handlers - escape sequences, we accept %s (random seed), %i (instance), and %% (%)
sub percent_sub
{
	my $char = $_[0];
	(print "Unrecognized escape sequence %$char.\n" and return 0)
   		unless first { $_ eq $char } %esc_chars;

	if ($char eq 's') { push @slots, [ '__SEED__' ]; }
	if ($char eq 'i') { push @slots, [ '__INST__ ' ]; }
	if ($char eq '%') { push @slots, [ '%' ]; }

	return 1;
}

# Fill in with all possible (single-character) flags, specified in -[asdf]
sub flag_sub
{
	push(@slots, [ map {"-$_"} split('', $_[0]) ]);
	return 1;
}

# Replace <word1|word2> with word1, word2
sub word_sub
{
	push(@slots, [ split(/\|/, $_[0]) ]);
	return 1;
}

# Write the command string data to a file
sub save_cmd
{
	my $command = shift;
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
	print CMD "\$command = \"$command\";\n";
	print CMD "\$num_tests_per = $num_tests_per;\n";
	print CMD "1;";
	close CMD;
}


1;
