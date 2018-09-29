#!/usr/bin/perl
BEGIN {
	use FindBin;
	my ($_parent_dir) = $FindBin::Bin =~ /(.*\/).*/;
	push(@INC, $FindBin::Bin, $_parent_dir);
}
use strict;
use warnings;

use File::Path;
use File::Copy;
use POSIX qw(strftime);
use MysqlX;
use Digest::MD5;

require 'srv.pl';
require 'common.pl';

our $g_app_path;
our $g_continue;

my $WARN_LOCKCOUNT;

my $g_lastime = 0;
my $g_lastinctime = {}; #最后一次增量备份时间
my $g_lastfulltime = 0; #最后一次全备份时间
my $g_restarted = 0;
my $g_weblasttime = 0;

main();
sub main 
{
	$| = 1;
	$g_app_path = $FindBin::Bin;
	$g_continue = 1;

	my ($base_file) = ($0 =~ /(.*?)(\.[^\.]*)?$/);
	my $cfg_file = "$base_file.cfg";
	die "cfg file: '$cfg_file' not exists!" unless -e $cfg_file;

	my $status_file = "$base_file.sta";
	if(!(-e $status_file)){
		open(F_STATUS, ">$status_file") or die "can't write status output file: $status_file";
		print F_STATUS time();
		close F_STATUS;
	}
	
	{
		my $cfg_ini = load_ini($cfg_file);
		my $dbbackfolder ="";
		foreach my $section(@{$cfg_ini}) {
			if ($section->{'name'} eq "mysql_inno_backup") {
				$dbbackfolder = get_section_value($section, "dbackupath", "");
				if($dbbackfolder eq '/' || $dbbackfolder eq '\\')
				{
					die "dbackupath error!\n";
				}	
				my $cmd = "rm $dbbackfolder/* -rf";
				diecmd($cmd);
			}	
		}	
		
			
	}
	while ($g_continue) {
		my $now = ts2str(time());
		
		my ($fullback_interval,$backfile_srcdb);#多备份时间间隔(大于单次全备份的时间才有效)和备份文件的数据库存储
		
		my $cfg_ini = load_ini($cfg_file);

		foreach my $section(@{$cfg_ini}) {
			if ($section->{'name'} eq "mysql_backup_info") {
				$fullback_interval = get_section_value($section, "fullback_interval", 1200);
				$backfile_srcdb = get_section_value($section, "backfile_srcdb", "");
				die "backfile_srcdb is null!\n" unless $backfile_srcdb;
			}
			elsif ($section->{'name'} eq "mysql_inno_backup") {
				my ($dbconfigfile, $dbackport, $dbackupath, $dbuser, $dbpass, $ftp_root, $interval, $cycle, $fullback_id, $servertype);	
				$dbconfigfile  = get_section_value($section, "dbconfigfile", "/etc/my.cnf");
				$dbackport = get_section_value($section, "dbackport", "3306");
				$dbackupath = get_section_value($section, "dbackupath", "");
				$dbuser  = get_section_value($section, "dbuser", "");
				$dbpass  = get_section_value($section, "dbpass", "");					
				$ftp_root = get_section_value($section, "ftp_root", "");
				$interval = get_section_value($section, "interval", 3600);
				$cycle = get_section_value($section, "cycle", 7);
				$fullback_id = get_section_value($section, "fullback_id", "");
				$servertype = get_section_value($section, "servertype", "");
				#保留之前的备份机制
				if($backfile_srcdb){
					die "cfg of fullback_id is null!\n" unless $fullback_id;
					die "cfg of servertype is null!\n" unless $servertype;
					if(!defined ($g_lastinctime->{$fullback_id})){
					$g_lastinctime->{$fullback_id} = 0;
					}
					dbackup2($dbconfigfile, $dbackport, $dbackupath, $dbuser, $dbpass, $ftp_root, $interval, $cycle, $fullback_id, $servertype, $fullback_interval, $backfile_srcdb);
				}else
				{
					dbackup($dbconfigfile, $dbackport, $dbackupath, $dbuser, $dbpass, $ftp_root, $interval, $cycle);
				}
				
			}
			elsif ($section->{'name'} eq "game_server_log") {
				my ($root, $ftp_root, $time, $delete);

				$root = get_section_value($section, "root", "");
				$ftp_root = get_section_value($section, "ftp_root", "");
				$time = get_section_value($section, "time");
				$delete = get_section_value($section, "delete", 0);

				log_backup($root, $ftp_root, $time, $delete);
			}
			elsif ($section->{'name'} eq "web_backup") {
				my ($web_path, $ftp_path, $web_dirs, $interval);
				
				$web_path  = get_section_value($section, "web_path", "");
				$ftp_path  = get_section_value($section, "ftp_path", "");
				$web_dirs  = get_section_value($section, "web_dirs", "");
				$interval  = get_section_value($section, "interval", "");
				
				&web_backup($web_path, $ftp_path, $web_dirs, $interval);
			}
		}

		open(F_STATUS, ">$status_file") or die "can't write status output file: $status_file";
		print F_STATUS time();
		close F_STATUS;
		
		print "now: $now Sleeping...\n";
		sleep(3);
	}
}

