BEGIN
{        
	$WARN_LOCKCOUNT = 0;

	$SIG{TERM} = sub {
		$g_continue = 0 
	};
	
	$SIG{__WARN__} = sub {
		return if($WARN_LOCKCOUNT);
		
		my ($text) = @_;
		chomp($text);

		my ($package, $filename, $line, $subroutine) = caller(0);
	    __log($filename, $line, $text);
	    
		my $stack_level = 1;
	    for (my @debuginfo = caller($stack_level); scalar(@debuginfo); @debuginfo = caller(++$stack_level)) {
			($package, $filename, $line, $subroutine) = @debuginfo;
			__log($filename, $line, "\t| $subroutine");
		}

	    return 1;
	};

	$SIG{__DIE__} = sub {
		my ($text) = @_;
		chomp($text);

		my ($package, $filename, $line, $subroutine) = caller(0);
	    __log($filename, $line, $text);	    
	    
		my $stack_level = 1;
	    for (my @debuginfo = caller($stack_level); scalar(@debuginfo); @debuginfo = caller(++$stack_level)) {
			($package, $filename, $line, $subroutine) = @debuginfo;
			__log($filename, $line, "\t| $subroutine");
		}

	    return 1;
	};

	sub __log
	{
		my ($file, $line, $text) = @_;
		
		my ($sec, $min, $hour, $day, $mon, $year) = localtime(time());
		$year += 1900;
		$mon += 1;

		my $time = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $day, $hour, $min, $sec);

		$WARN_LOCKCOUNT++;
		
		my ($logfile) = ($0 =~ /(.*?)(\.[^\.]*)?$/);
		$logfile .= '.log';
		
		open LOGFILE, ">>$logfile";
		#binmode(LOGFILE, ":encoding(utf8)");
		print LOGFILE "[$file($line)][$time] $text\n";
		close LOGFILE;

		$WARN_LOCKCOUNT--;              
	}
}

BEGIN
{
	use FindBin;
	for(@ARGV)
	{
		next unless /^\-srv$/i;
		
		my $pid = fork();
		if ($pid < 0)
		{
			die "fork: $!";
		}
		elsif ($pid)
		{
			exit 0;
		}
	
		chdir($FindBin::Bin);
	
		open(STDIN,  "</dev/null");
		open(STDOUT, ">/dev/null");
		open(STDERR, ">&STDOUT");
		last;
	}
}

return 1;