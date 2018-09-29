use strict;
use warnings;
use utf8;

#############################################################
#
# 敏感字,用户修改游戏服务器敏感字库
#############################################################
package Moby::Business::TimeMan;

use POSIX qw{strftime};

sub new
{
	shift;
	my $this = bless {@_};
	$this->init();
	return $this;
}

sub init{
	my ( $this) = @_;
	my $now = time();
	$this->{now} = $now;
	$this->{nowstr} = strftime( "%Y-%m-%d %H:%M:%S", localtime( $now));
	return $this;
}

sub setLogger{
	my ( $this, $logger) = @_;
	$this->{logger} = $logger;
	return $this;
}

sub runTick{
	my ( $this) = @_;
	$this->init();
	if( 0 && $this->{logger}) {
		$this->{logger}->info( sprintf( "now:%s nowstr:%s", 
			$this->{now}, 
			$this->{nowstr},
		));
	}
}

sub shut{
}

1;