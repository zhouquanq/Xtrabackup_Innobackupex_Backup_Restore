#!/usr/bin/perl -w
use strict;
use warnings;
use utf8;
use File::Copy;

use Net::FTP;
use File::Find;
use File::Path qw{mkpath};
use File::Basename qw{basename};
use PerlIO::encoding;
use IO::File;
use bignum;

BEGIN{

	use FindBin;
	$::APPLICATION_PATH = $FindBin::Bin;
	
    $::APPLICATION_ISRUN = 1;
	# 防止意外关闭
	$SIG{HUP} = sub {};
	$SIG{INT} = sub { $::APPLICATION_ISRUN = 0;};
	$| = 1;
	
	$::param = {@ARGV};
	if( $::param->{'-srv'}) {
		my $pid = fork();
		if ( $pid < 0){
			die "fork: $!";
		}
		elsif ($pid){
			exit 0;
		}
	
		open(STDIN,  "</dev/null");
		open(STDOUT, ">/dev/null");
		open(STDERR, ">&STDOUT");
	}
	
	push( @INC, $::APPLICATION_PATH);
	chdir( $::APPLICATION_PATH);
}

use Lib::Util::Ini;
use Moby::Business::LoggerMan;
use Moby::Business::TimeMan;

$::manlist = {};
$::manlist->{timeMan} = Moby::Business::TimeMan->new();
$::manlist->{loggerMan} = Moby::Business::LoggerMan->new(
	timeMan=>$::manlist->{timeMan},
	apppath=>$::APPLICATION_PATH,
);

our $logger = $::manlist->{loggerMan}->getLogger();

$SIG{__WARN__} = sub{
	
	my ($text) = @_;
    my @loc = caller(0);
   	chomp($text);
   	
   	my $text_ = $text ? $text : "";
	$::logger->warn('warn: '. $text_); 
	
	my $index = 1;
    for(@loc = caller($index); scalar(@loc); @loc = caller(++$index))
	{
		$::logger->warn( sprintf( " callby %s(%s) %s", $loc[1], $loc[2], "$loc[3]")); 
	};
    return 1;
};

$SIG{__DIE__} = sub{
	
	my ($text) = @_;
    my @loc = caller(0);
   	chomp($text);

	my $text_ = $text ? $text : "";
	$::logger->warn('error: '. $text_); 
	
	my $index = 1;
    for(@loc = caller($index); scalar(@loc); @loc = caller(++$index))
	{
		$::logger->warn( sprintf( " callby %s(%s) %s", $loc[1], $loc[2], "$loc[3]")); 
	};
    return 1;
};

$::logger->info("=================== 服务器开启 ===================");

my $cfgfile = $::param->{'-c'} ? $::param->{'-c'} : sprintf( "%s/config.ini", $::APPLICATION_PATH);
if( ! -e $cfgfile) {
    die( "no such file ".$cfgfile);
}

my $obj = new Lib::Util::Ini;
my $appcfg = $obj->read( $cfgfile);
my $ftpupload = $appcfg->{upload};

#默认60秒执行一次
my $secondpretime = defined( $appcfg->{application}->{secondpretime}) ? $appcfg->{application}->{secondpretime} : 60;
our $recstatus = $::param->{'-fp'} ? $::param->{'-fp'} : $appcfg->{application}->{recstatus};
my $lastruntime = 0;
our @filelist;#要上传文件的列表
my $prev_file = undef;
my $fileupload_path = undef;

