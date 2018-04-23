# FormSetup package for Apache::Controller Webapps
# Copyright (c) 2004, 2005, 2006 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# $Id$
#

package FormSetup;

use strict;
use POSIX qw(strftime);
use Time::Local;
use URI::Escape qw(uri_escape);
use DBList;
use DBEnum;

use Data::Dumper;

my $YEARS  = [1998..2019]; 

my $MONTH_NUMS  = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12'];

my $MONTHS = { '01' => 'January', '02' => 'February', '03' => 'March', '04' => 'April', '05' => 'May', '06' => 'June',
			   '07' => 'July', '08' => 'August', '09' => 'September', '10' => 'October',  '11' => 'November', 
			   '12' => 'December'};

my $DAYS = [ '01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '13', '14', '15', '16', '17', 
			 '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31' ];

my $TIME = {
	hour   => [0..23],
	minute => [0..59],
	second => [0..59],
};

sub new {
	my $class = shift;

	my $form = bless {
		config => undef,
		state => undef,
	}, $class;

	return $form;
}

# Format a date suitable for a default form form_setup_date
# Expects a localtime() type list
sub fmt_date {
	my ($form, @ds) = @_;

	return sprintf("%04d-%02d-%02d", $ds[5]+1900, $ds[4]+1, $ds[3]);
}

# Setup forms form viewing
sub form_info_setup {
	my ($form, $op, $field_info) = @_;

	return $form->form_setup($op, {}, $field_info, 1);
}

# Delete saved state
sub delete_form_state {
	my ($form, $op) = @_;

	delete $form->{state}->{$op};
}

# Generic XML data setup routine
sub form_setup {
	my ($form, $op, $param_table, $defaults, $info) = @_;
	$info = 0 unless $info;

	my %vars = ();

	my $state = $form->{state}->{$op};

	foreach my $name (keys %{ $form->{config}->{locals}->{data}->{field} }) {
		my $field = $form->{config}->{locals}->{data}->{field}->{$name};

		next unless $form->field_setup($field, $op);

		my $default = $state->{$name} || $defaults->{$name} || $field->{default};
		
		my $cmd = '$form->form_setup_' . $field->{type} . '($name, $field, $default, $info, \%vars)';

		eval $cmd;

		print STDERR "Error: $@\n" if $@;
	}

	return \%vars;
}

# Generic XML data setup check field setup matches op
sub field_setup {
	my ($form, $field, $op) = @_;

	foreach (@{ $field->{setup}->{form} }) {
		return 1 if $_ eq $op;
	}

	return 0;
}

# Generic XML type setup routines 
sub form_setup_latlon_str {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	if ($info) {
		$vars->{$name} = $default;
		return;
	}

	my $dir = '';

	$vars->{$name . '_deg'} = '00';
	$vars->{$name . '_min'} = '0.00';

	# default is in DDD MMM.MMM DIR form
	if ($default =~ /(\d+)\s+(\d+\.?\d*)\s+(N|S|E|W)/) {
		$vars->{$name . '_deg'} = $1;
		$vars->{$name . '_min'} = $2;

		$dir = $3;
	}

	# Default to latitude
	if (!$field->{dir} || $field->{dir} eq 'lat') {
		foreach my $d (qw(N S)) {
			push(@{ $vars->{$name . '_dir'} }, { option => $d, value => $d, selected => ($d eq $dir) ? 'SELECTED' : '' });
		}
	}

	if ($field->{dir} && ($field->{dir} eq 'lon')) {
		foreach my $d (qw(E W)) {
			push(@{ $vars->{$name . '_dir'} }, { option => $d, value => $d, selected => ($d eq $dir) ? 'SELECTED' : '' });
		}
	}
}

sub form_setup_list {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	# If we are displaying field value then use default to index list else
	# return all values for user selection
	if ($info) {
		my $func  = $name . '_name';

		$vars->{$func} = $form->$func($default);
	} else {
		my $func = $name . 's_setup';
		
		$vars->{$name . "s"} = $form->$func($default);
	}
}

