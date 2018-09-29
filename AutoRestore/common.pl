use strict;
use File::Path;
use Time::Local;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use MysqlX;

our $g_app_path;

######################################################################
#获得工作进程运行状态
######################################################################
sub get_working_proc
{
	my ($connarg) = @_;

	my $conn = MysqlX::genConn($connarg);
	my $db = new MysqlX($conn);	
	my $sql = "SELECT * FROM proc_status";

	my $records = $db->fetchAll($sql);
	my %is_running = ();		
	foreach my $record (@$records) {
		my $process = $record->{'process'};
		$is_running{$process} = $record->{'is_running'};
	}

	return %is_running;
}

######################################################################
#检查渠道key对应的渠道id，如果找不到则插入新的渠道id
#$ppbid		hash ref  渠道id（键值为渠道key)的哈希引用
#$pbkey		hash ref  要检查的渠道key
#$connarg	hash ref  gameanalysis的连接参数
#返回此渠道key的渠道id
######################################################################
sub check_pbid
{
	my ($ppbid, $pbkey, $connarg) = @_;
	
	my $conn = MysqlX::genConn($connarg);
	my $db = new MysqlX($conn);

	if (defined($ppbid->{$pbkey})) {
		return $ppbid->{$pbkey};
	} else {
		$db->insert('pub', {'pubkey'=>$pbkey, 'pubname'=>$pbkey});
		$ppbid->{$pbkey} = $db->getLastInsertId();
		return $ppbid->{$pbkey};
	}
}

sub check_pbid6
{
	my ($ppbid, $pbkey, $db) = @_;
	
	#my $conn = MysqlX::genConn($connarg);
	#my $db = new MysqlX($conn);

	if (defined($ppbid->{$pbkey})) {
		return $ppbid->{$pbkey};
	} else {
		$db->insert('pub', {'pubkey'=>$pbkey, 'pubname'=>$pbkey});
		$ppbid->{$pbkey} = $db->getLastInsertId();
		return $ppbid->{$pbkey};
	}
}

######################################################################
#获取渠道key、ID对应
#$connarg	hash ref  gameanalysis的连接参数
#返回一个渠道key、ID的对应哈希
######################################################################
sub get_pubid_for_key
{
	my ($connarg) = @_;		

	my $conn = MysqlX::genConn($connarg);
	my $db = new MysqlX($conn);
	
	my %pubid = ();
	my $sql = "SELECT id, pubkey FROM pub";
	my $recordset = $db->fetchAll($sql);
	foreach my $record(@$recordset) {
		my $pubkey = $record->{'pubkey'};
		$pubid{$pubkey} = $record->{'id'};
	}

	return \%pubid;
}

sub get_pubid_for_key6
{
	my ($db) = @_;		

	#my $conn = MysqlX::genConn($connarg);
	#my $db = new MysqlX($conn);
	
	my %pubid = ();
	my $sql = "SELECT id, pubkey FROM pub";
	my $recordset = $db->fetchAll($sql);
	foreach my $record(@$recordset) {
		my $pubkey = $record->{'pubkey'};
		$pubid{$pubkey} = $record->{'id'};
	}

	return \%pubid;
}

######################################################################
#插入或修改记录，如果keyfield字段等于它们的值则更新记录，否则插入记录
#$table		string	  进行存储的表名
#$data		hash ref  数据
#$keyfield	array ref 主字段
#$connarg	hash ref  连接参数
######################################################################
sub write_into_metable
{
	my ($table, $data, $keyfield, $connarg) = @_;

	my %data_copy = %{$data};

	my %where = ();
	foreach (@{$keyfield}) {
		defined($data_copy{$_}) or die ("keyfield '$_' not in data!");
		$where{"$_ = ?"} = $data_copy{$_};
		print $table.'.'.$_.': '.$data_copy{$_}."\n";
	}

	my $conn = MysqlX::genConn($connarg);
	my $db = new MysqlX($conn);

	if (!defined($db->fetchRowByCond($table, \%where))) {
		$db->insert($table, \%data_copy);
	} else {
		foreach (@{$keyfield}) {
			delete $data_copy{$_};
		}
		$db->update($table, \%data_copy, \%where);
	}
	
	foreach (@{$keyfield}) {
		delete $data_copy{$_};
	}

	while (my ($fieldname, $value) = each %data_copy) {
		print $table.'.'.$fieldname.': '.$value."\n";
	}

	print "\n";
}

