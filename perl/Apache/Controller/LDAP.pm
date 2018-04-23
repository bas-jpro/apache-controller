# LDAP Encapsulation for Apache::Controller 
# Copyright (c) 1999, 2000, 2003, 2004 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# $Id$
#

package Apache::Controller::LDAP;
use strict;
use Encode qw(encode_utf8 _utf8_off is_utf8);
use Net::LDAP;
use Net::LDAP::Filter;
use Data::Dumper;

# Bind with username/password given at login
# or anonymously if none given
sub new {
	my ($class, $org_root, $server, $login) = @_;

	my $ldap_conn = Net::LDAP->new($server) or die "Can't connect to $server\n";

	my $ldap = bless {
		ldap  => $ldap_conn,
		base  => $org_root,
		mesg  => undef,
		entry => undef,
		bound => 0,
	}, $class;

	if ($login) {
		if ($login->{user} =~ /,/) {
			$ldap->{mesg} = $ldap->{ldap}->bind(dn => $login->{user}, password => $login->{passwd});
		} else {
			$ldap->{mesg} = $ldap->{ldap}->bind(dn => "uid=$login->{user},ou=people,$ldap->{base}", password => $login->{passwd});
		}
	} else {
		$ldap->{mesg} = $ldap->{ldap}->bind;
	}

	$ldap->{bound} = !$ldap->{mesg}->code;

	return $ldap;
}

sub is_bound {
	my $self = shift;

	return $self->{bound};
}

sub DESTROY {
	my $ldap = shift @_;

	$ldap->{ldap}->unbind;
}

sub search {
	my ($ldap, $opt) = @_;

	if (ref($opt)) { 
		# Options for the search as perl Net::LDAP
		$opt->{base} = $ldap->{base} unless defined($opt->{base});
		$ldap->{mesg} = $ldap->{ldap}->search(%$opt);
	} else {
		# Bit of a hack but stops UTF8 searches hanging
		my $filter = encode_utf8($opt);

		# Assume just a string filter
		$ldap->{mesg} = $ldap->{ldap}->search(base => $ldap->{base}, filter => $filter);
	}
}

sub mesg {
	my $self = shift;

	return $self->{mesg};
}

# Opts is a hash of search constraints
# This builds a search filter by and'ing them
sub build_search {
	my ($ldap, $opts) = @_;

	my $filter = "";

	if (scalar(keys %$opts) > 1) {
		$filter = "(&";
		
		foreach (keys %$opts) {
			if (ref($opts->{$_}) eq "ARRAY") {
				$filter .= "(|";
				foreach my $v (@{ $opts->{$_} }) {
					$filter .= "($_=$v)";
				}
				$filter .= ")";
			} else {
				$filter .= "($_=$opts->{$_})";
			}
		}
		
		$filter .= ")";
	} else {
		foreach (keys %$opts) {
			if (ref($opts->{$_}) eq "ARRAY") {
				$filter = "(|";
				foreach my $v (@{ $opts->{$_} }) {
					$filter .= "($_=$v)";
				}
				$filter .= ")";		
			} else {
				$filter = "($_=$opts->{$_})";
			}
		}
	}

	return $filter;
}

sub next_entry {
	my $ldap = shift @_;

	return undef unless $ldap->{mesg};
	
	$ldap->{entry} = $ldap->{mesg}->pop_entry();

	$ldap->{entry};
}

sub get {
	my ($ldap, $attr) = @_;

	return undef unless $ldap->{entry};

	my @vs = $ldap->{entry}->get_value($attr);

	return \@vs;
}

sub get_single {
	my ($ldap, $attr) = @_;

	return undef unless $ldap->{entry};

	return scalar($ldap->{entry}->get_value($attr));
}

sub count {
	my $ldap = shift @_;
	
	return undef unless $ldap->{mesg};

	$ldap->{mesg}->count;
}

# mod_attr an attribute of a given idx (dn=idx,ou=$ou,$base)
# attrib is a hash of attribute and value
# mod_type is 'add', 'replace', or 'delete'
sub mod_attr {
	my ($ldap, $idx, $ou, $attrib, $mod_type) = @_;
	$mod_type = "replace" unless (($mod_type eq "add") || ($mod_type eq "delete"));

	my $msg = $ldap->{ldap}->modify(
									dn => "$idx, ou=$ou, $ldap->{base}",
									$mod_type => $attrib,
									);

	$msg->code && warn("Failed to modify entry: $idx, $ou, $mod_type\n", Dumper($attrib), $msg->error, "\n");

	$msg->sync;
}

# Just calls mod_attr with mod_type eq "replace"
sub replace_attr {
	my ($ldap, $idx, $ou, $attrib) = @_;
	
	$ldap->mod_attr($idx, $ou, $attrib, 'replace');
}

# Just calls mod_attr with mod_type eq "add"
sub add_attr {
	my ($ldap, $idx, $ou, $attrib) = @_;	

	$ldap->mod_attr($idx, $ou, $attrib, 'add');
}

# Just calls mod_attr with mod_type eq "delete"
sub del_attr {
	my ($ldap, $idx, $ou, $attrib) = @_;	

	$ldap->mod_attr($idx, $ou, $attrib, 'delete');
}

sub add {
	my ($ldap, $dn, $attrs) = @_;

	my $result = $ldap->{ldap}->add(
									dn => $dn,
									attrs => $attrs,
									);

	$result->code && warn("Failed to add entry: ", $result->error, "\n");
}

# $attrs is in the format in perldoc Net::LDAP
sub delete {
	my ($ldap, $idx, $ou, $attrs) = @_;

	my $msg = $ldap->{ldap}->modify(dn => "$idx, ou=$ou, $ldap->{base}",
									   delete => $attrs);

	$msg->sync;
}

1;
__END__

