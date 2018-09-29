#!/usr/bin/perl
BEGIN {
	use FindBin;
	my ($_parent_dir) = $FindBin::Bin =~ /(.*\/).*/;
	push(@INC, $FindBin::Bin, $_parent_dir);
}
use strict;
use warnings;
use File::Path;

require 'srv.pl';
require 'common.pl';

our $g_app_path;

my $g_continue;
my $WARN_LOCKCOUNT;

my %isneedcopybak;

main();
sub main
{
	$| = 1;
	$g_app_path = $FindBin::Bin;
	$g_continue = 1;

	my ($base_file) = ($0 =~ /(.*?)(\.[^\.]*)?$/);
	my $cfg_file = "$base_file.cfg";
	die "cfg file: '$cfg_file' not exists!" unless -e $cfg_file;

	my ($arg1) = @ARGV;
	if (defined($arg1) && $arg1 eq 'install') {
		install($cfg_file);
		return;
	} elsif (defined($arg1) && $arg1 eq 'uninstall') {
		uninstall($cfg_file);
		return;
	}

	my $status_file = "$base_file.sta";
			
	while ($g_continue) {
		my $now = ts2str(time());
		print "now: $now Sleeping...\n";

		my $cfg_ini = load_ini($cfg_file);

		foreach my $section(@{$cfg_ini}) {
			if ($section->{'name'} eq "restore") {
				dbrebuild($section);
			#	die "-----Done!------";
				sleep(10);
			}
		}

		open(F_STATUS, ">$status_file") or die "can't write status output file: $status_file";
		print F_STATUS time();
		close F_STATUS;
	}
}

sub dbrebuild
{
	my ($section) = @_;
	my $downpath = get_section_value($section, "downpath", "");
	my $workpath = get_section_value($section, "workpath", "");		
	my $dbdatadir = get_section_value($section, "dbdatadir", "");
	my $dbsrvname = get_section_value($section, "dbsrvname", "");
	
	$downpath =~ s/[\\\/]\s*$//;
	$workpath =~ s/[\\\/]\s*$//;
	$dbdatadir =~ s/[\\\/]\s*$//;

	if (!-d $workpath) {
		mkpath($workpath);
	}
	
	my $dbconfigfile = "/etc/$dbsrvname.cnf";
	my $processed_log = "$workpath/processed.log";
	my %processed_files = load_processed_files($processed_log);		

	if (opendir(DIR_SCAN, $downpath)) {
		my @files = sort(readdir DIR_SCAN);
		closedir DIR_SCAN;
		
		my $full_file = undef;
		my $newest_full = 0;
		my @newfiles = ();

		foreach my $filename(@files) {			
			if ($filename =~ /(\d+)_full\.tar\.gz$/) {
				if ($1 > $newest_full) {					
					$full_file = $filename;
					$newest_full = $1;
				}
			}
		}
		
		foreach my $filename(@files) {
			if ($filename =~ /(\d+)_inc\.tar\.gz$/ && !exists($processed_files{$filename})) {
				push @newfiles, $filename if $1 > $newest_full;
			}
		}
		
		my $isfullprocessed = exists($processed_files{$full_file}) ? 1 : 0;

		my $targetfile = shift @newfiles;		
		while ($g_continue) {
			if ($isfullprocessed && defined($targetfile)) {				
				print "processing file: $targetfile\n";	
				my ($dirname) = $targetfile =~ /(\d+_inc)/;

				return if logcmd("tar -zxvf $downpath/$targetfile -C $workpath");

				return if logcmd("innobackupex --defaults-file=$dbconfigfile --apply-log $workpath/full --incremental-dir=$workpath/$dirname");
								
				append_processed_files($processed_log, lc($targetfile));
				
				rmtree("$workpath/$dirname");
				$isneedcopybak{$dbsrvname} = 1;

				$targetfile = shift @newfiles;

			} elsif (0 == $isfullprocessed && defined($full_file)) {
				print "processing file: $full_file\n";	

				rmtree("$workpath/full");

				return if logcmd("tar -zxvf $downpath/$full_file -C $workpath");

				return if logcmd("innobackupex --defaults-file=$dbconfigfile --apply-log $workpath/full --redo-only");
				
				append_processed_files($processed_log, $full_file);

				$isneedcopybak{$dbsrvname} = 1;				
				$isfullprocessed = 1;

			} elsif ($isneedcopybak{$dbsrvname}) {				
				print "copying DB data. DB is going to restart!\n";	
				
				rmtree($dbdatadir.'_copying');
				mkpath($dbdatadir.'_copying');				
				my $dbcfg4copy = make_copying_cfgfile($dbconfigfile, $workpath);

				return if logcmd("innobackupex --copy-back --defaults-file=$dbcfg4copy $workpath/full");			
				
				return if logcmd("service $dbsrvname stop");
				rmtree($dbdatadir);
				rename($dbdatadir.'_copying', $dbdatadir);

				return if logcmd("chown mysql:mysql $dbdatadir -R");

				return if logcmd("service $dbsrvname start");
				
				#sleep(5);

				$isneedcopybak{$dbsrvname} = 0;
			} else {
				last;
			}			
		} #while ($g_continue)
	} #if (opendir(DIR_SCAN, $downpath))
}