sub write_into_metable6
{
	my ($table, $data, $keyfield, $db) = @_;

	my %data_copy = %{$data};

	my %where = ();
	foreach (@{$keyfield}) {
		defined($data_copy{$_}) or die ("keyfield '$_' not in data!");
		$where{"$_ = ?"} = $data_copy{$_};
		print $table.'.'.$_.': '.$data_copy{$_}."\n";
	}

	#my $conn = MysqlX::genConn($connarg);
	#my $db = new MysqlX($conn);

	if (!defined($db->fetchRowByCond($table, \%where))) {
		$db->insert($table, \%data_copy);
	} else {
		foreach (@{$keyfield}) {
			delete $data_copy{$_};
		}
		$db->update($table, \%data_copy, \%where);
	}
	
	foreach (@{$keyfield}) {
		delete $data_copy{$_};
	}

	while (my ($fieldname, $value) = each %data_copy) {
		print $table.'.'.$fieldname.': '.$value."\n";
	}

	print "\n";
}

#有记录就更新,没记录跳过
sub update_into_metable
{
	my ($table, $data, $keyfield, $connarg) = @_;

	my %data_copy = %{$data};

	my %where = ();
	foreach (@{$keyfield}) {
		defined($data_copy{$_}) or die ("keyfield '$_' not in data!");
		$where{"$_ = ?"} = $data_copy{$_};
		print $table.'.'.$_.': '.$data_copy{$_}."\n";
	}

	my $conn = MysqlX::genConn($connarg);
	my $db = new MysqlX($conn);

	if (defined($db->fetchRowByCond($table, \%where))) {
		foreach (@{$keyfield}) {
			delete $data_copy{$_};
		}
		$db->update($table, \%data_copy, \%where);
	}
	
	foreach (@{$keyfield}) {
		delete $data_copy{$_};
	}

	while (my ($fieldname, $value) = each %data_copy) {
		print $table.'.'.$fieldname.': '.$value."\n";
	}

	print "\n";
}

sub update_into_metable6
{
	my ($table, $data, $keyfield, $db) = @_;

	my %data_copy = %{$data};

	my %where = ();
	foreach (@{$keyfield}) {
		defined($data_copy{$_}) or die ("keyfield '$_' not in data!");
		$where{"$_ = ?"} = $data_copy{$_};
		print $table.'.'.$_.': '.$data_copy{$_}."\n";
	}

	#my $conn = MysqlX::genConn($connarg);
	#my $db = new MysqlX($conn);

	if (defined($db->fetchRowByCond($table, \%where))) {
		foreach (@{$keyfield}) {
			delete $data_copy{$_};
		}
		$db->update($table, \%data_copy, \%where);
	}
	
	foreach (@{$keyfield}) {
		delete $data_copy{$_};
	}

	while (my ($fieldname, $value) = each %data_copy) {
		print $table.'.'.$fieldname.': '.$value."\n";
	}

	print "\n";
}

#有新记录就插入,没新记录跳过
sub insert_into_metable
{
	my ($table, $data, $keyfield, $connarg) = @_;

	my %data_copy = %{$data};

	my %where = ();
	foreach (@{$keyfield}) {
		defined($data_copy{$_}) or die ("keyfield '$_' not in data!");
		$where{"$_ = ?"} = $data_copy{$_};
		print $table.'.'.$_.': '.$data_copy{$_}."\n";
	}

	my $conn = MysqlX::genConn($connarg);
	my $db = new MysqlX($conn);

	if (!defined($db->fetchRowByCond($table, \%where))) {
		$db->insert($table, \%data_copy);
	}
	
	foreach (@{$keyfield}) {
		delete $data_copy{$_};
	}

	while (my ($fieldname, $value) = each %data_copy) {
		print $table.'.'.$fieldname.': '.$value."\n";
	}

	print "\n";
}

