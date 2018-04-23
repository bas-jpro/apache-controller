# DBEnum package for Apache::Controller/FormSetup Webapps
# Copyright (c) 2006 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# v1.0 JPR 01/02/2006 Initial release
#

package DBEnum;

use strict;
use Apache::Controller::DB;

sub new {
	my ($class, $dbinfo, $database, $table, $field) = @_;

	my $dbenum = bless {
		db    => Apache::Controller::DB->new($database, $dbinfo),
		table => $table,
		field => $field,
	}, $class;

	return $dbenum;
}

sub List {
	my $dbenum = shift;

	$dbenum->{db}->query("DESCRIBE $dbenum->{table} $dbenum->{field}");
	return [] unless $dbenum->{db}->num_rows() == 1;

	$dbenum->{db}->next_record();

	my @ls = ();
	# FIXME: - breaks if enum values have )'s in them 
	if ($dbenum->{db}->f(1) =~ /^enum\(([^\)]+)\)/) {
		foreach my $v (split(/,/, $1)) {
			$v =~ s/\'//g;

			push(@ls, $v);
		}

	} else {
		return [];
	}

	return \@ls;
}

1;
__END__