sub form_setup_dblist {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	my $dblist = DBList->new($form->{config}->{locals}->{db}, $field->{database}, $field->{table});

	if ($info) {
		$vars->{$name} = $dblist->GetVal($default);

		return;
	}
	
	$vars->{$name} = $dblist->List();

	foreach (@{ $vars->{$name} }) {
		$_->{selected} = ($_->{id} eq $default) ? 'SELECTED' : '';
	}
}

# Generate list of values from enum field in db
sub form_setup_dbenum {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	if ($info) {
		$vars->{$name} = $default;

		return;
	}

	my $dbenum = DBEnum->new($form->{config}->{locals}->{db}, $field->{database}, $field->{table}, $field->{field});

	my $vals = $dbenum->List();

	$vars->{$name} = [];
	foreach (@$vals) {
		push(@{ $vars->{$name} }, { option => $_, value  => $_, selected => ($_ eq $default) ? 'SELECTED' : ''});
	}
}

sub form_setup_range {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	if ($info) {
		$vars->{$name} = $default;

		return;
	}
	
	my @vs = ();
	for (my $i=$field->{start}; $i<=$field->{end}; $i+=$field->{interval}) {
		push(@vs, { option => $i, value => $i, selected => (($i == $default) ? 'SELECTED' : '') });
	}

	$vars->{$name} = \@vs;
}

# Handle arrays
sub form_setup_array {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	# Not sure how to handle info requests at moment
	return if $info;

	$vars->{$name} = {};

	# Setup index variable
	my $idx_var = $field->{index} or die "Invalid index variable for $name\n";
	
	my $num_cols = $default->{$idx_var} || 0;

	$form->form_setup_number($idx_var, $form->{config}->{locals}->{data}->{field}->{$idx_var}, $num_cols, $info, $vars->{$name});

	my @cols = ();

	# Force element(s) to be an array ref even if there is only one
	if ($field->{element} && !ref($field->{element})) {
		$field->{element} = [ $field->{element} ];
	}

	# Setup 'columns'
	for (my $i=0; $i<$num_cols; $i++) {
		my $col = { idx => $i };

		# Setup elements
		foreach my $e (@{ $field->{element} }) {
			my $element_fld = $form->{config}->{locals}->{data}->{field}->{$e};

			my $def = $default->{cols}->[$i]->{$e} || $element_fld->{default};

			my $cmd = '$form->form_setup_' . $element_fld->{type} . '($e, $element_fld, $def, $info, $col)';
			
			eval $cmd;

			print STDERR "Error: $@\n" if $@;
		}

		push(@cols, $col);
	}

	$vars->{$name}->{cols} = \@cols;
}

# Handle radiobuttons or checkboxes
sub form_setup_enum {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	if ($info) {
		$vars->{$name} = $default;

		return;
	}

	$vars->{$name} = {};

	my $set = 0;
	foreach (@{ $field->{value} }) {
		$vars->{$name}->{$_} = '';

		my $def = 0;

		if ((ref $default) && (exists($default->{$_}))) {
			$vars->{$name}->{$_} = 'CHECKED';
			
			$set++;
		}
	}

	if (!$set) {
		$vars->{$name}->{$default || $field->{default}} = 'CHECKED';
	}
	
}

# Handle a list like a enum
sub form_setup_list_enum {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	if ($info) {
		$vars->{$name} = $default;

		return;
	}

	# Convert arry default to hash default
	my $defhash = {};
	if (ref($default) eq 'ARRAY') {
		foreach (@{ $default }) {
			$defhash->{$_->{id}} = $_;
		}

		$default = $defhash;
	}

	$vars->{$name} = ();

	my $func = $name . 's_setup';	
	foreach (@{ $form->$func() }) {
		my $def = 0;

		$_->{checked} = '';
		if ((ref $default) && (exists($default->{$_->{id}}))) {
			$_->{checked} = 'CHECKED';
		}

		push(@{ $vars->{$name} }, $_);
	}
}

