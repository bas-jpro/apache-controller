# Apache MVC 'Controller' module 
# Copyright (c) 2003, 2004, 2005, 2006 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# $Id$
#

	
package Apache::Controller;
use strict;

use Apache::Controller::Template;
use Apache::Controller::PDF qw(generate_pdf generate_sheet_pdf);
use Apache2::Const -compile => qw(:common :methods);
use Config::Simple;
use Fcntl;
use Apache::XMLCache;
use CGI::FastTemplate;
use Apache2::RequestRec;
use Apache2::Request;
use Apache2::SubRequest;
use Apache2::Response;
use Apache2::RequestIO;
use Apache2::Access;
use Apache2::Response;
use Apache::Session::MySQL;
use Apache::Session::Postgres;
use Apache2::Cookie;
use Time::HiRes qw(gettimeofday tv_interval);
use Global;

use Apache::Controller::DB;
use Apache::Controller::LDAP;

# For debugging
use Data::Dumper;

my $GLOBAL_PREFIX = 'G_';
my $TKT_TOKEN_ENV = 'REMOTE_USER_TOKENS';
my %SESSION_TYPES = ( mysql => 'Apache::Session::MySQL', Pg => 'Apache::Session::Postgres' );
my $IDLENGTH      = 16;

# FIXME: make generic 
sub elapsed_log {
	my ($t0, @msgs) = @_;

	#print STDERR "$$: Elapsed time: [" . sprintf("%0.6f", tv_interval($t0)) . "] - " . join(" ", @msgs) . "\n";

	return [gettimeofday];
}

