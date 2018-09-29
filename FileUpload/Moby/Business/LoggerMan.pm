use strict;
use warnings;
use utf8;

#############################################################
#
# 敏感字,用户修改游戏服务器敏感字库
#############################################################
package Moby::Business::LoggerMan;

use POSIX qw{strftime};
use File::Path qw{mkpath};
use Log::Log4perl;

sub new
{
	shift;
	my $this = bless {@_};
	if( !$this->{timeMan} || !$this->{apppath}) {
		die( "illegal construct param");
	}
	$this->init();
	return $this;
}

sub init{
	my ( $this) = @_;
	my $currdate = strftime( "%Y-%m-%d", localtime( $this->{timeMan}->{now}));
	if( !$this->{logger} || !$this->{logger_lastupdtime} || $this->{logger_lastupdtime} ne $currdate) {
		if( !$this->{logfilepath}) {
			$this->{logfilepath} = sprintf( "%s/logs", $this->{apppath});
			mkpath( $this->{logfilepath}, 0755);
		}
		my $confstr = q{
			layout_class = Log::Log4perl::Layout::PatternLayout
			layout_pattern = [%d{yyyy-MM-dd HH:mm:ss}][%F(%L)] %m%n
			
			log4perl.category.main             = INFO,Logfile,Screen
			log4perl.appender.Logfile          = Log::Log4perl::Appender::File
			log4perl.appender.Logfile.filename = __LOGFILEPATH__
			log4perl.appender.Logfile.utf8     = 1
			log4perl.appender.Logfile.mode     = append
			log4perl.appender.Logfile.layout   = ${layout_class}
			log4perl.appender.Logfile.layout.ConversionPattern = ${layout_pattern}
			
			log4perl.appender.Screen           = Log::Log4perl::Appender::Screen
			log4perl.appender.Screen.stderr    = 0
			log4perl.appender.Screen.utf8     = 1
			log4perl.appender.Screen.layout    = ${layout_class}
			log4perl.appender.Screen.layout.ConversionPattern = ${layout_pattern}
		};
		
		my $logfilename = sprintf( "%s/%s.log", $this->{logfilepath}, $currdate);
		$confstr =~ s/__LOGFILEPATH__/$logfilename/;
		
		Log::Log4perl::init( \$confstr);
		$this->{logger} = Log::Log4perl::get_logger( "main");
		
		$this->{logger_lastupdtime} = $currdate;
	}
}

sub runTick{
	my ( $this) = @_;
	$this->init();
}

sub getLogger{
	my ( $this) = @_;
	return $this->{logger};
}

sub shut{
}

1;