sub form_setup_text {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	$vars->{$name} = $default || '';
}

sub form_setup_number {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	$vars->{$name} = $default || '0';	
}

sub form_setup_string {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	$vars->{$name} = $default || '';
}

# Have to handle datetime as well
sub form_setup_date {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	my $dft;
	# Default might be of the form YYYY-MM-DD (HH:MM:SS)
	if (!ref($default) && ($default =~ /(\d{4})-(\d{2})-(\d{2})/)) {
		$dft = { day => $3, month => $2, month_name => $MONTHS->{$2}, year => $1 };
	} else {
		$dft = { days => '--', month => '--', month_name => '--', year => '----' };
	}

	# Hack for years 
	if ($dft->{year} eq '0000') {
		$dft->{year} = '----';
	}

	if ($info) {
		$vars->{$name} = $dft;

		return;
	}

	
	# Setup Days
	$vars->{$name}->{day} = ();
	$vars->{$name}->{day_val} = $dft->{day} || '';

	foreach (@$DAYS) {
		push(@{ $vars->{$name}->{day} }, {
			option   => $_,
			value    => $_,
			selected => ($_ == $dft->{day} ? 'SELECTED' : ''),
		});
	}

	# Setup Months
	$vars->{$name}->{month} = ();
	$vars->{$name}->{month_val} = $dft->{month} || '';

	foreach (@$MONTH_NUMS) {
		push(@{ $vars->{$name}->{month} }, {
			option_num => $_,
			option     => $MONTHS->{$_},
			value      => $_,
			selected   => ($_ == $dft->{month} ? 'SELECTED' : ''),
		});
	}

	# Setup Years
	$vars->{$name}->{year} = ();
	$vars->{$name}->{year_val} = $dft->{year} || '';

	foreach (@$YEARS) {
		push(@{ $vars->{$name}->{year} }, {
			option   => $_,
			value    => $_,
			selected => ($_ == $dft->{year} ? 'SELECTED' : ''),
		});
	}
}

# Have to handle datetime as well
sub form_setup_time {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	my $dft;

	# Default might be of the form (YYYY-MM-DD) HH:MM:SS
	if (!ref($default) && ($default =~ /(\d{2}):(\d{2}):(\d{2})/)) {
		$dft = { hour => $1, minute => $2, second => $3 };
	} else {
		$dft = { hour => '--', minute => '--', second => '--' };
	}

	if ($info) {
		$vars->{$name} = $dft;

		return;
	}

	foreach my $t (qw(hour minute second)) {
		$vars->{$name}->{$t} = ();

		foreach (@{ $TIME->{$t} }) {
			push(@{ $vars->{$name}->{$t} }, {
				option   => sprintf("%02d", $_),
				value    => $_,
				selected => ($_ == $dft->{$t} ? 'SELECTED' : ''),
			});
		}
	}
}

sub form_setup_datetime {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	$form->form_setup_date($name, $field, $default, $info, $vars);
	$form->form_setup_time($name, $field, $default, $info, $vars);
}

sub form_setup_user_dn {
	my ($form, $name, $field, $default, $info, $vars) = @_;

	if ($info) {
		$vars->{$name} = $default;

		return;
	}

	if (!ref $default) {
		my $rdn = (split(/=|,/, $default))[1];

		$default = { $field->{rdn} => $rdn };
	}

	if ($default->{$field->{rdn}}) {
		$vars->{$name} = {
			$field->{rdn} => $default->{$field->{rdn}},
			dn            => $field->{rdn} . "=" . $default->{$field->{rdn}} . "," . $field->{ou},
		};
	} else {
		$vars->{$name} = { $field->{rdn} => '', dn => '' };
	}
}

