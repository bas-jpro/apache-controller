# Database Encapsulation for Apache::Controller
# Copyright (c) 1999, 2000, 2001, 2002, 2004 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# This was based on the PHP3 DB class from phplib
# See http://www.php.net
#
# $Id$
#

package Apache::Controller::DB;

use strict;
use DBI;
use Text::ParseWords;

sub new {
	my ($class, $database, $dbinfo) = @_;

	my $dsn = "DBI:$dbinfo->{type}:dbname=$database;host=$dbinfo->{host}";
	$dsn .= ";port=$dbinfo->{port}" if $dbinfo->{port} && $dbinfo->{port} > 0;

	my $dbh = DBI->connect($dsn, $dbinfo->{user}, $dbinfo->{passwd}) or die $DBI::errstr;

	my $dbclass = bless {
		'dbh'  => $dbh,
		'sth'  => undef,
		'row'  => undef,
		_debug => 0,
	}, $class; 

	return $dbclass;
}

sub DESTROY {
	my $db = shift @_;
		
	$db->{sth}->finish() if $db->{sth};

	$db->{dbh}->disconnect() if $db->{dbh};
}

sub debug {
	my ($self, $opt) = @_;

	if (defined($opt)) {
		$self->{_debug} = $opt;
	}

	return $self->{_debug};
}

sub select_row {
	my ($db, $str) = @_;

#	print STDERR "Query: $str\n";

	$db->query($str);

	return $db->{sth}->fetchrow_hashref;
}

sub prepare {
	my ($db, $str) = @_;

	print STDERR "Query: $str\n" if $db->{_debug};

	$db->{sth}->finish() if $db->{sth};
	$db->{sth} = $db->{dbh}->prepare($str) || die $db->{dbh}->errstr;
}

sub execute {
	my ($db, @values) = @_;

	$db->{sth}->execute(@values) || die $db->{dbh}->errstr;
}

sub query {
	my ($db, $query) = @_;

	$db->prepare($query);
	$db->execute();
}

sub next_record {
	my $db = shift @_;

	$db->{row} = $db->{sth}->fetch;

	$db->{row};
}

sub f {
	my ($db, $field) = @_;

	return if !$db->{row};
	return $db->{row}->[$field];
}

sub num_rows {
	my $db = shift @_;
	
	$db->{sth}->rows;
}

# Build a search query (on a single table) from a hash
sub build_query {
	my ($db, $table, $opts, $select_str) = @_;

	$select_str = '*' unless $select_str;

	my $query = "SELECT $select_str FROM $table ";
	my $glue  = "WHERE";

	foreach (keys %$opts) {
		if (ref($opts->{$_}) eq "ARRAY") {
			if (scalar(@{$opts->{$_}}) >= 1) {
				my $v = pop(@{$opts->{$_}});
				$query .= $glue . " $_ IN ('$v'";
				foreach $v (@{$opts->{$_}}) {
					$query .= ", '$v'"
				}
				$query .= ") ";

				# Put $v back in case it's used again
				push(@{ $opts->{$_}}, $v);
			} else {
				$query .= $glue .= " $_ IN (NULL) ";
			}
		} else {
			# Not sure this is the best way to do it
			if (ref($opts->{$_}) eq "HASH") {
				my @ks = keys(%{$opts->{$_}});
				if (scalar(@ks) >= 1) {
					my $k = pop(@ks);

					# Replace spaces with % to make search a bit broader
					my $v = $opts->{$_}->{$k};
					$v =~ s/\s+/%/g;

					# Replace * with %
					$v =~ s/\*/%/g;

					$query .= "$glue ($k LIKE '%$v%'";
					foreach $k (@ks) {
						$v = $opts->{$_}->{$k};
						$v =~ s/\s+/%/g;
						$query .= " OR $k LIKE '%$v%'";
					}
					$query .= ") ";
				}
			} else {
				# Replace * with %
				$opts->{$_} =~ s/\*/%/g;

				my $comp = '=';
				if ($opts->{$_} =~ /%/) {
					$comp = 'LIKE';
				}
				
				$query .= $glue . " $_ $comp '" . $opts->{$_} . "' ";
			}
		}
		$glue = "AND";
	}

	return $query;
}

sub build_freetext_query {
	my ($db, $table, $field, $search_str, $select_str) = @_;
	return unless $table && $field && $search_str;

	$select_str = '*' unless $select_str;

	my $query = "SELECT $select_str FROM $table WHERE ";
	my $glue = '';

	# Generate list of words/phrases  from search_string
	my @phrases = shellwords($search_str);

	foreach my $p (@phrases) {
		# Replace *'s with [[:alnum:]]*'s to allow partial word searchs
		$p =~ s/\*/[[:alnum:]]*/g;

		my $cmp = 'REGEXP';

		# Exclude phrases if they begin with - 
		if ($p =~ /^\-(.+)$/) {
			$cmp = 'NOT REGEXP';
			
			$p = $1;
		}

		$query .= $glue . " ($field $cmp '[[:<:]]" . $p . "[[:>:]]')";
		
		$glue = ' AND';
	}

#	print STDERR "Query: $query\n";

	return $query;
}

# Create a temporaary table of the intersection of two tables
sub intersect_tables {
	my ($db, $result, $t1, $t2, $col) = @_;

	$db->query("CREATE TEMPORARY TABLE $result ENGINE=MEMORY SELECT $t1.$col FROM $t1 INNER JOIN $t2 USING ($col)");
}

# Create a temporaary table of the union of two tables
sub union_tables {
	my ($db, $result, $t1, $t2, $col) = @_;

	$db->query("CREATE TEMPORARY TABLE $result ENGINE=HEAP SELECT $col FROM $t1");
	$db->query("INSERT INTO $result SELECT $col FROM $t2");
}

1;
__END__