sub handler : method {
	my ($class, $r) = @_;

	$| = 1;

	my $pt0 = [gettimeofday];
	my $t0 = [gettimeofday];

	# Split URL path
	my @ps = split("/", $r->uri);

	my $cookies = Apache2::Cookie->fetch;
	$t0 = elapsed_log($t0, "Cookies");

	# Setup useful structure to pass to functions
	my $config = {
		request   => $r,
		location  => join("/", shift @ps, $ps[0]),
		name      => shift @ps,
		level     => shift @ps,
		op        => (shift @ps) || 'index',
		path_info => \@ps,
		session   => {},
		cookies   => $cookies,
	};

	
	# Load database info from controller config file
	my $dbinfo = _get_dbinfo($r->dir_config('ControllerCfg'));

	$t0 = elapsed_log($t0, "DBINFO");

	my $db = Apache::Controller::DB->new($dbinfo->{name}, $dbinfo);

	$t0 = elapsed_log($t0, "DB");

	# Read in local app details
	my $app = $db->select_row("SELECT * FROM $dbinfo->{modules_table} WHERE name='$config->{name}' AND " .
							  "site='" . $config->{request}->hostname . "'");

	$t0 = elapsed_log($t0, "DB read");

	die "No such module $config->{name}\n" unless $app->{name};

	$config->{templatedir} = $app->{templatedir};

	# Read in XML definitions (from Cache if possible)
	$config->{locals}  = Apache::XMLCache::get_xml_file($app->{intfile})    if $app->{intfile};
	
	$t0 = elapsed_log($t0, "XML intfile");

	$config->{globals} = Apache::XMLCache::get_xml_file($app->{globalfile}) if $app->{globalfile};

	$t0 = elapsed_log($t0, "XML globalfile");

	# Read in modules needed
	foreach (keys %{ $config->{locals}->{modules} }) {
		require $_;
		$t0 = elapsed_log($t0, "Module load [$_]");
	}

	# Setup up Apache Request Object
	$config->{apr} = Apache2::Request->new($r);

	# Convert post to get for subrequests
	if ($config->{request}->method() eq 'POST') {
		# Check for uploads
		$config->{upload} = $config->{apr}->upload;

		$config->{query_string} = $config->{apr}->body;

		$config->{request}->method('GET');
		$config->{request}->method_number(Apache2::Const::M_GET);
		$config->{request}->args($config->{query_string});
		$config->{request}->headers_in->unset('Content-Length');
	}

	# Save query-string
	if ($config->{request}->method() eq 'GET') {
		$config->{query_string} = $config->{request}->args;
	}

	$t0 = elapsed_log($t0, "config");

	# Get session data if any/valid, otherwise create new
	start_session($config, $dbinfo);

	$t0 = elapsed_log($t0, "Session start");

	# Setup cookie 
	# If path is $config->{location} internal redirects screw this up
	# Which one is better ?
	my $cookie = Apache2::Cookie->new($r, -name => uc($app->{name}) . '_SESSION_ID', 
									  -value => $config->{session}->{_session_id}, -domain => $r->hostname, -path => '/');

	# Set cookie header
	$cookie->bake($r);

	$t0 = elapsed_log($t0, "Cookie");

	# Access Control
	my $res = setup_user_access($config);

	$t0 = elapsed_log($t0, "Access control");

	my $class = new_class($config);

	$t0 = elapsed_log($t0, "New class");

	# Display levels page if no level
	if (!$config->{level}) {
		$config->{op} = 'levels';
		show_template($config, $class, undef, global_vars($config, $dbinfo), $t0);	

		end_session($config);
		return Apache2::Const::OK;
	} 

	if ($res != Apache2::Const::OK) {
		end_session($config);
		return $res;
	}

	# For modperl2 need to copy params into a hash because APR::Request::Param::Table doesn't
	# allow modification
	my $param_table_ref = $config->{apr}->param;
	my $param_table = {};

	foreach my $k (keys %$param_table_ref) {
		# Check if already defined - i.e is multi valued
		if (defined($param_table->{$k})) {
			next if ref($param_table->{$k});
			my @vals = $config->{apr}->param($k);
			$param_table->{$k} = \@vals;
		} else {
			$param_table->{$k} = $param_table_ref->{$k};
		}
	}
	
	# Check for form action
	my $form_op = _check_form_action($config, $param_table);

	# Check user/level is allow to access specific function
	$res = _check_restrict($form_op || $config->{op}, $config);

	if ($res != Apache2::Const::OK) {
		end_session($config);
		return $res;
	}

	if ($form_op) {
		my $next_page = $param_table->{"next_page_" . $form_op};
		# If next page has been set do action
		if ($next_page) {
			
			my $err = undef;
			eval '$err = $class->' . $form_op . '($param_table, @{ $config->{path_info} })';
			
			if ($@) {
				print STDERR "Error: $@\n";
			}
			
			if ($err) {
				$config->{op} = 'error';
				$config->{error_message} = $err;
			} else {
				# Allow redirect page to read session data
				my $session_id = $config->{session}->{_session_id};
				end_session($config);
		
				# The class function may have changed next_page_$form_op so use param_table not $next_page
				# set environment variable so we can use it in new handler
				my $name = uc($config->{name}) . "_SESSION_ID";
				$r->subprocess_env($name => $session_id);

#				print STDERR "Redirecting to " . $param_table->{"next_page_" . $form_op} . "\n";
				$config->{request}->internal_redirect($param_table->{"next_page_" . $form_op});
				return Apache2::Const::OK;
			}
		}
	}		   

	show_template($config, $class, $param_table, global_vars($config, $dbinfo), $t0);

	end_session($config);

	# print STDERR "$$: Page time: [" . tv_interval($pt0) . "]\n";

	return Apache2::Const::OK;
}

sub _check_form_action {
	my ($config, $param_table) = @_;

	my $op = undef;

	# Check for a form action unless an internal_redirect or a form error 
	if ($config->{request}->is_initial_req && !$param_table->{form_error}) {

		# Get real op name ('CMD_...')
		foreach my $k (keys %$param_table) {
			if ($k =~ /^CMD_(.+)$/) {
				$op = $1;
			}
		}
		
		# Test for images
		if (($op =~ /^(.+)\.x$/) || ($op =~ /^(.+)\.y$/)) {
			$op = $1;

			$config->{image} = { 
				'x' => $param_table->{'CMD_' . $1 . '.x'}, 
				'y' => $param_table->{'CMD_' . $1 . '.y'},
			}; 
		}
	}

	return $op;
}

