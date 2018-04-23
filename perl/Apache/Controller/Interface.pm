# Apache::Controller Interface Module
# Copyright (c) 2006 Jeremy Robst <jpr@robst.me.uk>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# v1.0 JPR 23/01/2006 Initial release.
# v1.1 JPR 25/01/2006 Modified for Apache::Controller 5.1
#

package Apache::Controller::Interface;
@ISA = qw(FormSetup);

use strict;
use Apache::Controller::DB;
use Data::Dumper;

sub new {
	my ($class, $config) = @_;

	my $aci = bless {
		config => $config,
		db     => Apache::Controller::DB->new($config->{locals}->{db}->{name}, $config->{locals}->{db}),
		user   => $config->{user},
		state  => $config->{session},
	}, $class;

	return $aci;
}

sub header_setup { }
sub footer_setup { }
sub levels_setup { }

sub index_setup { 
	my ($aci, $param_table) = @_;

	$aci->{db}->query("SELECT * FROM modules ORDER BY SITE ASC, name ASC");
	
	my @apps = ();
	while ($aci->{db}->next_record()) {
		push(@apps, $aci->_appinfo($aci->{db}));
	}
	
	return { apps => \@apps };
}

sub _appinfo {
	my ($aci, $db) = @_;

	return {
		name        => $db->f(0),
		site        => $db->f(1),
		templatedir => $db->f(2),
		globalfile  => $db->f(3),
		intfile     => $db->f(4),
		title       => $db->f(5),
	};
}

sub _get_info {
	my ($aci, $name, $site) = @_;
	
	$aci->{db}->prepare("SELECT * FROM modules WHERE name=? AND site=?");
	$aci->{db}->execute($name, $site);

	if ($aci->{db}->num_rows() == 1) {
		$aci->{db}->next_record();

		return $aci->_appinfo($aci->{db});
	}
	
	return undef;
}

sub edit_setup {
	my ($aci, $param_table, $org_name, $org_site) = @_;

	my $defaults = $aci->_get_info($org_name, $org_site);

	$defaults->{org_name} = $org_name;
	$defaults->{org_site} = $org_site;

	return $aci->form_setup('edit', $param_table, $defaults);
}

sub edit {
	my ($aci, $param_table) = @_;

	$aci->save_form_state($param_table, 'edit');
	
	my $info = $aci->_get_info($aci->{state}->{edit}->{org_name}, $aci->{state}->{edit}->{org_site});
	
	my @changes = ();
	my @newvals = ();

	foreach my $k (keys %$info) {
		if ($info->{$k} ne $aci->{state}->{edit}->{$k}) {
			push(@changes, "$k=?");
			push(@newvals, $aci->{state}->{edit}->{$k});
		}
	}

	if (scalar(@changes)) {
		$aci->{db}->prepare("UPDATE modules SET " . join(", ", @changes) . " WHERE name=? AND site=?");
		$aci->{db}->execute(@newvals, $aci->{state}->{edit}->{org_name}, $aci->{state}->{edit}->{org_site});
	}

	$aci->delete_form_state('edit');
	return 0;
}

sub add_setup {
	my ($aci, $param_table) = @_;

	return $aci->form_setup('add', $param_table);
}

sub add {
	my ($aci, $param_table) = @_;

	$aci->save_form_state($param_table, 'add');
	return -1 if $aci->form_param_check('add');

	my $module = $aci->{state}->{add};
	my $info = $aci->_get_info($module->{name}, $module->{site});

	if (!$info) {
		$aci->{db}->prepare("INSERT INTO modules VALUES(?, ?, ?, ?, ?, ?)");
		$aci->{db}->execute($module->{name}, $module->{site}, $module->{templatedir}, $module->{globalfile}, $module->{intfile},
							$module->{title});
	}
	
	$aci->delete_form_state('add');
	return 0;
}

sub sessions_setup {
	my ($aci, $param_table) = @_;

	# Have to close session to remove lock from table
	Apache::Controller::end_session($aci->{config}, $aci->{config}->{locals}->{db});
	
	my $vars = $aci->form_setup('sessions', $param_table);

	my $opts = Apache::Controller::_session_connect_opts($aci->{config}->{locals}->{db});
	my $type = Apache::Controller::_get_session_type($aci->{config}->{locals}->{db});

	my (%session, @ss) = ((), ());

	$aci->{db}->query("SELECT TRIM(id) FROM sessions");
	while ($aci->{db}->next_record()) {
		tie %session, $type, $aci->{db}->f(0), $opts;

		push(@ss, { id => $aci->{db}->f(0), data => Dumper(\%session) });
		
		untie(%session);
	}

	$vars->{sessions} = \@ss;

	# Start session again as Apache::Controller expects it
	Apache::Controller::start_session($aci->{config}, $aci->{config}->{locals}->{db});
	return $vars;
}

sub add_session {
	my ($aci, $param_table) = @_;

	my %session = undef;
	my $opts = Apache::Controller::_session_connect_opts($aci->{config}->{locals}->{db});
	my $type = Apache::Controller::_get_session_type($aci->{config}->{locals}->{db});

	tie %session, $type, undef, $opts;
	$session{timestamp} = time();
	untie(%session);
	
	return 0;
}

sub del {
	my ($aci, $param_table) = @_;

	my %session = undef;
	my $opts = Apache::Controller::_session_connect_opts($aci->{config}->{locals}->{db});
	my $type = Apache::Controller::_get_session_type($aci->{config}->{locals}->{db});

	# Look for "del_" keys
	foreach my $p (keys %$param_table) {
		if ($p =~ /^del_(.+)$/) {
			my $sid = $1;
			
			tie %session, $type, $sid, $opts;
			tied(%session)->delete;
			untie(%session);
		}
	}

	return 0;
}

sub delold {
	my ($aci, $param_table) = @_;

	$aci->save_form_state($param_table, 'sessions');
	
	my $expire_time = time() - $aci->{state}->{sessions}->{age};

	# Have to close session to remove lock from table
	Apache::Controller::end_session($aci->{config});
	
	my $opts = Apache::Controller::_session_connect_opts($aci->{config}->{locals}->{db});
	my $type = Apache::Controller::_get_session_type($aci->{config}->{locals}->{db});

	$aci->{db}->query("SELECT trim(id) FROM sessions");
	while ($aci->{db}->next_record()) {
		my %session;

		tie %session, $type, $aci->{db}->f(0), $opts;

		if ($session{timestamp} < $expire_time) {
			tied(%session)->delete;
		}

		untie(%session);
	}

	# Start session again as Apache::Controller expects it
	Apache::Controller::start_session($aci->{config}, $aci->{config}->{locals}->{db});

	$aci->delete_form_state('sessions');

	return 0;	
}

1;
__END__;