sub insert_into_metable6
{
	my ($table, $data, $keyfield, $db) = @_;

	my %data_copy = %{$data};

	my %where = ();
	foreach (@{$keyfield}) {
		defined($data_copy{$_}) or die ("keyfield '$_' not in data!");
		$where{"$_ = ?"} = $data_copy{$_};
		print $table.'.'.$_.': '.$data_copy{$_}."\n";
	}

	#my $conn = MysqlX::genConn($connarg);
	#my $db = new MysqlX($conn);

	if (!defined($db->fetchRowByCond($table, \%where))) {
		$db->insert($table, \%data_copy);
	}
	
	foreach (@{$keyfield}) {
		delete $data_copy{$_};
	}

	while (my ($fieldname, $value) = each %data_copy) {
		print $table.'.'.$fieldname.': '.$value."\n";
	}

	print "\n";
}

######################################################################
#过滤指定日期范围的日志行
#$logdir		string	  日志目录
#$startday		string	  开始日期
#$enday		    string	  结束日期
######################################################################
sub filter_log_lines
{
	my ($logdir, $startday, $enday) = @_;
	$enday = $startday if !defined($enday);

	my $tmpdir = "$g_app_path/temp";
	(-d $tmpdir ? rmtree($tmpdir) : unlink $tmpdir) if -e $tmpdir;
	mkdir($tmpdir);

	my @zipfiles = filter_log_zipfile($logdir, $startday, $enday);
	while (<@zipfiles>) {
			my $zip_obj = Archive::Zip->new($_);
			#print "--extracting: $_ ...\n";
			$zip_obj->extractTree('', "$tmpdir/");
	}

	opendir(DIR, $tmpdir) or die "Open dir $tmpdir failed!\n";
	my @logfiles = sort(readdir(DIR));
	closedir DIR;

    my @log_lines = ();
	while (<@logfiles>) {
		next unless $_ =~ /\.log/;
        open FH, "<$tmpdir/$_";
        print "Add log file: $_\n";
        push (@log_lines, <FH>);
        close FH;
	}
	rmtree($tmpdir);
		
	return \@log_lines;
}

######################################################################
#过滤指定日期范围的日志压缩文件
#$scandir		string	  扫描目录
#$startday		string	  开始日期
#$enday		    string	  结束日期
######################################################################
sub filter_log_zipfile {
	my ($scandir, $startday, $enday) = @_;
	
	my $starts = str2ts($startday);
	my $endts = str2ts($enday) + 86400;
	
	opendir(DIR_SCAN, $scandir) or die "Open dir $scandir failed!\n";
	my @allzips = reverse(readdir(DIR_SCAN));
	closedir DIR_SCAN;

	my @filelist = ();
	foreach my $zipfile(@allzips) {
		if ($zipfile =~ /game_server_log_\d+\.zip$/i) {
				my $zip_obj = Archive::Zip->new();
				if ($zip_obj->read("$scandir/$zipfile") ne AZ_OK ) {
					#print "read zip file failed $scandir/$zipfile! \n";
					next;
				}
				my @compress_logfiles = sort($zip_obj->memberNames());

				while (<@compress_logfiles>) {
					next unless $_ =~ /server-(\d{4})-(\d{2})-(\d{2})-(\d{2})\.log$/i;
					my $logtimestamp = timelocal(0, 0, $4, $3, $2 - 1, $1);
					if ($starts <= $logtimestamp && $logtimestamp < $endts) {
						push(@filelist, "$scandir/$zipfile");
					}
				}
		}
	}

	return @filelist;
}

########################################################################################################################################
#以下是比较底层的函数
sub log2
{
	my ($text) = @_;
	print "$text\n";
	my $time = ts2str(time());
	my $logfiletime = ts2str(time(),1);
	my ($basefile) = ($0 =~ /(.*?)(\.[^\.]*)?$/);
	my ($logfile) = $basefile."-".$logfiletime;
	$logfile .= '.log';
	
	open FH, ">>$logfile";
	binmode(FH, ":encoding(utf8)");
	print FH "[TIPS][$time] $text\n";
	close FH;
}

sub cmd
{
	my ($cmd) = @_;
	print "$cmd\n";
	return system($cmd);
}

sub str2arr
{
	my $str = shift(@_);
	if ($str =~ /\s*,\s*/) {
		return split(/\s*,\s*/, $str);
	} else {
		return ();
	}
}