sub show_template {
	my ($config, $class, $param_table, $global_vars, $t0) = @_;

	my @ps = @{ $config->{path_info} };
	
	# Create Template
	# FIXME: Handle error templates
	$config->{tpl} = Apache::Controller::Template->new($config->{templatedir}, $config->{name}, $config->{analyst}->{level}, 
													   $config->{op}, @ps);
   
	# Define some useful variables
	$config->{tpl}->assign('', '', { 
		G_HOSTNAME     => $config->{request}->hostname .':' . $config->{request}->get_server_port, 
		G_OP           => $config->{op},
		G_PATH_INFO    => join("/", @{ $config->{path_info} }),
		G_LOCATION     => $config->{location},
		G_ANALYST_USER => $config->{analyst}->{user},
		G_LEVEL        => $config->{analyst}->{level} || 'guest',
		
		# For Lookups / Error forms etc
		G_QUERY_STRING => $config->{query_string},
		
		# Per Session CSS or default
		G_CSS_FILE     => $config->{session}->{_CSS} || $config->{locals}->{css} || '',
	});
	
	# Setup global scalar variables
	$config->{tpl}->assign('', '', $global_vars);
	
	if ($config->{op} eq "error") {
		$config->{tpl}->assign('', '', { msg => $config->{error_message} });
	}

	# Attempt to call class specific function setup, include old params if they exist
	my $vars = undef;
	my $func = '$vars = $class->' . $config->{op} . '_setup($param_table, @ps)';

#	print STDERR "Func: $func\n";

	eval $func;

	if ($@) {
		print STDERR "Template Error: $@\n";

		return;
	}

	# FIXME: Tidy up file types - switch / lookup table ?
	# Check for special file types
	if (defined($vars->{_PDF})) {
		# Send header
		$config->{request}->content_type('application/pdf');

		# Print PDF
		print $vars->{_PDF};
		
		return;
	}

	if (defined($vars->{_PDF_TEMPLATE})) {
		# Send header
		$config->{request}->content_type('application/pdf');

#		print STDERR "Page Time: " . sprintf("%0.2f", tv_interval($t0, [gettimeofday])) . "\n";

		print generate_pdf($config, $vars->{_PDF_TEMPLATE}, $config->{op}, $vars->{_PDF_VARS}, $t0);

		return;
	}

	if (defined($vars->{_PDF_SHEET_TEMPLATE})) {
		# Send header
		$config->{request}->content_type('application/pdf');

		print generate_sheet_pdf($config, $vars->{_PDF_SHEET_TEMPLATE}, $config->{op}, $vars->{_PDF_VARS});

		return;
	}

	if (defined($vars->{_CSV})) {
		# Send header
		$config->{request}->content_type('text/csv');
		
		# Send Filename if given 
		if ($vars->{_CSV_FILENAME}) {
			$config->{request}->headers_out->{'Content-disposition'} = 'attachment; filename="' . $vars->{_CSV_FILENAME} . '"';
		}

		# Print CSV
		print $vars->{_CSV};

		return;
	}

	if (defined($vars->{_CMD})) {
		# Let routine do all work, including sending content type
		my $cmd = '$class->' . $vars->{_CMD} . '($param_table, @ps)';

		eval $cmd;

		if ($@) {
			die "Command error: $@\n";
		}

		return;
	}

	if (defined($vars->{_IMAGE})) {
		# Send header
		$config->{request}->content_type('image/' . $vars->{_IMAGE_TYPE});

		# Send Content Disposition if filename given for user to save image
		if (defined($vars->{_IMAGE_FILENAME})) {
			$config->{request}->headers_out->{'Content-disposition'} = 'attachment; filename="' . $vars->{_IMAGE_FILENAME} . '"';
		}

		# Send image;
		print $vars->{_IMAGE};
		
		return;
	}

	if (defined($vars->{_XML})) {
		$config->{request}->content_type('text/xml');

		# print XML
		print $vars->{_XML};

		return;
	}

	# FIXME: Maybe this could do all but _CMD ?
	if (defined($vars->{_FILE})) {
		$config->{request}->content_type($vars->{_FILE_TYPE});
		$config->{request}->set_content_length(-s $vars->{_FILE});
		$config->{request}->sendfile($vars->{_FILE});

		return;
	}

	# Default print HTML
	# Generate template variables
	$config->{tpl}->assign($config->{op}, '', $vars);

	# Setup header
	my $hdr_vars = $class->header_setup($param_table, $config->{op}, @ps);
	$config->{tpl}->assign('', '', $hdr_vars);

	# Setup Footer
	my $ftr_vars = $class->footer_setup($param_table, $config->{op}, @ps);
	$config->{tpl}->assign('', '', $ftr_vars);

	# Page Generation Time
	$config->{tpl}->assign('', '', { PAGE_GENERATED_IN => sprintf("%0.2f", tv_interval($t0, [gettimeofday])) } );

	# Send header
	$config->{request}->content_type('text/html; charset=UTF-8');

	# Parse & print template
	$config->{tpl}->parse();
	$config->{tpl}->print();
}