# Dummy function to prevent error
sub form_setup_timestamp { }

# Generic save form state
sub save_form_state {
	my ($form, $param_table, $op) = @_;

	$form->{state}->{$op} = {};

	foreach my $name (keys %{ $form->{config}->{locals}->{data}->{field} }) {
		my $field = $form->{config}->{locals}->{data}->{field}->{$name};

		next unless $form->field_setup($field, $op);

		my $cmd = '$form->save_state_' . $field->{type} . '($name, $field, $param_table, $form->{state}->{$op})';
		eval $cmd;

		print STDERR "Error: $@\n" if $@;
	}	
}

sub save_state_simple {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = $param_table->{$name};
}

sub save_state_list {
	save_state_simple(@_);
}

sub save_state_range {
	save_state_simple(@_);
}

sub save_state_latlon_str {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = join(" ", $param_table->{$name . '_deg'}, $param_table->{$name . '_min'}, $param_table->{$name . '_dir'});
}

sub save_state_dblist {
	save_state_simple(@_);
}

sub save_state_dbenum {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = $param_table->{$name};
}

sub save_state_number {
	save_state_simple(@_);
}

sub save_state_text {
	save_state_simple(@_);
}

sub save_state_string {
	save_state_simple(@_);
}

# Handle array variables
sub save_state_array {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = {};

	# Save index variable
	my $idx_var = $field->{index};
	$state->{$name}->{$idx_var} = $param_table->{$name . '_' . $idx_var};

	my @cols = ();

	# Force element(s) to be an array ref even if there is only one
	if ($field->{element} && !ref($field->{element})) {
		$field->{element} = [ $field->{element} ];
	}

	for (my $i=0; $i<$state->{$name}->{$idx_var}; $i++) {
		my $col = { idx => $i };

		foreach my $e (@{ $field->{element} }) {
			my $element_fld = $form->{config}->{locals}->{data}->{field}->{$e};

			# Add array prefix and index suffix to name
			my $element_name = join("_", $name, $e, $i);

			my $var = {};
			my $cmd = '$form->save_state_' . $element_fld->{type} . '($element_name, $element_fld, $param_table, $var)';
			
			eval $cmd;
			
			$col->{$e} = $var->{$element_name};

			print STDERR "Error: $@\n" if $@;
		}
		push(@cols, $col);
	}
		
	$state->{$name}->{cols} = \@cols;

	# Get rid of state if index is 0 - to help param_check
	delete $state->{$name} if ($state->{$name}->{$idx_var} == 0);
}

# Handle either radiobuttons (1 value) or checkboxes (multivalue)
sub save_state_enum {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = {};

	foreach (@{ $field->{value} }) {
		if ($param_table->{$name . '_' . $_} || ($param_table->{$name} eq $_)) {
			$state->{$name}->{$_} = $_;
		}
	}

	my @vs = keys %{ $state->{$name} };

	# Check if any value
	if (scalar(@vs) == 0) {
		delete $state->{$name};
	}

	# Check if single valued
	if (scalar(@vs) == 1) {
		$state->{$name} = shift @vs;
	}
}

sub save_state_list_enum {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = {};

	my $func = $name . 's_setup';	
	foreach (@{ $form->$func() }) {
		if ($param_table->{$name . '_' . $_->{id}}) {
			$state->{$name}->{$_->{id}} = $_;
		}
	}

	my @vs = keys %{ $state->{$name} };

	# Check if any value
	if (scalar(@vs) == 0) {
		delete $state->{$name};
	}		
}

sub save_state_date {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = join("-", $param_table->{$name . '_year'}, $param_table->{$name . '_month'}, $param_table->{$name . '_day'});
						   
	if ($state->{$name} !~ /\d{4}-\d{2}\-\d{2}/) {
		delete $state->{$name};
	}
}

