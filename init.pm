#!/usr/bin/perl

# init.pm: David R. Morrison
#
# This is the first major component of my experiment-testing framework.  It handles all of the
# initialization stuff.  It first sets up all of the directories and paths (including the path to
# the executable, the directory we want data stored in, the location of the problem instances -- if
# they exist).  Then it creates the initial file structure (README file describing the experiments,
# DATA.csv file for outputting data, etc.)
#

use warnings;
use strict;

use Cwd;
use File::Basename;

use util;

sub initialize
{
	# process_hooks('pre_init');

	# First set up the configuration directory
	mkdir $config_dir unless -e $config_dir;
	die "ERROR: $config_dir is not readable!\n" unless -r $config_dir;
	die "ERROR: $config_dir is not writeable!\n" unless -w $config_dir;

	# Read in a configuration, if one exists already
	my $config_changed = 1;
	if (-e "$config_dir/$config_file") 
	{ 
		# The config file is just another perl file that fills in the appropriate values
		die "ERROR: $config_dir/$config_file is not readable!\n" unless 
			-r "$config_dir/$config_file";
		require "$config_dir/$config_file"; 
		$config_changed = 0; 					# The configuration doesn't need to be saved here
	}

	# Try to set up all the directories (print errors if unable)
	set_base_dir(); set_inst_dir(); set_data_dir(); set_exec();

	# Main initialization loop; ensure that everything is correct and saved before proceeding
	while (1)
	{
		print "\n1 - Working directory: $base_dir\n";
		print "2 - Instance directory: ". ($inst_dir eq '-1' ? 'None' : "$inst_dir")."\n";
		print "3 - Data directory: $data_dir\n";
		print "4 - Executable directory: $exec_dir\n";
		print "5 - Executable name: $exec_dir/$exec\n";
		print "6 - Number of threads: $num_threads\n";

		my @commands = qw(q 1 2 3 4 5 6);
		if ($base_dir ne '' && $inst_dir ne '' && $data_dir ne '' && $exec_dir ne '' && $exec ne '')
			{ unshift @commands, qw(y s); }
		else { $config_changed = 1; }
		my $key = prompt("Do these settings look correct?", @commands);

		# If we make modifications, record the configuration as changing
		if ($key =~ /[123456]/) { $config_changed = 1; }

		if    ($key eq 'y' && check_git()) { last; }
		elsif ($key eq 's' && check_git()) { $config_changed = 1; last; }
		elsif ($key eq 'q') { print "Quitting.\n"; exit; }
		elsif ($key eq '1') 
		{ 
			$base_dir = '<CUSTOM>'; 
			set_base_dir(); set_inst_dir(); set_data_dir(); set_exec();
		}
		elsif ($key eq '2') { $inst_dir = ''; set_inst_dir(); }
		elsif ($key eq '3') { $data_dir = ''; set_data_dir(); }
		elsif ($key eq '4') { $exec_dir = ''; set_exec(); }
		elsif ($key eq '5') { $exec = ''; set_exec(); }
		elsif ($key eq '6') { set_num_threads(); }
	} 

	chdir $base_dir;
	if ($config_changed) { save_init(); }

	while (1)
	{
		print "Enter a name for this experiment: ";
		$exp_name = <STDIN>; trim $exp_name;
		$exp_dir = "$data_dir/$exp_name"; 

		if (-e "$exp_dir")
		{
			my $key = prompt("An experiment with this name already exists.  Continue? ", 
				qw(y n q));
			if ($key eq 'y') { last; }
			elsif ($key eq 'q') { exit; }
		}
		else 
		{ 
			mkdir "$exp_dir" or (print "Could not create $exp_dir: $!\n" and next);
			last; 
		}
	}

	print "Enter a short description of this experiment: (Ctrl-D to end)\n";
	my $annotation = '';
	while (<>) { $annotation .= "  $_"; }
	print "\n";

	init_readme_and_data_files($annotation);

	load_instances();

	# process_hooks('post_init');
}

sub load_instances
{
	if ($inst_dir eq '-1') { return; }

	# Use double-braces to make last work
	if ($inst_file ne '')
	{
		open INST, "$inst_dir/$inst_file" or 
			(print "WARNING: could not open $inst_dir/$inst_file ($!).  ".
				"Running on all files in $inst_dir.\n" and $inst_file = '' and goto ALL_FILES);

		while (<INST>) 
		{ 
			my @inst_line = split /,/;
			push @inst_list, $inst_line[0];
			# TODO push @data, [ @inst_line[1 .. -1] ];
		}
		close INST;
	}

	else
	{
ALL_FILES:
		opendir INST_DIR, $inst_dir or 
			(print "Could not read directory $inst_dir ($!).  Aborting.\n" and exit);

		while (readdir INST_DIR)
		{
			next if (/^\./);
			my ($fn, $dir, $suf) = fileparse($_, qr/\.[^.]+/);
			push @inst_list, $fn;
		}
		closedir INST_DIR;
	}
}

sub init_readme_and_data_files
{
	my $annotation = shift;
	my $time = localtime;

	open $readmefp, ">>$exp_dir/$readme_name";
	print $readmefp "----------------------------------------------------------------------\n";
	print $readmefp "New experiment beginning on $time\n";
	print $readmefp "Experiment name: $exp_name\n";
	print $readmefp "Experiment description:\n$annotation\n\n";

	print $readmefp "Executable information:\n";
	print $readmefp "  path: $exec_dir/$exec\n";
	chdir $exec_dir; my $gitlog = `git log -1 2>&1`; chdir $base_dir;
	$gitlog =~ s/^/    /gm;
	print $readmefp "  git commit info: ";
	if ($gitlog =~ /^fatal/) { print $readmefp "(no git repository detected)\n"; }
	else { print $readmefp "\n$gitlog\n"; }
	print "\n";

	print $readmefp "Running on instances from $inst_dir\n";
	print $readmefp "Saving data to $exp_dir\n";
	print $readmefp "----------------------------------------------------------------------\n";

	open $datafp, ">>$exp_dir/$data_name";
}

