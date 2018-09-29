#! /opt/ActivePerl-5.14/bin/perl  -w

#########################################################################
#
# perl 环境 
# 版本 5.12
# 模块
#	cpan install PAR::Packer
#   cpan install DBI
#	cpan install DBD::mysql
#	cpan install Term::ANSIColor
#	cpan install Crypt::Blowfish
#	cpan install Digest::MD5
#	cpan install PerlIO::encoding
#
#########################################################################

use strict;
use warnings;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Path qw{mkpath};
BEGIN
{
	use FindBin;
	
	$::APPLICATION_PATH = scalar( $FindBin::Bin);
	chdir( $::APPLICATION_PATH);
}

#应用名称
$::appname = "FileUpload";
#perl根目录
$::perlhome = "/opt/ActivePerl-5.14";
#编译器所在目录
$::buildbinpath = $::perlhome."/site/bin/pp";
#编译后的文件名
$::targetfilename = $::APPLICATION_PATH."/../".$::appname;
my $workspace = $::APPLICATION_PATH."/..";
print "svn updating...\n";
print `svn update $workspace`;

my $date = "";
my $sv = `svnversion`;
print $sv;
$sv =~ s/\s//g;
print "=====\n";
{
	my ($sec, $min, $hour, $yday, $mon, $year) = localtime( );
	$year += 1900;
	$mon += 1;
	$year = sprintf( "%04d", $year);
	$mon = sprintf( "%02d", $mon);
	$yday = sprintf( "%02d", $yday);
	$hour = sprintf( "%02d", $hour);
	$min = sprintf( "%02d", $min);
	$sec = sprintf( "%02d", $sec);
	$date = "$year-$mon-$yday";
}

if( -e $::targetfilename) {
#	unlink( $::targetfilename);
}

print "perl building...\n";
print `$::buildbinpath -g -f Crypto -F Crypto -I .. -M Filter::Crypto::Decrypt -o $::targetfilename ../ftp_load.pl`;

if( ! -e $::targetfilename) {
	die( "building failed...");
}

print "ziping...\n";
#read files
my $files = [ $::appname, 'config.ini.ga.example', 'config.ini.gs.example'];
my $fhLangdir;

if( ! -e $::APPLICATION_PATH."/building/") {
	mkdir( $::APPLICATION_PATH."/building/", 0755);
}
my $zip = Archive::Zip->new();
my $upzip = Archive::Zip->new();

my $filename = "$::appname-${date}-$sv";
my $name = "$::APPLICATION_PATH/building/$filename.zip";
for( @{$files}) {
print "$::APPLICATION_PATH/$_\n";
    $zip->addFile( "$::APPLICATION_PATH/../$_", "$filename/$_");
    $upzip->addFile( "$::APPLICATION_PATH/../$_", "$::appname/$_");
}
$zip->writeToFileNamed($name) == AZ_OK or die 'write error: $!';

my $uppath = "/www/docs/pkgload.ly.ta.cn/package/";
if( -e $uppath) {
	mkpath( $uppath);
}
$upzip->writeToFileNamed( sprintf( "%s/%s.zip", $uppath, $::appname)) == AZ_OK or die 'write error: $!';