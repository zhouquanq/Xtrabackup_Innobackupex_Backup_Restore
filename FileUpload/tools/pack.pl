#! /opt/ActivePerl-5.14/bin/perl  -w

use strict;
use warnings;
use utf8;
use Data::Dump qw{ dump};
use File::Path;

BEGIN
{
	use FindBin;
	
	$::APPLICATION_PATH = scalar( $FindBin::Bin);
	chdir( $::APPLICATION_PATH);
}

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

my $appname = "FileUpload";
my $workspace = $::APPLICATION_PATH."/..";
print "svn update $workspace...\n";
print `svn update $workspace`;

my $date = "";
my $sv = `svnversion $workspace`;
$sv =~ s/\s//g;
print "get sv:$sv\n";

{
	my ($yday, $mon, $year) = (localtime( ))[3,4,5];
	$year += 1900;
	$mon += 1;
	$year = sprintf( "%04d", $year);
	$mon = sprintf( "%02d", $mon);
	$yday = sprintf( "%02d", $yday);
	$date = "$year-$mon-$yday";
}

# my $foldername;
(my $foldername = "$appname-$date-$sv") =~ s/[\\\/:\*\?"<>|]//g;
my $folderbasepath = $::APPLICATION_PATH."/building";
my $folderpath = "$folderbasepath/$foldername";
my $zipfilename = "$folderpath.zip";

if( !( -e $folderbasepath)) {
	# print `mkdir $folderbasepath -p`;
	File::Path::mkpath( $folderbasepath, 1, 0755);
	
}
if( -e $folderpath) {
	# print `rm $folderpath -rf`;
	File::Path::rmtree( $folderpath);
}

print "svn export $folderpath\n";
print `svn export $workspace $folderpath`;

print "create version.txt\n";
open( my $fhv, ">", sprintf( "%s/%s", $folderpath, "version.txt"));
print $fhv sprintf( "version:%s", $sv);
close( $fhv);

print $zipfilename."-----------\n";
if( -e $zipfilename) {
	# print `rm $zipfilename -f`;
	File::Path::rmtree( $zipfilename);
}
print "ziping...";

zipdir( $folderpath, $zipfilename, $foldername);
if( 'MSWin32' ne $^O) {
	zipdir( $folderpath, "/www/docs/pkgload.ly.ta.cn/package/${appname}.zip", "");
}

rmtree( $folderpath);

sub zipdir{
	my( $path, $zipfilename, $foldername) = @_;
	if( !( -e $path)) {
		warn( 'no such file or directory');
		return 0;
	}
	my $files = zipreaddir( $path, "");
	my $zip = Archive::Zip->new();
	
	for( @{$files}) {
		printf( "%s/%s\n", $path, $_);
		if( $foldername) {
			$zip->addFile( $path.'/'.$_, $foldername.'/'. $_);
		} else {
			$zip->addFile( $path.'/'.$_, $_);
		}
	}
	$zip->writeToFileNamed($zipfilename) == AZ_OK or die 'write error: $!';
}

sub zipreaddir{
	my( $path_, $prefix) = @_;
	if( !defined( $prefix)) {
		$prefix = "";
	}
	if( !( -e $path_)) {
		warn( 'no such file or directory');
		return [];
	}
	if( -f $path_) {
		warn( 'the '.$path_.' is a directory');
		return [];
	}
	
	my $result = [];
	my $fhLangdir;
	opendir( $fhLangdir, $path_) or die("not found the lang dir");
	while( my $line = readdir( $fhLangdir)) {
		if( ('.' eq $line) || ( '..' eq $line)) {
			next;
		}
		my $logicname = ( defined( $prefix) && ("" ne $prefix)) ? ($prefix.'/'.$line) : $line;
		my $realpath = $path_.'/'.$line;
		if( -f $path_.'/'.$line) {
			push( @{$result}, $logicname);
			next;
		}
		if( -d $path_.'/'.$line) {
			my $subresult = zipreaddir( $realpath, $logicname);
			push( @{$result}, @{$subresult});
			next;
		}
	}
	closedir( $fhLangdir);
	return $result;
}