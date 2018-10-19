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
use Net::FTP;
use MysqlX;
use Data::Dumper;
use JSON;
use Digest::MD5;
use LWP::UserAgent;

require 'srv.pl';
require 'common.pl';

our $g_app_path;
our $copy_count = 0;
our $makepath_count = 0;

my $g_continue;
my $WARN_LOCKCOUNT;

my %isneedcopybak;
my $last_full_time = {};
my $bak_flag ={};

eval{
	main();
};
log2("deadly wrong:".$@) if $@;

sub main
{
	$| = 1;
	$g_app_path = $FindBin::Bin;
	$g_continue = 1;

	my ($base_file) = ($0 =~ /(.*?)(\.[^\.]*)?$/);
	my $cfg_file = "$base_file.cfg";
	die "cfg file: '$cfg_file' not exists!" unless -e $cfg_file;

	while ($g_continue) {
		my $now = ts2str(time());
		log2("%%%%%%%%%%%%%%%% service start %%%%%%%%%%%%%%%%");

		my $cfg_ini = load_ini($cfg_file);
		
		my ($dbname, $server, $port, $passive, $username, $password, $ext, $filter_ext, $downpath, $ftp_from_dir, $workpath, $dbdatadir, $dbsrvname, $dstconinfo);
		foreach my $section(@{$cfg_ini}) {
			if ($section->{'name'} eq "restore") {
				$workpath = get_section_value($section, "workpath", "");		
				$dbdatadir = get_section_value($section, "dbdatadir", "");
				$dbsrvname = get_section_value($section, "dbsrvname", "");
				$dstconinfo = get_section_value($section, "dstconinfo", "");
			}
			if ($section->{'name'} eq "ftp") {
				#use_ftp 1-使用ftp拷贝文件, 0-cp命令拷贝文件
				$use_ftp = get_section_value($section, "use_ftp", "");		
				$server = get_section_value($section, "server", "");		
				$port = get_section_value($section, "port", "");
				$passive = get_section_value($section, "passive", "");
				$username = get_section_value($section, "username", "");
				$password = get_section_value($section, "password", "");
				$ext = get_section_value($section, "ext", "");
				$filter_ext = get_section_value($section, "filter_ext", "");
				$downpath = get_section_value($section, "ftp_to_dir", "");
			}
		}
		
		#扩展名trim
		my $exts;
		{
			my @tmp_exts = split(/,/, $ext);
			for (@tmp_exts)
			{
				my $e = $_;
				$e =~ s/^\s+//;
				$e =~ s/\s+$//;

				$exts->{lc($e)} = 1;
			}
		}
		
		foreach my $section (@{$cfg_ini}) {
			my $dbname_base = $section->{'name'};
			next unless $dbname_base;
			next if $dbname_base eq "restore" || $dbname_base eq "ftp";
			if ($dbname_base ne "restore" && $dbname_base ne "ftp" ) {
				my $ftp_from_base = get_section_value($section, "ftp_from_base", "");
				my $srcdb = get_section_value($section, "srcdb", "");
				my $posturl = get_section_value($section, "posturl", "");
				my $op = get_section_value($section, "op", "");
				my $startday = ts2str(time(), 1);
				my %srcdb = str2arr($srcdb);
				#从数据库查询该运营商需要分析日志的服务器
				my $conn = MysqlX::genConn(\%srcdb);
				my $db = new MysqlX($conn);
				my $sql = "
					SELECT * FROM needrunserver WHERE theday = '$startday' GROUP BY serverid
				";
				my $run_servers = [];
				push @{$run_servers},{'ftp_from_dir'=>$ftp_from_base."/ga",'dbname'=>$dbname_base."_ga"};
				my $servers = $db->fetchAll($sql);
				#对该运营商的每个服务器进行数据库还原(包括账号服)
				foreach (@{$servers}) {
					my $theday = $_->{'theday'};
					my $serverid = $_->{'serverid'};
					
					my $params = {
						'ftp_from_dir'	=>	$ftp_from_base."/gs".$serverid,
						'dbname'	=>	$dbname_base."_gs".$serverid,
					};
					push @{$run_servers},$params;
				}
				log2("---need run servers:\n".Dumper($run_servers));
				$db->__destruct();
				foreach (@{$run_servers}) {
												
						uninstall($cfg_file);
						log2("uninstall done!");
						install($cfg_file);
						log2("install done!");				
						
						my $dbname = $_->{dbname};
						my $ftp_from_dir = $_->{ftp_from_dir};
						
						my $servertype ='ga';
						if($ftp_from_dir =~ /(gs\d+)$/) 
						{
							$servertype = $1;
						}
						
						
						my $conn = MysqlX::genConn(\%srcdb);
						my $db = new MysqlX($conn);
						###################文件列表##################################
						#select distinct aab_bakid from admin_autobak where aab_servertype ='$servertype' order by aab_bakid
						my $sql = "select distinct aab_bakid from admin_autobak  where aab_servertype ='$servertype' order by aab_bakid";
						my $ids = $db->fetchAll($sql);
						$sql = "select * from admin_autobak  where aab_servertype ='ga' order by aab_bakid";
						my $filelist = $db->fetchAll($sql);
						$db->__destruct();
						foreach (@$ids){
							my $newest_full_time = 0;
							my $b_files = [];		#需要拷贝的db备份
							my $a_files = [];		#拷贝的db备份
							my $md5_file ={};		#文件的md5值
							my $id = $_->{'aab_bakid'};
							#my $sql = "select * from admin_autobak  where aab_servertype ='$servertype' and aab_bakid = $id";
							#my $filelist = $db->fetchAll($sql);
							foreach  (@{$filelist}){
								next if($_->{'aab_id'} != $id);
								my $filename  = $_->{'aab_filename'};
								my $md5  = $_->{'aab_md5'};
								$md5_file->{$filename} = $md5;
							}
							
							##############################文件拷贝####################################
							if($use_ftp) {
								log2("--------------------------------- ftp $ftp_from_dir start ---------------------------------");
								#创建FTP连接
								my $ftp = createFTP($server, $port, $passive, $username, $password);
								next unless $ftp;
								my @items = $ftp->ls($ftp_from_dir);
								
								############################################################
								foreach (@items) {
									next unless /(\d+)_full_$id\.tar\.gz$/;
									$newest_full_time = $1 if $1 > $newest_full_time;
								}
								foreach (@items) {
									next unless /((\d+)_(full|inc)_$id\.tar\.gz)$/;
									push @$b_files,$1 if $2 >= $newest_full_time;
								}
								print "b_files:\n".Dumper([sort(@$b_files)]);
								
								$copy_count = 0;
								
								rmtree($downpath);
								mkpath($downpath);
								print "downpath: $downpath\n";
								print "newest_full_time: $newest_full_time\n";
								my $ftp_start_time = ts2str(time);
								
								my $flag = 1;
								while ($flag) {
									if(!defined($ftp) || !$ftp) {
										$ftp->quit();
										$ftp = createFTP($server, $port, $passive, $username, $password);
										log2("reconnect ftp flag1\n");
									}
									ftp_down_file6($ftp, $ftp_from_dir, $downpath, $b_files, $md5_file);
									
									my $a_files = [sort(glob("$downpath/*gz"))];
									print "a_files:\n".Dumper($a_files);
									if(scalar(@{$b_files}) == scalar(@{$a_files})) {
										$flag = 0;
									} else {
										$ftp->quit();
										$ftp = createFTP($server, $port, $passive, $username, $password);
										log2("reconnect ftp flag2\n");
									}
								}
								
								$ftp->quit();					
								
								my $ftp_end_time = ts2str(time);
								log2("ftp Success,copied $copy_count files!");
								log2("ftp start_time:".$ftp_start_time);
								log2("ftp end_time:".$ftp_end_time);
								log2("--------------------------------- ftp $ftp_from_dir end ---------------------------------");
							}else
							{
								log2("--------------------------------- copy $ftp_from_dir start ---------------------------------");
								opendir DIR, $ftp_from_dir;
								my @items = readdir DIR;
								foreach (@items) {
									next unless /(\d+)_full_$id\.tar\.gz$/;
									$newest_full_time = $1 if $1 > $newest_full_time;
								}
								foreach (@items) {
									next unless /((\d+)_(full|inc)_$id\.tar\.gz)$/;
									push @$b_files,$1 if $2 >= $newest_full_time;
								}
								closedir DIR;
								print "b_files:\n".Dumper([sort(@$b_files)]);
								$copy_count = 0;
								
								rmtree($downpath);
								mkpath($downpath);
								print "downpath: $downpath\n";
								print "newest_full_time: $newest_full_time\n";
								foreach  my $file_name (@{$b_files}){
									my $sourcefile = $ftp_from_dir."/".$file_name;
									my $destinationfile = $downpath."/".$file_name;
									copy($sourcefile, $destinationfile);
									$copy_count++;
								}
								log2("copy Success,copied $copy_count files!");
								log2("--------------------------------- copy $ftp_from_dir end ---------------------------------");
							}
							##############################文件拷贝####################################
							
							
							log2("\n\n===========================Start restore $dbname ==============================");
							my $start_time = ts2str(time);
							if(!defined($last_full_time->{$dbname}->{$id})) {
									$last_full_time->{$dbname}->{$id} =0;
							}
							if(!defined($bak_flag->{$dbname})) {
									$bak_flag->{$dbname} =1;
							}
							my $before_full_time = $last_full_time->{$dbname}->{$id};
							my $restore_return = dbrebuild($downpath, $workpath, $dbdatadir, $dbsrvname, $dbname, $id);	
							my $end_time = ts2str(time);
							
							log2("dbrebuild param-----\n downpath:$downpath\n workpath:$workpath\n dbdatadir:$dbdatadir\n dbsrvname:$dbsrvname\n");
							log2("restore start_time:".$start_time);
							log2("restore end_time:".$end_time);
							log2("++++restore_return:\n".Dumper($restore_return));
							
							my %dstconinfo = str2arr($dstconinfo);
							my $dstconn = MysqlX::genConn(\%dstconinfo);
							my $dstcon = new MysqlX($dstconn);
							
							my $row;
							#还原时没有返回值,说明还原失败
							if(!defined($restore_return)) {
								$row = {
									db_name	=>	$dbname,
									reducible	=>	0,
									start_restore_time	=>	$start_time,
									end_restore_time	=>	$end_time,
								};
								log2("insert row: \n".Dumper($row));
								write_into_metable6('restore_info', $row, ['db_name'], $dstcon);					
								log2("===========================restored $dbname wrong ==============================");
								#调用工具更新后台接口完成auto_bak工具重启重新生成数据库备份
								my $after_full_time = $last_full_time->{$dbname}->{$id};
								if($bak_flag->{$dbname} || $after_full_time > $before_full_time){
									my $jsonResponse =  httpPort($posturl,$dbname,$op);
									if(!defined($jsonResponse))
									{
										$bak_flag->{$dbname} = 1;
										log2("===========================$dbname auto_bak restart post wrong ==============================");
									}else
									{
										$bak_flag->{$dbname} = 0;
										log2("===========================$dbname auto_bak restart post succ ==============================");
									}
								}
								
							} 
							else {
								my $isold = 0;
								my $last_ts;
								if($restore_return->{lastnewfile}) {
									($last_ts) = $restore_return->{lastnewfile} =~ /(\d+)/;
								} else {
									($last_ts) = $restore_return->{full_file} =~ /(\d+)/;
								}							
								log2("currenttime:".$end_time."  lasttime:".ts2str($last_ts));
								if(str2ts($end_time) - $last_ts > 7200) {
									log2("the last db file is too old");
									$isold = 1;
								}
								
								$row = {
									db_name	=>	$dbname,
									reducible	=>	1,
									last_full_file	=>	$restore_return->{full_file},					
									last_file_time	=>	ts2str($last_ts),
									isold	=>	$isold,
									start_restore_time	=>	$start_time,
									end_restore_time	=>	$end_time,
								};
								$row->{last_inc_file} = $restore_return->{lastnewfile} if defined $restore_return->{lastnewfile};
								log2("insert row: \n".Dumper($row));
								write_into_metable6('restore_info', $row, ['db_name'], $dstcon);
								$bak_flag->{$dbname} = 1;
								log2("===========================end restore $dbname ==============================");
								
							}
							sleep 60;
						}	
				}
			}
			sleep 3;
		}
				
		sleep(10);	
		log2("%%%%%%%%%%%%%%%% service end %%%%%%%%%%%%%%%%");
	}
}

