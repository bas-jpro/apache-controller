# DBList package for Apache::Controller/FormSetup Webapps
# Copyright (c) 2004 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# v1.0 JPR 03/04/2004 Initial release
# v1.1 JPR 09/05/2004 Added desc column - need to rethink
# v2.0 JPR 12/01/2006 Moved to Apache::Controller::DB
#

package DBList;

use strict;
use Apache::Controller::DB;

sub new {
	my ($class, $dbinfo, $database, $table) = @_;

	my $dblist = bless {
		db    => Apache::Controller::DB->new($database, $dbinfo),
		table => $table,
	}, $class;

	return $dblist;
}

sub List {
	my $dblist = shift;

	$dblist->{db}->query("SELECT id, value, description FROM $dblist->{table} ORDER BY id ASC");
	
	my @ls = ();
	while ($dblist->{db}->next_record()) {
		push(@ls, { id => $dblist->{db}->f(0), value => $dblist->{db}->f(1), desc => $dblist->{db}->f(2) });
	}

	return \@ls;
}

sub GetVal {
	my ($dblist, $id) = @_;
	return undef unless $id;

	$dblist->{db}->query("SELECT description FROM $dblist->{table} WHERE id='$id'");
	return undef unless $dblist->{db}->num_rows() == 1;

	$dblist->{db}->next_record();

	return $dblist->{db}->f(0);
}

sub GetDesc {
	my ($dblist, $value) = @_;

	$dblist->{db}->query("SELECT description FROM $dblist->{table} WHERE value='$value'");
	return undef unless $dblist->{db}->num_rows() == 1;

	$dblist->{db}->next_record();

	return $dblist->{db}->f(0);
}

1;
__END__
