use strict;
use warnings;

package MysqlX;

use DBI;

sub new
{
	my ($class, $conn) = @_;
	my $this = {};
	$this = bless( $this, $class) ;
	
	$this->setConn( $conn);
	return $this;

}

sub setConn {
	my ( $this, $conn) = @_;
	if( $conn && "DBI::db" eq ref( $conn)) {
		$this->{conn} = $conn;
		$this->_execute( 'set names utf8');
	}
}

###################################################
#
# 生成数据库连接(静态方法)
# @param hash $config 数据库配置
# @return DBI 数据库连接
#
###################################################
sub genConn {
	my ( $c) = @_;
	if( !defined( $c) || !defined( $c->{host}) || !defined( $c->{port}) || !defined( $c->{name}) || !defined( $c->{user}) || !defined( $c->{pass})) {
		foreach my $item ( keys( %{$c})) {
			printf( "%20s %s\n", $item, defined( $c->{$item}) ? $c->{$item} : 'undef');
		}
		die( 'can not connect to database server');	
	}
	my $dsn = "DBI:mysql:database=$c->{name};host=$c->{host};port=$c->{port}";
	
	my $conn = DBI->connect( $dsn, $c->{user}, $c->{pass});
	if( !$conn) {
		if( "HASH" eq ref( $c)) {
			foreach( keys( %{$c})) {
				printf( "% 10s %s\n", $_, defined( $c->{$_}) ? $c->{$_} : 'undef');	
			}	
		} else {
			printf( "%s\n", $c);
		}
		die "Can't connect to $dsn: $DBI::errstr";
	}
	$conn->{LongReadLen} = 10485760;
	$conn->{LongTruncOk} = 1;
	return $conn;
}

###################################################
#
# 将要存到数据库的值进行过滤
# @return string 过滤后的值
#
###################################################
sub quote( $) {
	my ( $this, $value) = @_;
	if( defined( $value)) {
		$value =~ s/\'/\'\'/i;
	}
	return "'$value'";
}

###################################################
#
# 添加数据
# @param hash $hData 要插入的数据
# @return int 影响行数
#
###################################################
sub insert {
	my ( $this, $sTable, $hData) = @_;	
	if( !defined( $hData) || !(ref( $hData) eq "HASH") || !%{$hData}) {
		warn 'the opera not execute, because the argument is undef or not a HASH or is empty';
		return 0;	
	}
	my $aFields = [keys( %{$hData})];
	my $aValues = [];
	foreach my $field( @{$aFields}) {
		if( !defined( $hData->{$field})) {
			die( 'the insert data value of '.$field.' can not be undef');
		}
		push( @{$aValues}, $this->quote( $hData->{$field}));
	}
	my $sFields = "`".join( "`, `", @{$aFields})."`";
	my $sValues = join( ", ", @{$aValues});
	
	my $sql = qq{
		insert into `${sTable}`( $sFields) values( $sValues)
	};
	
	return $this->_execute( $sql);
}

###################################################
#
# 修改数据
# @param hash $hData 要修改的数据
# @param hash $hWhere 修改数据的条件
# @return int 影响行数
#
###################################################
sub update {
	my ( $this, $sTable, $hData, $hWhere) = @_;
	if( !defined( $hData) || !(ref( $hData) eq "HASH") || !%{$hData}) {
		warn 'the opera not execute, because the argument is undef or not a HASH or is empty';
		return 0;	
	}
	my $sWhere = $this->getStrWhere( $hWhere);
	if( $sWhere) {
		$sWhere = " where ".$sWhere;	
	}
	
	my $aFields =  [keys( %{$hData})];
	my $aSets = [];
	foreach my $field( @{$aFields}) {
		if( !defined( $hData->{$field})) {
			die( 'the insert data value can not be undef');
		}
		my $value = $this->quote( $hData->{$field});
		push( @{$aSets}, "`$field`=$value");
	}
	my $sSets = join( ", ", @{$aSets});
	
	my $sql = qq{
		update `${sTable}` set ${sSets} ${sWhere}
	};

	return $this->_execute( $sql);
}

