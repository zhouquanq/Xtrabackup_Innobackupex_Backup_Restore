#############################################################
#
# 配置文件读取工具
#############################################################
package Lib::Util::Ini;

use strict;
BEGIN
{
	require 5.004;
	$Lib::Util::Ini::VERSION = '2.12';
	$Lib::Util::Ini::errstr  = '';
	$Lib::Util::Ini::__nestSeparator = '\\.';
}

# Create an empty object
sub new { bless {}, shift }

# Create an object from a file
sub read {
	my $class = ref $_[0] ? ref shift : shift;

	# Check the file
	my $file = shift or return $class->_error( 'You did not specify a file name' );
	my $encoding = shift || "utf8";
	return $class->_error( "File '$file' does not exist" )              unless -e $file;
	return $class->_error( "'$file' is a directory, not a file" )       unless -f _;
	return $class->_error( "Insufficient permissions to read '$file'" ) unless -r _;

	# Slurp in the file
	local $/ = undef;
	open CFG, $file or return $class->_error( "Failed to open file '$file': $!" );
	binmode(CFG, ":encoding($encoding)");
	my $contents = <CFG>;
	close CFG;

	$class->read_string( $contents );
}

# Create an object from a string
sub read_string {
	my $class = ref $_[0] ? ref shift : shift;
	my $self  = bless {}, $class;
	return undef unless defined $_[0];

	# Parse the file
	my $ns      = '_';
	my $counter = 0;
	foreach ( split /(?:\015{1,2}\012|\015|\012)/, shift ) {
		$counter++;

		# Skip comments and empty lines
		next if /^\s*(?:\#|\;|$)/;

		# Remove inline comments
		s/\s\;\s.+$//g;

		# Handle section headers
		if ( /^\s*\[\s*(.+?)\s*\]\s*$/ ) {
			# Create the sub-hash if it doesn't exist.
			# Without this sections without keys will not
			# appear at all in the completed struct.
			$self->{$ns = $1} ||= {};
			next;
		}

		# Handle properties
		if ( /^\s*([^=]+?)\s*=\s*["']?(.*?)["']?\s*$/ ) {
			
			#$self->{$ns}->{$key} = $value;
			$self->_processkey ( $self->{$ns}, $1, $2);
			next;
		}

		return $self->_error( "Syntax error at line $counter: '$_'" );
	}

	$self;
}

###########################################################################
#
# 处理ini文件中的多层次配置
# 
###########################################################################
sub _processkey ( $$$){
	my ( $self, $config, $key, $value) = @_;
	
	if( $key =~ m/$Lib::Util::Ini::__nestSeparator/) {
		my $pieces = [split( /$Lib::Util::Ini::__nestSeparator/, $key, 2)];
		
		if( length( $pieces->[0]) > 0 && length( $pieces->[1]) >  0) {
			if ( !defined( $config->{$pieces->[0]})) {
				if( '0' eq $pieces->[0] && !defined( $config)) {
                    $config = {$pieces->[0] => $config};
                } else {
                    $config->{$pieces->[0]} = {};
                }
			} elsif ( !( 'HASH' eq ref( $config->{$pieces->[0]}))) {
                $config->{$pieces->[0]} = $self->_processkey( $config->{$pieces->[0]}, $pieces->[1], $value);
            }
            $config->{$pieces->[0]} = $self->_processkey( $config->{$pieces->[0]}, $pieces->[1], $value);
		} else {
			warn 'impossible';
			return $config;
		}
	} elsif( $key) {
		$config->{$key} = $value;
	}
	return $config;
}

# Save an object to a file
sub write {
	my $self = shift;
	my $file = shift or return $self->_error('No file name provided');
	my $encoding = shift || "utf8";

	# Write it to the file
	open( CFG, '>' . $file ) or return $self->_error(
		"Failed to open file '$file' for writing: $!"
		);
	binmode(CFG, ":encoding($encoding)");
	print CFG $self->write_string;
	close CFG;
}

# Save an object to a string
sub write_string {
	my $self = shift;

	my $contents = '';
	foreach my $section ( sort { (($b eq '_') <=> ($a eq '_')) || ($a cmp $b) } keys %$self ) {
		my $block = $self->{$section};
		$contents .= "\n" if length $contents;
		$contents .= "[$section]\n" unless $section eq '_';
		foreach my $property ( sort keys %$block ) {
			$contents .= "$property=$block->{$property}\n";
		}
	}
	
	$contents;
}

# Error handling
sub errstr { $Lib::Util::Ini::errstr }
sub _error { $Lib::Util::Ini::errstr = $_[1]; undef }

1;

__END__