# Write out the current configuration to a file
sub save_init
{
	if (prompt("Configuration has changed.  Save? ") eq 'n') { return; }

	# Be careful not to overwrite an existing configuration unless requested
SAVE_INIT:
	my $filename;
	print "Enter config file name (default: $config_file): ";
	$filename = <STDIN>; trim $filename;
	if ($filename eq '') { $filename = $config_file; }

	if (-e "$config_dir/$filename")
	{
		if (prompt("$config_dir/$filename already exists.  Overwrite? ") eq 'n') { goto SAVE_INIT; }
	}

	# Save the configuration
	print "Writing configuration to $config_dir/$filename\n";

	open CONFIG, ">$config_dir/$filename" or 
		(print "Could not save $config_dir/$filename ($!).\n" and goto SAVE_INIT);

	print CONFIG "\$base_dir = \"$base_dir\";\n";
	print CONFIG "\$inst_dir = \"$inst_dir\";\n";
	print CONFIG "\$data_dir = \"$data_dir\";\n";
	print CONFIG "\$exec_dir = \"$exec_dir\";\n";
	print CONFIG "\$exec = \"$exec\";\n";
	print CONFIG "\$num_threads = $num_threads;\n";
	print CONFIG "1;";

	close CONFIG;
}

sub set_base_dir
{
	if ($base_dir eq '') { $base_dir = getcwd(); }
	elsif ($base_dir eq '<CUSTOM>')
	{
		print "Enter working directory: ";
		$base_dir = <STDIN>; trim $base_dir;
	}
	if (!create_dir($base_dir)) 
		{ $base_dir = '<CUSTOM>'; return 0; }

	return 1;
}

sub set_inst_dir
{
	if ($inst_dir eq '')
	{
		print "Enter path to problem instances (-1 for none): "; 
		$inst_dir = <STDIN>; trim $inst_dir; 
	}

	if (not $inst_dir =~ /^(\/|-1)/) { $inst_dir = "$base_dir/$inst_dir"; }
	if ($inst_dir ne '-1' && not -e $inst_dir) 
		{ print "Instance directory $inst_dir does not exist\n"; $inst_dir = ''; return 0; }
	if ($inst_dir ne '-1' && not -r $inst_dir)
		{ print "Instance directory $inst_dir is not readable\n"; $inst_dir = ''; return 0; }

	return 1;
}

sub set_data_dir
{
	if ($data_dir eq '')
	{ 
		print "Enter path to data directory: "; 
		$data_dir = <STDIN>; trim $data_dir; 
	}

	if (not $data_dir =~ /^\//) { $data_dir = "$base_dir/$data_dir"; }
	if (!create_dir($data_dir)) { $data_dir = ''; return 0; }
	if (not -w $data_dir) 
		{ print "Cannot write to data dir $data_dir\n"; $data_dir = ''; return 0; }

	return 1;
}

sub set_exec
{
	if ($exec_dir eq '') 
	{ 
		print "Enter location of executable: "; 
		$exec_dir = <STDIN>; trim $exec_dir; 
	}
	if (not $exec_dir =~ /^\//) { $exec_dir = "$base_dir/$exec_dir"; }
	if (not -e $exec_dir)
		{ print "$exec_dir does not exist.\n"; $exec_dir = ''; return 0; }

	if ($exec eq '') 
	{ 
		print "Enter executable name: "; 
		$exec = <STDIN>; trim $exec; 
	}

	if (not -e "$exec_dir/$exec") 
		{ print "$exec_dir/$exec does not exist.\n"; $exec = ''; return 0; }
	elsif (not -x "$exec_dir/$exec")
		{ print "$exec_dir/$exec is not executable.\n"; $exec = ''; return 0; }


	return 1;
}

sub set_num_threads
{
	while (1)
	{
		print "Enter number of concurrent experiments to run: ";
		$num_threads = <STDIN>; trim $num_threads;

		if ($num_threads =~ /^\d+$/ && $num_threads != 0) { return; }
		else { print "Invalid entry.\n"; }
	}
}

sub check_git
{
	chdir $exec_dir;
	my $gitstatus = `git status -s 2>&1`;
	if ($gitstatus =~ /^fatal/)
	{
	   	my $key = prompt("\n**********\nWARNING: No git repository detected in $exec_dir.\n".
			"**********\n\nContinue? ", qw(y n q));
		if ($key eq 'n') { $exec_dir = ''; return 0; }
		elsif ($key eq 'q') { exit; }
	}
	else
	{
		print "\ngit repository status of $exec_dir:\n$gitstatus\n";
		if ($gitstatus =~ m/^ ?[AMDRCU]\s+/m)
		{
			my $key = prompt("\n**********\nERROR: Changes must be committed before experiments ".
				"begin.\n**********\n\nProceed? ", qw(y q));
			print "Commiting all changes.  Enter a commit message: ";
			my $message = <STDIN>; trim $message;
			if ($key eq 'q') { exit; }
			else { print `git commit -a -m \"$message\"`; }
		}
		elsif (prompt('Ok? ', qw(y q)) eq 'q') { exit; }
	}

	return 1;
}

1;