###################################################
#
# 删除数据
# @param hash $hWhere 删除数据的条件
# @return int 影响行数
#
###################################################
sub delete {
	my ( $this, $sTable, $hWhere) = @_;
		
	my $sWhere = $this->getStrWhere( $hWhere);
	if( $sWhere) {
		$sWhere = " where ".$sWhere;	
	}
	
	my $sql = qq{
		delete from `${sTable}` $sWhere
	};
	
	return $this->_execute( $sql);
}

################################################
#  生成where 条件语句
#  @param array $where 条件数组
#  
#  @return string 生成条件表达式
################################################
sub getStrWhere( $) {
	my ( $this, $where) = @_;
	my $sWhere = '';
	if( defined( $where) && scalar( %{$where})) {
		my $aWhere = [];
		my $cond = "";
		my $svalue = "";

		foreach my $key( keys( %{$where})) {
			my $value = $where->{$key};
			if( !defined( $svalue)) {
				die "the cond $key value can not be null";
			}
			if( $value =~ m/^\d+&/) {
				$value = int( $value);
			}
			if( !$key || ($key =~ m/^\d+&/)) {
				$cond = $value;
			} else {
				if( "ARRAY" eq ref( $value)) {
					my $aValue = [];
					foreach my $subvalue( @{$value}) {
						push( @{$aValue}, $this->quote( $subvalue));
					}
					$svalue = join( "','", @{$aValue});
					$cond = $key;
					
				} else {
					$cond = $key;
					$svalue = $this->quote( $value);
				}
				$cond =~ s/\?/$svalue/;
			}
			push( @{$aWhere}, '(' . $cond . ')');
		}
		
		$sWhere = join( ' and ', @{$aWhere});
	}
	return $sWhere;
}

################################################
#  生成order by 条件语句
#  @param array $orderby 排序规则数组
#  
#  @return string 生成条件表达式
################################################
sub getStrOrderBy {
	my( $this, $orderby) = @_;	
	my $result = "";
	if( $orderby && %{$orderby}) {
		my $_orderby = [];
		my $_key = "";
		my $_value = "";
		foreach $_key( keys( %{$orderby})) {
			$_value = $orderby->{$_key};
			if( $_value) {
				if( !($_key =~ m/^\d+$/)) {
					$_value = $_key.' '.$_value;
				}
				push( @{$_orderby}, $_value);
			}
		}
		$result = implode( ',', $_orderby);
		if( $result) {
			$result = ' order by '.$result;
		}
	}
	return $result;
}

################################################
#  传递一条sql 语句,返回查询的记录集
#  @param string $sql sql语句
#  
#  @return arrayref[hashref] 生成条件表达式
################################################
sub fetchAll( $) {
	my ( $this, $sql) = @_;
	my $result = [];
	
	my $sth = $this->_query( $sql);
	if( $sth) {
		while( my $hashRow = $sth->fetchrow_hashref()) {
			push( @{$result}, $hashRow);
		}
	}
	$sth->finish( );
	return $result;
}

sub fetchAllByCond( $$) {
	my ( $this, $sTable, $hWhere, $hOrderby) = @_;
	
	my $sOrderby = $this->getStrOrderBy( $hOrderby);
	
	my $sWhere = $this->getStrWhere( $hWhere);
	if( $sWhere) {
		$sWhere = " where ".$sWhere;	
	}
	
	my $sql = qq{
		select * from `${sTable}` ${sWhere} ${sOrderby}
	};
	
	return $this->fetchAll( $sql);
}