sub make_copying_cfgfile
{
	my ($dbconfigfile, $workpath) = @_;

	my $dbcfg4copy = "$workpath/copy.cnf";

	if (!-e $dbcfg4copy) {
		open FH1, "<$dbconfigfile";
		open FH2, ">$dbcfg4copy";
		
		my $line;
		foreach $line(<FH1>) {
			if ($line =~ m/datadir/) {
				$line =~ s/(datadir\s*=\s*\S+)/$1_copying/;
			}
			print FH2 $line;
		}

		close FH2;
		close FH1;
	}

	return $dbcfg4copy;
}

sub diecmd
{
	my ($cmd) = @_;

	(0 == cmd($cmd)) or die("Fail:$cmd");
}

sub logcmd
{
	my ($cmd) = @_;
	my $ret = cmd($cmd);

	log2("Fail:$cmd") if ($ret);
	die("Fail:$cmd") if ($ret);

	return $ret
}

sub install
{
	my ($cfg_file) = @_;

	my $cfg_ini = load_ini($cfg_file);
	
	foreach my $section(@{$cfg_ini}) {
		if ($section->{'name'} eq "restore") {
			my $dbsrvname = get_section_value($section, "dbsrvname", "");
			my $dbdatadir = get_section_value($section, "dbdatadir", "");
			my $port	  = get_section_value($section, "port", "");
			$dbdatadir =~ s/\//\\\//g;

			diecmd("cp -f mysql_template.cnf /etc/$dbsrvname.cnf");
			diecmd("perl -p -i -e \"s/{dbsrvname}/$dbsrvname/g\" /etc/$dbsrvname.cnf");			
			diecmd("perl -p -i -e \"s/{dbdatadir}/$dbdatadir/g\" /etc/$dbsrvname.cnf");
			diecmd("perl -p -i -e \"s/{port}/$port/g\" /etc/$dbsrvname.cnf");

			diecmd("cp -f mysql_template.service /etc/rc.d/init.d/$dbsrvname");
			diecmd("perl -p -i -e \"s/{dbsrvname}/$dbsrvname/g\" /etc/rc.d/init.d/$dbsrvname");
			diecmd("chmod a+x /etc/rc.d/init.d/$dbsrvname");
		}
	}

	print "Install Done!\n";
}

sub uninstall
{
	my ($cfg_file) = @_;

	my $cfg_ini = load_ini($cfg_file);

	foreach my $section(@{$cfg_ini}) {
		if ($section->{'name'} eq "restore") {
			my $dbsrvname = get_section_value($section, "dbsrvname", "");
			my $dbdatadir = get_section_value($section, "dbdatadir", "");
			my $port	  = get_section_value($section, "port", "");
			my $workpath = get_section_value($section, "workpath", "");

			cmd("service $dbsrvname stop");			

			cmd("rm -f /var/log/mysql/$dbsrvname.log");
			cmd("rm -f /var/pid/$dbsrvname.pid");
			cmd("rm -f /tmp/$dbsrvname.sock");	
			
			cmd("rm -f /etc/$dbsrvname.cnf");
			cmd("rm -f /etc/rc.d/init.d/$dbsrvname");

			cmd("rm -rf $dbdatadir");
			cmd("rm -rf $workpath");
		}
	}

	print "Uninstall Done!\n";
}