while( $::APPLICATION_ISRUN) {
    my $now = time;
        
    #runTick
    $::manlist->{timeMan}->runTick();
    $::manlist->{loggerMan}->runTick();
    if($now - $lastruntime > $secondpretime){
    	foreach my $fileuploadkey( keys %{$ftpupload}) {
    		my $remote_host = $ftpupload->{$fileuploadkey}->{"host"};
			my $user = $ftpupload->{$fileuploadkey}->{"user"};
			my $port = $ftpupload->{$fileuploadkey}->{"port"};
			my $password = $ftpupload->{$fileuploadkey}->{"pass"};
			my $remote_path = $ftpupload->{$fileuploadkey}->{"uploadpath"};
			my $local_path = $ftpupload->{$fileuploadkey}->{"datapath"};
			my $file_process = $ftpupload->{$fileuploadkey}->{"fileproces"};
			my $file_format = $ftpupload->{$fileuploadkey}->{"fileformat"};
            my $passive = $ftpupload->{$fileuploadkey}->{"passive"};
            my $filemove_path = $ftpupload->{$fileuploadkey}->{"filemove"};
            my $buffer = $ftpupload->{$fileuploadkey}->{"buffer"};

            if((!defined $file_process) || ($file_process ne "0" && $file_process ne "1")){
            	$file_process = "-1";
            	$::logger->info( "fileprocess is no process by $fileuploadkey");
			}
			
            statusReport();
            next if(defined $fileupload_path && $fileupload_path ne $remote_path);
	        ($prev_file, $fileupload_path) = &file_ftp($remote_host, $user, $password, $port, $remote_path, $local_path, $file_process, $file_format, $passive, $filemove_path, $buffer, $prev_file);

			if( !$::APPLICATION_ISRUN) {
	        	last;
	        }
	    }
        $lastruntime = time;
    }
    sleep(1);
}

$::logger->info("=================== 服务器停止 ===================");
$::manlist->{loggerMan}->shut();
$::manlist->{timeMan}->shut();

sub statusReport {
	if( $::recstatus) {
        if( open FILE, ">$::recstatus") {
	        print FILE time;
	        close FILE;
	    }
    }
}

