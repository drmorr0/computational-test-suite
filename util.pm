#!/usr/bin/perl

package util;
use strict;
use warnings;
use Exporter;

our @ISA = 'Exporter';
our @EXPORT = qw($config_dir $config_file $base_dir $inst_dir $data_dir $exec_dir $exec $exp_name 
	$exp_dir $readme_name $readme $num_threads &trim &prompt &create_dir $cmd_file $inst_file
	@inst_list @task_list @data &get_seed);

our ($config_dir, $config_file, $cmd_file);
our ($base_dir, $inst_dir, $inst_file, @inst_list, $data_dir, $exec_dir, $exec);
our ($exp_name, $exp_dir, $num_exp);
our $readme_name = 'README';
our $readme;
our $num_threads = 1;
our (@task_list, @data);

sub trim
{
	$_[0] =~ s/^\s+//g;
	$_[0] =~ s/\s+$//g
}

sub prompt
{
	my ($query, @commands) = @_;
	@commands = qw(y n) unless @commands;

	my $key;
	while (1)
	{
		local $, = '/';
		print "$query ["; print @commands; print "] ";
		$key = <STDIN>; trim $key;
		if ($key ~~ @commands) { return $key; }
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