sub save_state_time {
	my ($form, $name, $field, $param_table, $state) = @_;

	$state->{$name} = join(":", map { sprintf("%02d", $_) } ($param_table->{$name . '_hour'}, $param_table->{$name . '_minute'}, 
						   $param_table->{$name . '_second'}) );
}

sub save_state_datetime {
	my ($form, $name, $field, $param_table, $state) = @_;

	my %date_vals = ();
	$form->save_state_date($name, $field, $param_table, \%date_vals);

	my %time_vals = ();
	$form->save_state_time($name, $field, $param_table, \%time_vals);

	$state->{$name} = join(" ", $date_vals{$name}, $time_vals{$name});
}

# Generate current timestamp and save it
sub save_state_timestamp {
	my ($form, $name, $field, $param_table, $state) = @_;
	
	$state->{$name} = strftime("%Y%m%d%H%M%S", localtime);
}

# User Account (e.g LDAP dn)
sub save_state_user_dn {
	save_state_simple(@_);
}

# Recreate a query string from a given state
sub generate_query_string {
	my ($form, $form_name) = @_;

	my @vars = ();

	foreach my $f (keys %{ $form->{state}->{$form_name} }) {
		push(@vars, "$f=" . uri_escape($form->{state}->{$form_name}->{$f}));
	}

	return join("&", @vars);
}

# Generic form parameter check 
sub param_check {
	my ($form, $form_name) = @_;

	my @errs = ();

	my $state = $form->{state}->{$form_name};

	# Check parameters for validity
	foreach my $name (keys %{ $form->{config}->{locals}->{data}->{field} }) {
		my $field = $form->{config}->{locals}->{data}->{field}->{$name};
		
		next unless $form->field_setup($field, $form_name . '_mandatory');

		push(@errs, $field->{desc} . " is a mandatory field") unless $state->{$name};
	}

	return \@errs if scalar(@errs);

	return undef;
}

# New form parameter check - to allow highlighting of error fiels
sub form_param_check {
	my ($form, $form_name) = @_;

	my $params = $form->{state}->{$form_name};

	$form->{state}->{errors} = ();

	# Check parameters for validity
	foreach my $name (keys %{ $form->{config}->{locals}->{data}->{field} }) {
		my $field = $form->{config}->{locals}->{data}->{field}->{$name};
		
		next unless $form->field_setup($field, $form_name . '_mandatory');

		push(@{ $form->{state}->{errors} }, $name) unless defined($params->{$name});
	}

	return 1 if $form->{state}->{errors} && scalar(@{ $form->{state}->{errors} });
	
	return undef;
}

# Setup error strings
sub form_error_setup {
	my ($form, $param_table, $vars) = @_;

	if (!$param_table->{form_error}) {
		delete $form->{state}->{errors};
	}
	
	# Check if any errors exist and highlight fields
	if ($form->{state}->{errors}) {
		foreach (@{ $form->{state}->{errors} }) {
			$vars->{$_ . '_error'} = 'error';
		}
		
		$vars->{error_message} = [ 'dummy' ];
		
		delete $form->{state}->{errors};
	}
}

# Generic remove 'any' options
sub form_clean_search {
	my ($form, $form_name) = @_;

	my $state = $form->{state}->{$form_name};

 	foreach my $name (keys %{ $form->{config}->{locals}->{data}->{field} }) {
		my $field = $form->{config}->{locals}->{data}->{field}->{$name};
		
		next unless $form->field_setup($field, $form_name);

		my $cmd = '$form->clean_search_' . $field->{type} . '($name, $field, $state)';

		eval $cmd;

		print STDERR "Error: $@\n" if $@;
	
	}
}

sub clean_search_list {
	my ($form, $name, $field, $state) = @_;

	delete $state->{$name} if $state->{$name} eq 'any';
}

sub clean_search_range {
	my ($form, $name, $field, $state) = @_;

	delete $state->{$name} if $state->{$name} eq 'any';	
}