sub file_ftp{
    my( $remote_host, $user, $password, $port, $remote_path, $local_path, $file_process, $file_format, $passive, $filemove_path, $buffer, $before_file, $fileuploadkey) = @_;
    $passive = $passive ? 1 : 0;
	$buffer = $buffer ? $buffer : 1024;
   
    # my $maxCount = 2;
    # sub function
	if(($before_file && $before_file =~ /.*\.$file_format$/) && ($remote_path && $remote_path eq $fileupload_path)){
		@::filelist = ();#initial数组
		push @::filelist, $before_file;
		$::logger->info("last upload file $before_file and filetype is $fileupload_path!");
		$prev_file = undef($prev_file);
		$fileupload_path = undef($fileupload_path);
	}else{
		my $findsub =  sub{
			if($File::Find::name =~ /.*\.$file_format$/){
				push (@::filelist, $File::Find::name);
			}
		};
		# get file list to be upload
		@::filelist = ();#initial数组
		find( $findsub, $local_path);
		printf( "file count:%s\n", scalar( @::filelist));
		if( !scalar( @::filelist)) {
			return;
		}
		
		@::filelist = sort @::filelist;
		@::filelist = splice( @::filelist, 0, 1);
	}
	
    # upload process
    my ($catch_file, $catch_filepath) = eval{
		#创建ftp对象
	    my $ftp = Net::FTP->new($remote_host, Port => $port, Passive => $passive, Timeout=>30);
		unless (defined $ftp){
			$::logger->info( "FTP connect false!");
			return;
		}
		#ftp登录
		unless($ftp->login($user, $password)) {
			$::logger->info( "login false!");
			$ftp->quit();
			return;
		}
		#ftp切换路径
		my $path = $ftp->cwd($remote_path), my $FTP_error=$ftp->message;
		if ( $FTP_error =~ /Failed/){
			$::logger->info( "mkdir $remote_path in ftp server");
			$ftp->mkdir( $remote_path, 1);#如果路径不存在，则创建
		}
		unless($ftp->cwd($remote_path)){
			$::logger->info( "path set false!");
			$ftp->quit();
			return;
		}

		$ftp->binary();#采用二进制模式传送
		my $svrfllist = $ftp->ls();#获取文件列表
		my $svrflmap = {map{ $_=>1} @{$svrfllist}};
		
		foreach my $file ( @::filelist) {
			my $filebasename = basename( $file);#得到文件名
			my $tmpfilename = sprintf( "%s.tmp", $filebasename);
			$::logger->info( "$file upload file");
			
			#上传文件前先检查文件是否存在如果存,则删除远程文件
			if( $svrflmap->{$filebasename}) {
				$ftp->delete( $filebasename);
				$::logger->info( "$file already exist and delete again upload");
			}

			my $fh = IO::File->new($file,'r');
			unless ($fh){
				$::logger->info("can not open file for read($!)");
				$ftp->quit();
				return;
			}
			$fh->binmode();

			if($svrflmap->{$tmpfilename}){#如果传送临时文件存在
				my $localsize = stat($file) ?(stat(_))[7]:(0);#本地文件大小
				my $ftpsize = $ftp->size($tmpfilename);#远程文件大小
				if(!defined $ftpsize){#判断远程文件返回值如果未定义 怎数据有问题
					$::logger->info("get remote server file false!");
					$fh->close;
					next;
				}
				if(!$ftpsize){#判断远程文件返回值大小为0,则删除远程临时文件
					$ftp->delete( $tmpfilename);
					$::logger->info("remote $tmpfilename size is 0");
					next;
				}
				
				if($ftpsize > $localsize){#如果远程断点文件大小本地本件，则文件有问题删除
					$ftp->delete( $tmpfilename);
					$::logger->info( "this Retransmission file $file is bad delete remains");
				}elsif($ftpsize < $localsize){#如果远程断点文件小于本地文件，则需要续传
					$::logger->info("start Retransmission file $file and info remote filesize $ftpsize local filesize $localsize");
					seek($fh, $ftpsize, 0);

					while(my $block_size = $fh->sysread(my $sFileBuf, 1024*$buffer)){
						my $partfh;
						open( $partfh, '<', \$sFileBuf);
						$ftp->append( $partfh, $tmpfilename);
						close( $partfh);
						
						my $uploadsize = $ftp->size($tmpfilename);
						if (!defined $uploadsize || !$uploadsize){#如果传送文件后返回回来数据未定义和大小为0则数据有问题
							$::logger->info("Control Connection off! last file $file");
							$fh->close;
							$ftp->quit();
							return ($file, $remote_path);
						}
						$::logger->info( sprintf( "transfer %u/%u $file", $uploadsize, $localsize));
					}
				}else{#如果相等
					if(1 == $ftp->rename( $tmpfilename, $filebasename)){
						$::logger->info( "$file Upload success!");
						if( $file_process eq "1") {
							unlink( $file);
							$::logger->info( "$file delete success!");
						}elsif( $file_process eq "0") {
							if( ! -e $filemove_path) {
								mkpath( $filemove_path, 0755);
							}
							move( $file,$filemove_path) || warn "$file move false $!";
							$::logger->info( "$file move success!");
						}
					}
				}
			}else{
				my $localsize = stat($file) ?(stat(_))[7]:(0);#本地文件大小
				$::logger->info("start upload file $file");

				while(my $block_size = $fh->sysread(my $sFileBuf, 1024*$buffer)){
					my $partfh;
					open( $partfh, '<', \$sFileBuf);
					$ftp->append( $partfh, $tmpfilename);
					close( $partfh);

					my $uploadsize = $ftp->size($tmpfilename);
					unless (defined $uploadsize){
						$::logger->info("Control Connection off! last file $file");
						$fh->close;
						$ftp->quit();
						return ($file, $remote_path);
					}
					$::logger->info( sprintf( "transfer %u/%u $file", $uploadsize, $localsize));
				}
				$::logger->info("end upload file $file");
			}
			$fh->close;
			statusReport();
		}
		$ftp->quit();
	};
	if( $@) {
		$::logger->info( "upload error $@");
	}
	return ($catch_file, $catch_filepath) if (defined $catch_file && defined $catch_filepath);
}