sub str2ts
{
	my $str = shift(@_);
	
	if ($str !~ /\d{4}-\d+-\d+(\s+\d+:\d+:\d+)?/) {
		die ("Illegal datetime str($str).\n");
	}

	$str =~ s/(\d+)-(\d+)-(\d+)//;
	my ($year, $month, $day) = ($1, $2, $3);

	my ($hour, $minute, $second);
	if ($str =~ /(\d+):(\d+):(\d+)/) {
		($hour, $minute, $second) = split(':', $str);
	} else {
		($hour, $minute, $second) = (0, 0, 0);
	}
	
	my $timestamp = timelocal($second, $minute, $hour, $day, $month - 1, $year);

	return $timestamp;
}

sub ts2str
{
	my ($ts, $only_date) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
	$mon++;
	$year += 1900;
	
	$mon = '0'.$mon if $mon < 10;
	$mday = '0'.$mday if $mday < 10;
	$hour = '0'.$hour if $hour < 10;
	$min = '0'.$min if $min < 10;
	$sec = '0'.$sec if $sec < 10;
	
	if (defined($only_date) && 1 == $only_date) {
		return "$year-$mon-$mday";
	} else {
		return "$year-$mon-$mday $hour:$min:$sec";
	}
}

sub load_processed_files
{
	my ($logfile) = @_;
	my %processed_files;

	if (open(F_PROCESS, $logfile)) {
		while(<F_PROCESS>)
		{
			my $line = $_;
			next if $line =~ /^\s*$/;

			$line =~ s/^\s+//;
			$line =~ s/\s+$//;

			$processed_files{lc($line)} = 1;
		}
		close(F_PROCESS);
	}

	return %processed_files;
}

sub append_processed_files
{
	my ($logfile, $filename) = @_;
	open(F_OUT_PROCESS, ">>$logfile") or die "can't write $logfile";
	print F_OUT_PROCESS "$filename\n";
	close F_OUT_PROCESS;
}

sub load_ini
{
	my ($file) = @_;

    return load_ini_from_buffer(readin($file));
}

sub readin
{
    my ($file) = @_;

    my $len = -s $file;


    return "" unless $len > 0;

    my $f;
    open $f, $file;
    binmode $f;
    my $cont = "";
    sysread($f, $cont, $len);
    close $f;

    return $cont;
}

sub get_section_value
{
	my ($section, $key, $default_value) = @_;

	for (@{$section->{'kvs'}}) {
		my $kv = $_;

		if (lc($kv->{'key'}) eq lc($key)) {
			if (length($kv->{'value'})>0) {
				return $kv->{'value'};
			}

			return defined($default_value)?$default_value:"";
		}
	}

	return defined($default_value)?$default_value:"";
}

sub load_ini_from_buffer
{
    my ($buffer) = @_;

    my @lines = split(/\r?\n/, $buffer);

	my @ret;
	my $section_name = "";
	my $kvs;

	for(@lines)
	{
		my $line = $_;
		next if $line=~ /^\s*$/ or $line =~ /^\s*\#/;

		$line =~ s/^\s+//;
		$line =~ s/\s+$//;

		if ($line =~ /^\[([^\]]+)\]$/) {
			my $tmp_name = $1;
			$tmp_name =~ s/^\s+//;
			$tmp_name =~ s/\s+$//;

			if (length($section_name) > 0) {
				my %ini_info;
				$ini_info{'name'} = $section_name;
				$ini_info{'kvs'} = $kvs;

				push @ret, \%ini_info;
			}

			my @arKvs;
			$kvs = \@arKvs;
			$section_name = $tmp_name;
		}
		elsif ($line =~ /^([^=]+)=(.*)$/){
			my $key = $1;
			my $value = $2;

			$key =~ s/^\s+//;
			$key =~ s/\s+$//;

			$value =~ s/^\s+//;
			$value =~ s/\s+$//;

			if (length($section_name) > 0) {
				my %kv;
				$kv{'key'} = $key;
				$kv{'value'} = $value;

				push @{$kvs}, \%kv;
			}
		}
	}

	if (length($section_name) > 0) {
		my %ini_info;
		$ini_info{'name'} = $section_name;
		$ini_info{'kvs'} = $kvs;

		push @ret, \%ini_info;
	}

	return \@ret;
}

return 1;