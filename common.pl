use strict;
use File::Path;
use Time::Local;

our $g_app_path;

########################################################################################################################################
#以下是比较底层的函数
sub log2
{
	my ($text) = @_;
	print "$text\n";
	my $time = ts2str(time());

	my ($logfile) = ($0 =~ /(.*?)(\.[^\.]*)?$/);
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