sub dbackup2
{
		my ($dbconfigfile, $dbackport, $dbackupath, $dbuser, $dbpass, $ftp_root, $interval, $cycle, $fullback_id, $servertype, $fullback_interval, $backfile_srcdb) = @_;		
		my $g_localtime = $g_lastinctime->{$fullback_id};
		if (time() - $g_localtime < $interval) {
			return;
		}
		
		$ftp_root =~ s/[\\\/]\s*$//;
		$dbackupath =~ s/[\\\/]\s*$//;
		
		#定期重打全备份
		if (-f "$dbackupath/fullbak.log") {
			open FH, "<$dbackupath/fullbak.log";
			my $fullbak_ts = <FH>;
			close FH;
			rmtree($dbackupath) if (time() - $fullbak_ts > 86400 * $cycle);
		}
		
		if (!-e $dbackupath) {
			mkpath($dbackupath, 0, 0755);	
		}

		if (!-e $ftp_root) {
			mkpath($ftp_root, 0, 0755);
			#defined(my $user = getpwnam 'gm_tools') or die 'bad user';
			#defined(my $group = getgrnam 'gm_tools') or die 'bad group';
			#chown $user, $group, $ftp_root;
		}

		my $cmd;	
		my %dstconinfo = str2arr($backfile_srcdb);
		my $conn = MysqlX::genConn(\%dstconinfo);
		my $db = new MysqlX($conn);
		
		if (!-d "$dbackupath/full") {						#full backup	
			if(time()-  $g_lastfulltime < $fullback_interval){
				return;
			}
			$cmd = "innobackupex --user=$dbuser --password=$dbpass --host=127.0.0.1 --port=$dbackport --no-lock --no-timestamp --defaults-file=$dbconfigfile $dbackupath/full";
			diecmd($cmd);
			
			my $full = time()."_full_$fullback_id";
			$cmd = "GZIP=\"-9\" tar -zcvf $dbackupath/$full.tar.gz -C $dbackupath full";
			diecmd($cmd);
			
			my $file_name="$dbackupath/$full.tar.gz";
			open FILE, "$file_name";
			binmode(FILE);
			my $ctx = Digest::MD5->new;
			$ctx->addfile (*FILE);
			my $md5 = $ctx->hexdigest;
			close (FILE);
			
			move("$dbackupath/$full.tar.gz", "$ftp_root/");

			open FH, ">$dbackupath/fullbak.log";
			print FH time();
			close FH;
			$g_lastfulltime = time();
		
			my $table ='admin_autobak';
			my $data ={
				'aab_servertype' =>$servertype,
				'aab_filename' =>"$full.tar.gz",
				'aab_bakid' =>$fullback_id,
				'aab_md5' =>$md5,
				};
			die "insert to db $full.tar.gz fail !" unless $db->insert($table,$data);
		}
		else {												#incremental backup
			my @files;
			if (opendir(DIR_SCAN, $dbackupath)) {
				@files = sort(readdir(DIR_SCAN));
				closedir DIR_SCAN;
			}

			my $lastinc = -1;			
			foreach my $filename(@files) {					#find last incremental backup
				if (-d "$dbackupath/$filename" && $filename =~ /(\d+)_inc/) {						
					if ($1 > $lastinc) {
						$lastinc = $1;							
					}
				}
			}
			
			if ($lastinc == -1) {							#first
				$lastinc = "full";
			} else {										#second, third, ...
				$lastinc = $lastinc."_inc_$fullback_id";					
			}

			my $nextinc = time()."_inc_$fullback_id";	

			$cmd = "innobackupex --user=$dbuser --password=$dbpass --host=127.0.0.1 --port=$dbackport --no-lock --no-timestamp --defaults-file=$dbconfigfile --incremental --incremental-basedir=$dbackupath/$lastinc $dbackupath/$nextinc";
			diecmd($cmd);

			$cmd = "GZIP=\"-9\" tar -zcvf $dbackupath/$nextinc.tar.gz -C $dbackupath $nextinc";
			diecmd($cmd);

			#计算文件的md5
			my $file_name="$dbackupath/$nextinc.tar.gz";
			open FILE, "$file_name";
			binmode(FILE);
			my $ctx = Digest::MD5->new;
			$ctx->addfile (*FILE);
			my $md5 = $ctx->hexdigest;
			close (FILE);
			
			move("$dbackupath/$nextinc.tar.gz", "$ftp_root/");
			#存入数据库
#			my $table ='admin_autobak';
#			my $data ={
#				'aab_servertype' =>$servertype,
#				'aab_filename' =>"$nextinc.tar.gz",
#				'aab_bakid' =>$fullback_id,
#				'aab_md5' =>$md5,
#				};
#			die "insert to db $nextinc.tar.gz fail !" unless $db->insert($table,$data);
			rmtree("$dbackupath/$lastinc") unless $lastinc eq 'full';
		}
		
		$g_lastinctime->{$fullback_id} = time();
}