sub dbrebuild
{
	my ($downpath, $workpath, $dbdatadir, $dbsrvname, $dbname, $id) = @_;
	
	$downpath =~ s/[\\\/]\s*$//;
	$workpath =~ s/[\\\/]\s*$//;
	$dbdatadir =~ s/[\\\/]\s*$//;

	if (!-d $workpath) {
		mkpath($workpath);
	}
	
	my $dbconfigfile = "/etc/$dbsrvname.cnf";
	my $processed_log = "$workpath/processed.log";
	my %processed_files = load_processed_files($processed_log);		
	
	my $full_file = undef;
	my $newest_full = 0;
	my @newfiles = ();
	my $lastnewfile = undef;
	
	if (opendir(DIR_SCAN, $downpath)) {
		my @files = sort(readdir DIR_SCAN);
		closedir DIR_SCAN;
	

		foreach my $filename(@files) {			
			if ($filename =~ /(\d+)_full_$id\.tar\.gz$/) {
				if ($1 > $newest_full) {					
					$full_file = $filename;
					$newest_full = $1;
					$last_full_time->{$dbname}->{$id} = $newest_full;
				}
			}
		}
		return unless $newest_full;
		foreach my $filename(@files) {
			if ($filename =~ /(\d+)_inc_$id\.tar\.gz$/ && !exists($processed_files{$filename})) {
				push @newfiles, $filename if $1 > $newest_full;
			}
		}
		$lastnewfile = [sort(@newfiles)]->[-1] if scalar(@newfiles) > 0;
		my $isfullprocessed = exists($processed_files{$full_file}) ? 1 : 0;
		
		log2("---newest_full:".Dumper($newest_full));
		log2("---newfiles:".Dumper([@newfiles]));
		my $targetfile = shift @newfiles;		
		while ($g_continue) {
			if ($isfullprocessed && defined($targetfile)) {				
				print "processing file: $targetfile\n";	
				my ($dirname) = $targetfile =~ /(\d+_inc_$id)/;

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
				
				rmtree($dbdatadir);
				mkpath($dbdatadir);
				return if logcmd("innobackupex --copy-back --defaults-file=$dbconfigfile $workpath/full");	

				return if logcmd("chown mysql:mysql $dbdatadir -R");

				return if logcmd("service $dbsrvname restart");
				
				#sleep(5);

				$isneedcopybak{$dbsrvname} = 0;
			} else {
				last;
			}
		}
	}
	my $return_value;
	if(defined($lastnewfile) || defined($full_file)) {
		$return_value = {lastnewfile => $lastnewfile,full_file=>$full_file};
	} else {
		$return_value = undef;
	}
	return $return_value;
	log2("++++return value:\n".Dumper($return_value));
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
	log2("---exc:$cmd	ret:".Dumper($ret));
	log2("Fail:$cmd") if ($ret);
	return $ret;
}

