# Global Variable package for Apache::Controller/FormSetup Webapps
# Copyright (c) 2004 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# v1.0 JPR 10/04/2004 Initial release
#

package Global;

use strict;
use DB;

sub new {
	my ($class, $dbinfo, $database, $table) = @_;

	my $global = bless {
		db    => DB->new($database, $dbinfo),
		table => $table,
	}, $class;

	return $global;
}

sub List {
	my $global = shift;

	$global->{db}->query("SELECT var, value FROM $global->{table}");
	
	my @ls = ();
	while ($global->{db}->next_record()) {
		push(@ls, { var => $global->{db}->f(0), value => $global->{db}->f(1) });
	}

	return \@ls;
}

sub GetVal {
	my ($global, $var) = @_;
	return undef unless $var;

	$global->{db}->query("SELECT value FROM $global->{table} WHERE var='$var'");
	return undef unless $global->{db}->num_rows() == 1;

	$global->{db}->next_record();

	return $global->{db}->f(0);
}

1;
__END__