sub clean_search_number { 
	my ($form, $name, $field, $state) = @_;

	delete $state->{$name} unless $state->{$name} =~ /^\d+$/;
}

sub clean_search_string {
	my ($form, $name, $field, $state) = @_;

	delete $state->{$name} unless $state->{$name} !~ /^\s*$/;
}

sub clean_search_text {
	clean_search_string(@_);
}

sub clean_search_dbenum {
	clean_search_string(@_);
}

sub clean_search_enum {
	my ($form, $name, $field, $state) = @_;

	# Convert to any array for OR'd search
	if (ref $state->{$name}) {
		my @ks = keys %{ $state->{$name} };

		$state->{$name} = \@ks;
	} else {
		delete $state->{$name} if $state->{$name} eq 'any';
	}
}

sub clean_search_list_enum {
	my ($form, $name, $field, $state) = @_;
	
	if (ref $state->{$name}) {
		my @ks = keys %{ $state->{$name} };

		$state->{$name} = \@ks;

		delete $state->{$name} unless scalar(@ks);
	} else {
		delete $state->{$name};
	}
}

# Check date is of required form
sub clean_search_date {
	my ($form, $name, $field, $state) = @_;

	if ($state->{$name} !~ /\d{4}-\d{2}\-\d{2}/) {
		delete $state->{$name};
	}
}

# Generate seconds from time
sub clean_search_time {
	my ($form, $name, $field, $state) = @_;

	return if (!ref($state->{$name}));

	my ($hour, $min, $sec) = ($state->{$name}->{hour}, $state->{$name}->{minute}, $state->{name}->{second});

	# Convert to seconds
	$state->{$name} = $sec + 60 * ($min + 60 * $hour)
}

# Generate timestamp from datetime
sub clean_search_datetime {
	my ($form, $name, $field, $state) = @_;

	my ($year, $month, $day, $hour, $min, $sec) = split(/-|:|\ /, $state->{$name});
	
	# Convert to timestamp
	$state->{$name} = timegm($sec, $min, $hour, $day, $month - 1, $year - 1900);

}

# Nothing to do
sub clean_search_timestamp  { }
sub clean_search_dblist     { }
sub clean_search_latlon_str { }

# Get rid of extraneous info, just leave list of entries
sub clean_search_array { 
	my ($form, $name, $field, $state) = @_;

	# Remove cols / count entry
	my @as = ();
	foreach (@{ $state->{$name}->{cols} }) {
		my %a = ();

		foreach my $k (keys %$_) {
			next if $k eq 'idx';

			$a{$k} = $_->{$k};
		}

		push(@as, \%a);
	}

	$state->{$name} = \@as;

	delete $state->{$name} if scalar(@as) == 0;
}

# Array Handling
# Increase number of array columns
sub inc_array {
	my ($form, $form_name, $array) = @_;

	# Get array index var
	my $idx_var = $form->{config}->{locals}->{data}->{field}->{$array}->{index};

	$form->{state}->{$form_name}->{$array}->{$idx_var}++;
}

# Remove array columns
sub rm_array {
	my ($form, $form_name, $array, $param_table) = @_;

	my $state = $form->{state}->{$form_name}->{$array};

	# Get array index var
	my $idx_var = $form->{config}->{locals}->{data}->{field}->{$array}->{index};

	# Build new column list
	my @cols = ();

	# New column index
	my $new_idx = 0;

	for (my $i=0; $i<$state->{$idx_var}; $i++) {
		my $del = join("_", 'del', $array, $i);

		# Skip if marked for deletion
		next if $param_table->{$del};

		# Save and correct index
		push(@cols, $state->{cols}->[$i]);

		$cols[$new_idx]->{idx} = $new_idx;

		$new_idx++;
	}

	# Correct total and replace old cols with new
	$state->{$idx_var} = $new_idx;

	$state->{cols} = \@cols;
}

1;
__END__
