#!/usr/bin/perl

package util;
use strict;
use warnings;
use Exporter;
use List::Util 'first';

our @ISA = 'Exporter';
our @EXPORT = qw($config_dir $config_file $base_dir $inst_dir $data_dir $exec_dir $exec $exp_name 
	$exp_dir $readme_name $data_name $readmefp $datafp $num_threads &trim &prompt &create_dir
	$cmd_file $inst_file @inst_list @task_list @task_labels %data &get_seed $write_func_name);

our ($config_dir, $config_file, $cmd_file);
our ($base_dir, $inst_dir, $inst_file, @inst_list, $data_dir, $exec_dir, $exec);
our ($exp_name, $exp_dir, $num_exp);
our $readme_name = 'README.ptest';
our $data_name = 'DATA.ptest';
our ($readmefp, $datafp);
our $num_threads = 1;
our (@task_list, @task_labels, %data);
our $write_func_name = "write_data_CSV";

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