sub dbackup
{
		my ($dbconfigfile, $dbackport, $dbackupath, $dbuser, $dbpass, $ftp_root, $interval, $cycle) = @_;		

		if (time() - $g_lastime < $interval) {
			return;
		}
		
		$ftp_root =~ s/[\\\/]\s*$//;
		$dbackupath =~ s/[\\\/]\s*$//;
		
		#定期重打全备份
		if (-f "$dbackupath/fullbak.log") {
			open FH, "<$dbackupath/fullbak.log";
			my $fullbak_ts = <FH>;
			close FH;
			rmtree($dbackupath) if (time() - $fullbak_ts > 86400 * $cycle);
		}
		
		if (!-e $dbackupath) {
			mkpath($dbackupath, 0, 0755);	
		}

		if (!-e $ftp_root) {
			mkpath($ftp_root, 0, 0755);
			#defined(my $user = getpwnam 'gm_tools') or die 'bad user';
			#defined(my $group = getgrnam 'gm_tools') or die 'bad group';
			#chown $user, $group, $ftp_root;
		}

		my $cmd;			
		
		if (!-d "$dbackupath/full") {						#full backup			
			$cmd = "innobackupex --user=$dbuser --password=$dbpass --host=127.0.0.1 --port=$dbackport --no-lock --no-timestamp --defaults-file=$dbconfigfile $dbackupath/full";
			diecmd($cmd);
			
			my $full = time().'_full';
			$cmd = "GZIP=\"-9\" tar -zcvf $dbackupath/$full.tar.gz -C $dbackupath full";
			diecmd($cmd);

			move("$dbackupath/$full.tar.gz", "$ftp_root/");

			open FH, ">$dbackupath/fullbak.log";
			print FH time();
			close FH;
		}
		else {												#incremental backup
			my @files;
			if (opendir(DIR_SCAN, $dbackupath)) {
				@files = sort(readdir(DIR_SCAN));
				closedir DIR_SCAN;
			}

			my $lastinc = -1;			
			foreach my $filename(@files) {					#find last incremental backup
				if (-d "$dbackupath/$filename" && $filename =~ /(\d+)_inc/) {						
					if ($1 > $lastinc) {
						$lastinc = $1;							
					}
				}
			}
			
			if ($lastinc == -1) {							#first
				$lastinc = "full";
			} else {										#second, third, ...
				$lastinc = $lastinc.'_inc';					
			}

			my $nextinc = time().'_inc';	

			$cmd = "innobackupex --user=$dbuser --password=$dbpass --host=127.0.0.1 --port=$dbackport --no-lock --no-timestamp --defaults-file=$dbconfigfile --incremental --incremental-basedir=$dbackupath/$lastinc $dbackupath/$nextinc";
			diecmd($cmd);

			$cmd = "GZIP=\"-9\" tar -zcvf $dbackupath/$nextinc.tar.gz -C $dbackupath $nextinc";
			diecmd($cmd);

			move("$dbackupath/$nextinc.tar.gz", "$ftp_root/");
			rmtree("$dbackupath/$lastinc") unless $lastinc eq 'full';
		}
		
		$g_lastime = time();
}


