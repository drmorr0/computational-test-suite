#!/usr/bin/perl

# Here's a bunch of global variables and functions and things.  I think this is probably exceedingly
# poor Perl form, but I'm not sure what the better thing to do is, and I don't care right now.  This
# is where you'd find out information about what to hook into, but since hooks don't work right now
# and this might all change at a moment's notice, maybe it's better to just pretend this file
# doesn't exist... :)

package util;
use strict;
use warnings;
use Exporter;
use List::Util 'first';

our @ISA = 'Exporter';
our @EXPORT = qw($config_dir $config_file $base_dir $inst_dir $data_dir $exec_dir $exec $exp_name 
	$exp_dir $readme_name $data_name $readmefp $datafp $num_threads &trim &prompt &create_dir
	$cmd_file $inst_file @inst_list @task_list %data &get_seed $write_func_name
	$annotation $always_say_yes @output_metadata);

our ($config_dir, $config_file, $cmd_file);
our ($base_dir, $inst_dir, $inst_file, @inst_list, $data_dir, $exec_dir, $exec);
our ($exp_name, $exp_dir, $num_exp);
our $readme_name = 'README.cts';
our $data_name = 'DATA.cts';
our ($readmefp, $datafp);
our $num_threads = 1;
our (@task_list, %data);
our $write_func_name = "write_data_CSV";
our $annotation = '';
our $always_say_yes = 0;
our @output_metadata;

sub trim
{
	$_[0] =~ s/^\s+//g;
	$_[0] =~ s/\s+$//g
}

sub prompt
{
	my ($query, @commands) = @_;
	@commands = qw(y n) unless @commands;
	if ($always_say_yes && first {$_ eq 'y'} @commands)
		{ return 'y'; }

	my $key;
	while (1)
	{
		local $, = '/';
		print "$query ["; print @commands; print "] ";
		$key = <STDIN>; trim $key;
		if (first { $_ eq $key } @commands) { return $key; }
		else { print "Unrecognized command.\n"; }
	} 
}

sub create_dir
{
	my $dirname = shift;
	unless (-e $dirname)
	{
		if (prompt("$dirname does not exist.  Create? ") eq 'y')
			{ ( mkdir $dirname and return 1 ) or 
			  print "Could not create $dirname (Reason: $!)\n"; }
		
		return 0;
	}
	return 1;
}

sub get_seed
{
	return int(rand() * 100000000);
}

1;
