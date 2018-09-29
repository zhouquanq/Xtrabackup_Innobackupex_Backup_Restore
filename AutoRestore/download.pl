#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use IO::File;
use IO::Dir;
use Date::Parse;
use POSIX qw{strftime};
use Net::FTP;
use File::Path;


$::APPLICATION_PATH = $FindBin::Bin;
sub usage {
	print( "usage: search.pl <operateName> <serverid> <time(yyyy-MM-dd HH:mm:ss)> <isservice(0 or 1)>\n");
	print( "example:\n");
	print( "    search.pl lywm 7 '2012-11-08 04:00:00'\n");
}

if( @ARGV != 4) {
	printf( "count:%s\n", scalar( @ARGV));
	usage();
	exit;
}
my ( $operateName, $serverid, $time) = @ARGV;
$time = Date::Parse::str2time( $time);

if( $ARGV[3]) {
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

my $cfg = {
	host=>'124.232.163.34',
	port=>21,
	user=>'gm_tools',
	pass=>'syxOzpz6CoBRGqUC2Frx',
	path=>'/home/gm_tools/GMAutoUpload',
	ispass=>1,
};

my $ftp;
my $trycount = 0;
while ( !$ftp && $trycount <= 5) {
	$trycount++;
	eval{
		$ftp = Net::FTP->new( $cfg->{host}, Port=>$cfg->{port}, Debug=>0, Passive=>$cfg->{ispass});
		$ftp->login( $cfg->{user}, $cfg->{pass});
	}
}
if( !$ftp ) {
	die( "connect ftp server error");
}

my $result = [];
my $targetdir = sprintf( "%s/%s_db/gs%s", $cfg->{path}, $operateName, $serverid);
$ftp->cwd( $targetdir);
my $dirlist = [$ftp->dir( )];
foreach my $file_( @{$dirlist}) {
	#printf( "%s\n", $file_);
	if( $file_ =~ /\b((\d+)_(full|inc)\.tar\.gz)/) {
		my $file = $1;
		my $timestamp = $2;
		my $type = $3;	
		my $filepath = sprintf( "%s/%s", $targetdir, $file);
		push( @{$result}, {
			timestamp=>$timestamp,
			type=>$type,
			path=>$filepath,
			name=>$file,
			dir=>$targetdir,
		});
	}
}

$result = [sort { $a->{timestamp} <=> $b->{timestamp}} @{$result}];
my $lastFullTime = 0;
my $lastTime = 0;
foreach my $file( @{ $result}) {
	if( $lastFullTime) {
		if( $file->{timestamp} > $time ) {
			if( $file->{timestamp} - $time < $time - $lastTime) {
				$lastTime = $file->{timestamp};
				if( $file->{type} eq 'full') {
        			$lastFullTime = $file->{timestamp};
    			}
			}
            last;
        }
		$lastTime = $file->{timestamp};
	}

	if( $file->{type} eq 'full') {
        $lastFullTime = $file->{timestamp};
		if( $file->{timestamp} > $time ) {
			$lastTime = $file->{timestamp};
		}
    }
}

my $rs = [];
if( !$lastTime || !$lastFullTime) {
	printf( "%s\n", "nothing find");
}
$rs = [grep { $_->{timestamp} >= $lastFullTime && $_->{timestamp} <= $lastTime} @{$result}];

my $localdir = sprintf( "%s/download", $::APPLICATION_PATH);
if( ! -e $localdir) {
	mkpath( $localdir);
}
my $fhld;
opendir( $fhld, $localdir);
my $localdirlist = {};
while( my $dir_ = readdir( $fhld)){
	$localdirlist->{$dir_} = 1;
}
closedir( $fhld);
$ftp->binary();
my $taskcount = scalar( @{$rs});
my $compcount = 0;
my $skipcount = 0;
foreach my $file ( @{$rs}) {
	my $localfile = sprintf( "%s/%s", $localdir, $file->{name});
	my $offect = 0;
	if( $localdirlist->{$file->{name}}) {
		my $remotesize = $ftp->size( $file->{path});
	    my( $localsize) = (stat($localfile))[7];
		if( $remotesize == $localsize) {
			print( "skiping $file->{name}\n");
			$skipcount++;
			next;
		}
		else {
			$offect = $localsize;
		}
	}
	$ftp->get( $file->{path}, $localfile, $offect);
	my $remotesize = $ftp->size( $file->{path});
	my( $localsize) = (stat($localfile))[7];
	if( $remotesize && $localsize && $remotesize == $localsize) {
		$compcount++;
		printf( "download %s success\n", $file->{path});
	} else {
		printf( "error download %s failure\n", $file->{path});
	}
}
printf( "taskcount:%s, compcount:%s skipcount:%s\n", $taskcount, $compcount, $skipcount);