sub global_vars {
	my ($config, $dbinfo) = @_;

	my $globalvar = $config->{globals}->{globalvar};

	return {} unless $globalvar->{db};

	my $global = Global->new($dbinfo, $globalvar->{db}, $globalvar->{table});

	my %vars = {};

	foreach (@{ $global->List() }) {
		$vars{$GLOBAL_PREFIX . $_->{var}} = $_->{value};
	}

	return \%vars;
}

# Create an instance of the class of objects the XML file describes
sub new_class {
	my $config = shift;

	my $class  = undef;
	eval '$class = ' . $config->{locals}->{class} . '->new($config)';
	die "Can't create class: $@\n" if $@;
	
	return $class;
}

sub _get_dbinfo {
	my $filename = shift;

	my $cfg = new Config::Simple(filename => $filename, mode => O_RDONLY);
	die "Missing or invalid controller configuration file: $filename\n" if !$cfg;
 
	# Read Values from Config file
	return $cfg->param(-block => 'db');
}

sub setup_user_access {
	my $config = shift;

	if (!$config->{level} || ($config->{level} eq 'guest')) {
		$config->{analyst} = { user => 'guest', level => 'guest' };
		return Apache2::Const::OK;
	}

	$config->{analyst} = {
		user => $config->{request}->user,
		level => $config->{level}
	};

	# Check for specific Access Control 
	my $notes = $config->{request}->notes;
	return Apache2::Const::OK if $notes->get('Apache::Controller::AccessControl');
	
	# Basic Authentication
	my ($res, $passwd) = $config->{request}->get_basic_auth_pw();
	$config->{analyst}->{passwd} = $passwd;
	return Apache2::Const::OK if $res == Apache2::Const::OK;

	# Check for mod_auth_tkt login
	my $val = $config->{request}->subprocess_env($TKT_TOKEN_ENV);
	my $user = $config->{request}->user;

	return Apache2::Const::OK if ($user && ($val eq 'TktLogin'));

	return Apache2::Const::DECLINED;
}

sub _check_restrict {
	my ($op, $config) = @_;

	return Apache2::Const::OK unless $op;

	my $restrict = $config->{locals}->{restrict};

	# If op has been restricted only allow if level matches
	if ($restrict->{op}->{$op}) {
		foreach my $l (@{ $restrict->{op}->{$op}->{level} }) {
			return Apache2::Const::OK if $l eq $config->{analyst}->{level};
		}

		return Apache2::Const::FORBIDDEN;
	}

	return Apache2::Const::OK;
}

# Session Management
sub start_session {
	my ($config, $dbinfo) = @_;

	my $sid = undef;
	my $name = uc($config->{name}) . "_SESSION_ID";

	# Generate session - from current id if possible or new one
	if ($config->{cookies}->{$name}) {
		$sid = $config->{cookies}->{$name}->value;
	}

	# Try From REDIRECT ENV variable if we're in a subprocess
	if (!$sid && ($config->{request}->subprocess_env("REDIRECT_$name"))) {
		$sid = $config->{request}->subprocess_env("REDIRECT_$name");
	}

	my $opts = _session_connect_opts($dbinfo);
	my $type = _get_session_type($dbinfo);

	# prevent infinite loop
	my $cnt = 20;
	do {
		eval { tie %{ $config->{session} }, $type, $sid, $opts; };

		# Create new session if old one expired
		$sid = undef if $@;

		$cnt--;
	} while ($cnt && $@);

	if ($@) {
		die "Failed: $@\n";
	}
}

# Update Timestamp to force update & untie
sub end_session {
	my $config = shift;

	# Force write of session data
	$config->{session}->{timestamp} = time();

	# Release Session locks
	untie(%{ $config->{session} });
}

# Broken out so Apache::Controller::Interface can use it
sub _session_connect_opts {
	my ($dbinfo) = @_;

	my $data_source = "dbi:$dbinfo->{type}:dbname=$dbinfo->{sessiondb};host=$dbinfo->{host}";

	return {
		DataSource     => $data_source,
		UserName       => $dbinfo->{user},
		Password       => $dbinfo->{passwd},
		LockDataSource => $data_source,
		LockUserName   => $dbinfo->{user},
		LockPassword   => $dbinfo->{passwd},
		IDLength       => $IDLENGTH,
		TableName      => $dbinfo->{session_table},
		Commit         => 1,
	};	
}

sub _get_session_type {
	my $dbinfo = shift;

	return $SESSION_TYPES{$dbinfo->{type}};
}

1;
__END__