################################################
#  传递一条sql 语句,返回查询的记录集(仅一条)
#  @param string $sql sql语句
#  
#  @return hashref 生成条件表达式
################################################
sub fetchRow( $) {
	my ( $this, $sql) = @_;
	my $result = {};
		
	my $sth = $this->_query( $sql);

	if( defined($sth)) {
		$result = $sth->fetchrow_hashref();
	}
	
	return $result;
}

sub fetchRowByCond {
	my ( $this, $sTable, $hWhere, $hOrderby) = @_;
	
	my $sOrderby = $this->getStrOrderBy( $hOrderby);
	
	my $sWhere = $this->getStrWhere( $hWhere);
	if( $sWhere) {
		$sWhere = " where ".$sWhere;	
	}
	
	my $sql = qq{
		select * from `${sTable}` ${sWhere} ${sOrderby} limit 1
	};
	
	return $this->fetchRow( $sql);
}

sub fetchCol {
	my ( $this, $sql) = @_;
	
	$this->_logsql( $sql);
	my $result = {};
	if( defined( $sql) && $sql) {
		$result = $this->{conn}->selectcol_arrayref( $sql);
		if( $DBI::errstr) {
			die( "execute sqlstatement $sql error:".$DBI::errstr);
		}
	}
	
	return $result;
}

sub fetchColByCond {
	my ( $this, $sTable, $hWhere, $field) = @_;
	
	my $sWhere = $this->getStrWhere( $hWhere);
	if( $sWhere) {
		$sWhere = " where ".$sWhere;	
	}
	
	if( !$field) {
		$field = "*";
	}
	
	my $sql = qq{
		select ${field} from `${sTable}` ${sWhere}
	};
	
	return $this->fetchCol( $sql);
}

sub fetchHash {
	my ( $this, $sql) = @_;
	my $result = {};
	
	my $sth = $this->_query( $sql);
	if( $sth) {
		my $_key = "";
		my $_value = "";
		while( my $arrayRow = $sth->fetchrow_arrayref()) {
			$_key = $arrayRow->[0] ? $arrayRow->[0] : '';
			$_value = $arrayRow->[1] ? $arrayRow->[1] : '';
			$result->{$_key} = $_value;
		}
	}
	$sth->finish( );
	return $result;
}

sub fetchHashByCond{
	my ( $this, $sTable, $hWhere, $keyfield, $valuefield) = @_;
	
	my $sWhere = $this->getStrWhere( $hWhere);
	if( $sWhere) {
		$sWhere = " where ".$sWhere;	
	}
	
	my $sql = qq{
		select ${keyfield}, ${valuefield} from `${sTable}` ${sWhere}
	};
	
	return $this->fetchHash( $sql)
}

sub getLastInsertId {
	my ($this) = @_;

	return $this->{conn}->last_insert_id(undef, undef, undef, undef);
}

sub _query( $) {
	my ( $this, $sql) = @_;
	
	$this->_logsql( $sql);
	my $sth = undef;
	if( defined( $sql) && $sql) {
		$sth = $this->{conn}->prepare( $sql);
		$sth->execute();
		if( $DBI::errstr) {
			die( "execute sqlstatement $sql error:".$DBI::errstr);
		}
	}
	
	return $sth;
}

sub _logsql {
	my ( $this, $sql) = @_;
	
	
	#print "--------";
	#print $sql;
	#print "\n";	

}

sub _execute( $) {
	my ( $this, $sql) = @_;
	
	$this->_logsql( $sql);
	my $result = 0;
	if( defined( $sql) && $sql) {
		
		my $sth = $this->{conn}->prepare( $sql);
		if( !$sth || $DBI::errstr) {
			die( "execute sqlstatement $sql error:".$DBI::errstr);	
		}
		my $result = $sth->execute();
		
		if( $DBI::errstr) {
			die( "execute sqlstatement $sql error:".$DBI::errstr);	
		}
		$sth->finish( );
		return $result;
	}
	
	return $result;
}

sub __destruct() {
	my ( $this) = @_;
	$this->{conn}->disconnect();
	$this->{conn} = 0;
}

1;