sub install
{
	my ($cfg_file) = @_;

	my $cfg_ini = load_ini($cfg_file);
	
	mkpath "/var/pid" unless -d "/var/pid";
	return if logcmd("chown mysql:mysql /var/pid -R");
	
	foreach my $section(@{$cfg_ini}) {
		if ($section->{'name'} eq "restore") {
			my $dbsrvname = get_section_value($section, "dbsrvname", "");
			my $dbdatadir = get_section_value($section, "dbdatadir", "");
			my $port	  = get_section_value($section, "port", "");
			$dbdatadir =~ s/\//\\\//g;
			
			diecmd("cp -f $g_app_path/mysql_template.cnf /etc/$dbsrvname.cnf");
			diecmd("perl -p -i -e \"s/{dbsrvname}/$dbsrvname/g\" /etc/$dbsrvname.cnf");			
			diecmd("perl -p -i -e \"s/{dbdatadir}/$dbdatadir/g\" /etc/$dbsrvname.cnf");
			diecmd("perl -p -i -e \"s/{port}/$port/g\" /etc/$dbsrvname.cnf");

			diecmd("cp -f $g_app_path/mysql_template.service /etc/rc.d/init.d/$dbsrvname");
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

sub createFTP {
	my ($server, $port, $passive, $username, $password) = @_;
	
	#FTP连接
	my $ftp = 0;
	my $tryCount = 3;
	while ($tryCount--) {
		$ftp = Net::FTP->new($server, Port => $port, Debug => 0, Passive => $passive, Timeout => 3600);
		
		if($ftp) {
			last;
		} else {
			sleep 10;
		}
	}
	if (!$ftp) {
		log2("connect to ftp error: $@");
		return;
	}
	#ftp登录
	my $b_logined = 0;
	$tryCount = 3;
	while ($tryCount--) {
		$b_logined = $ftp->login($username, $password);
		
		if($b_logined) {
			last;
		} else {
			sleep 10;
		}
	}
	if (!$b_logined) {
		log2("login to ftp($server) error: $@");
		return;
	}
	#ftp切换传输模式
	if (!$ftp->binary()) {
		log2("can't change ftp($server) mode to binary: $@");
		return;
	}
	return $ftp;
}

sub ftp_down_file6 {
	my ($ftp, $ftp_path, $download_path, $ftp_file_names, $md5_file) = @_;
	return unless defined($ftp) && $ftp;
	foreach my $file_name (@{$ftp_file_names}) {
		my $ftp_file = $ftp_path."/".$file_name;
		my $local_file = $download_path."/".$file_name;
		
		my $tmpfile = $local_file.".tmp";
		
		my $tmpfilesize;	
		if(-e $local_file) {
			print "file $local_file exists,next...\n";
			next;
		} elsif (-e $tmpfile) {
			$tmpfilesize = -s $tmpfile;
			if ($tmpfilesize < $ftp->size($ftp_file)) {
				if (!$ftp->get($ftp_file, $tmpfile, $tmpfilesize)) {
					log2("ftp get file $ftp_file error: $@");
					return;
				}
			}
		} else {
			#log2("-----------------------\nget $ftp_file...");
			if (!$ftp->get($ftp_file, $tmpfile)) {
					log2("ftp get file $ftp_file error: $@");
					return;
			}
		}

		#下载完整性检查	
		return unless -e $tmpfile;	
		$tmpfilesize = -s $tmpfile;
		unless (defined($tmpfilesize) && $tmpfilesize > 0) {
			return;
		}
		
		log2("local size:$tmpfilesize		remote size:".$ftp->size($ftp_file));
		if ($tmpfilesize == $ftp->size($ftp_file)) {
			move($tmpfile, $local_file);
			open FILE, "$local_file";
			binmode(FILE);
			my $ctx = Digest::MD5->new;
			$ctx->addfile (*FILE);
			my $local_md5 = $ctx->hexdigest;
			close (FILE);
			if(defined($md5_file->{$file_name})){
				my $source_md5 = $md5_file->{$file_name};
				if($source_md5 ne $local_md5){
					log2("download $file_name md5 is change:sorce is $source_md5,local is $local_md5");
					unlink $local_file;
					return;
				}
			}	
			$copy_count++;
		}
		elsif ($tmpfilesize > $ftp->size($ftp_file)) {
			log2("Delete too large tmpfile: $tmpfile");
			unlink $tmpfile;
		}
	}
}

$SIG{__WARN__} = sub{
	
	my ($text) = @_;
    my @loc = caller(0);
   	chomp($text);
   	
   	my $text_ = $text ? $text : "";
	log2('warn: '. $text_); 
	
	my $index = 1;
    for(@loc = caller($index); scalar(@loc); @loc = caller(++$index))
	{
		log2( sprintf( " callby %s(%s) %s", $loc[1], $loc[2], "$loc[3]")); 
	};
    return 1;
};

$SIG{__DIE__} = sub{
	
	my ($text) = @_;
    my @loc = caller(0);
   	chomp($text);

	my $text_ = $text ? $text : "";
	log2('error: '. $text_); 
	
	my $index = 1;
    for(@loc = caller($index); scalar(@loc); @loc = caller(++$index))
	{
		log2( sprintf( " callby %s(%s) %s", $loc[1], $loc[2], "$loc[3]")); 
	};
    return 1;
};

sub httpPort
{
	my ($posturl,$dbname,$op)= @_;
	my $sign =  "856c99c0fe02a78a";
	my $action = 'restart';
	my $ctx = Digest::MD5->new;
	my $server;
	my $type;
	if($dbname =~/ga/){
		$server = 'ga';
		$type ='GAT';
	}elsif($dbname =~/.*_(gs\d+)$/){
		$server = $1;
		$type ='GST';
	}
	my $hash ={};
    $hash->{op}= $op;
    $hash->{server}= $server;
    $hash->{type}= $type;
    $hash->{cmd}= "service GM_AutoBak restart";
	print "$posturl\n";
	my $request;
	my $response;
    my $jsonResponse;
	my $content;
	my $httpclient = new LWP::UserAgent();
	#$posturl =~ s/{__ACTION__}/$action/;
	my $json_text = to_json($hash,{ utf8  => 1 });
	my $data = "$sign$action$json_text";
	print "$data\n";
	$ctx->add($data);
	my $digest = $ctx->hexdigest;
	$posturl .= $digest;
	#post 数据
	print "$posturl\n";
	$request = HTTP::Request->new( "POST", $posturl);
	$request->content($json_text);
	my $iTryCount = 0;
	 my $bIsOk = 0;
	 while( !$bIsOk && $iTryCount < 5) {
		$iTryCount++;
 	   	eval
  	  	{
    	 $response = $httpclient->request( $request);
   	     if(!$response->is_success) 
     	   {
				die( $!);
		   }
   		 };
  	  	if($@)
   		 {
    	    print "report error:$@\n";
    	    $bIsOk = 0;
    	    next;
   		 }
   	    $content = $response->content; 		
  	  	eval
   	 	{
   	  	   $jsonResponse = JSON->new->utf8->decode( $content);
   		 };
   		 if($@)
   	 	{
    	   print "json decode error:$@\n";
    	    $bIsOk = 0;
    	    next;
   		 }
    	if( "HASH" ne ref( $jsonResponse) || !$jsonResponse->{status} || !$jsonResponse->{code} || !$jsonResponse->{data}) 
   		 {
   	   	  print "getdata error:illegal json format";
      	  $bIsOk = 0;
      	  next;
   		 }
  	  $bIsOk = 1;
	 }

	if( !$bIsOk) {
		return undef;
	}
	return $jsonResponse;   
}