sub log_backup
{
	my ($root, $ftp_root, $time, $delete) = @_;

	$root =~ s/[\\\/]\s*$//;
	$ftp_root =~ s/[\\\/]\s*$//;
	if (!-e $ftp_root) {
		mkpath($ftp_root, 0, 0755);
	}

	my @files;
	opendir(DIR_SCAN, $root) or next;
	@files = sort(readdir(DIR_SCAN));
	closedir DIR_SCAN;
	
	my @bak_files;
	my $tmNow = time();

	foreach my $file(@files) {
		next if $file =~ /^\.\.?$/;
		my $filepath = "$root/$file";
		
		if (-d $filepath) {
			log_backup($filepath, $ftp_root, $time, $delete);
		} elsif (-f $filepath && $filepath =~ /server-(\d{4})-(\d{2})-(\d{2})-(\d{2})\.log$/i) {
			my $compressed_filename = "$1$2$3$4.lzo";
			my $compressed_tmpfilename = "$1$2$3$4.tmp";
			my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($filepath);
			if ($tmNow-$mtime>$time) {				
				my $cmd = "lzop -9 -f $filepath -o $ftp_root/$compressed_tmpfilename";
				if (0 == cmd($cmd)) {
					move("$ftp_root/$compressed_tmpfilename", "$ftp_root/$compressed_filename");
					push @bak_files, $filepath;
				} else {
					log2("Failed: $cmd")
				}
			}
			
		} 
=pod		
		elsif (-f $filepath && $filepath =~ /(\d{4})-(\d{2})-(\d{2})\.log$/i) {
			my $compressed_filename = "$1$2$3.lzo";
			my $compressed_tmpfilename = "$1$2$3.tmp";
			my $log_ts = str2time("$1-$2-$3 23:59:59");
			
			if ($tmNow-$log_ts>$time) {				
				my $cmd = "lzop -9 -f $filepath -o $ftp_root/$compressed_tmpfilename";
				if (0 == cmd($cmd)) {
					move("$ftp_root/$compressed_tmpfilename", "$ftp_root/$compressed_filename");
					push @bak_files, $filepath;
				} else {
					log2("Failed: $cmd")
				}
			}
		}
=cut		
	}

	if($delete) {
		for(@bak_files) {
			unlink($_);
		}
	}
}

sub web_backup {
	my ($web_path, $ftp_path, $web_dirs, $interval) = @_;
	
	$web_path =~ s/[\\\/]\s*$//;
	$ftp_path =~ s/[\\\/]\s*$//;
	if (!-e $ftp_path) {
		mkpath($ftp_path, 0, 0755);
	}
	
	my $tmNow = time();
	my $daystr = strftime("%Y%m%d", localtime(time));
	#print "tmNow:$tmNow		g_weblasttime:$g_weblasttime	interval:$interval\n";
	if($tmNow - $g_weblasttime > $interval) {
		my @web_dirs = split(',', $web_dirs);
		foreach my $web_dir (@web_dirs) {
			$web_dir =~ s/[\\\/]\s*$//;
			$web_dir =~ s/[\\\/]\s*$//;
			$web_dir =~ s/(^\s+|\s+$)//g;
			
			
			my $webfilename = $web_dir."_$daystr.tar.gz";
			my $tmp_webfilename = $webfilename.".tmp";
			my $cmd = "tar -zcvf $ftp_path/$tmp_webfilename -C $web_path $web_dir";
			if (0 == cmd($cmd)) {
				move("$ftp_path/$tmp_webfilename", "$ftp_path/$webfilename");
			} else {
				log2("Failed: $cmd")
			}
		}
		$g_weblasttime = time();
	}
}
################################################################################################################################
sub diecmd
{
	my ($cmd) = @_;
	print "$cmd\n";
	0 == system($cmd) or die("Fail:$cmd");
}
