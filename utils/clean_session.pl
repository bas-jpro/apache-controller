#!/packages/perl/current/bin/perl -w
# Clear out old sessions in database
# $Id$
#

use Apache::Session::MySQL;
use Apache::Session::Postgres;
use Config::Simple;
use lib '/data/web/webapps/controller/current/perl';
use Apache::Controller::DB;
use Fcntl;

use strict;

my %SESSION_TYPES = ( mysql => 'Apache::Session::MySQL', Pg => 'Apache::Session::Postgres' );

if (scalar(@ARGV) < 3) {
    die "Usage: $0 <config file> <session age> <database name> [<database name>...] \n";
}

my $cfg_file = shift @ARGV;
my $age = shift @ARGV;

# Read defaults from Config File
my $cfg = new Config::Simple(filename => $cfg_file, mode => O_RDONLY);

# Configuration file error
die "Error in configuration file: $cfg_file\n" if !$cfg;

# Get DB information
my $dbinfo = $cfg->param(-block => 'db');

# Check each database for old sessions
foreach my $d (@ARGV) {
	my $db = Apache::Controller::DB->new($d, $dbinfo);

	my $data_source = "dbi:$dbinfo->{type}:dbname=$d;host=$dbinfo->{host}";

	my $expire_time = time() - $age;

	$db->query('SELECT trim(id) FROM sessions');
	while ($db->next_record()) {
		my %session;

		tie %session, $SESSION_TYPES{$dbinfo->{type}}, $db->f(0), {
			DataSource     => $data_source,
			UserName       => $dbinfo->{user},
			Password       => $dbinfo->{passwd},
			LockDataSource => $data_source,
			LockUserName   => $dbinfo->{user},
			LockPassword   => $dbinfo->{passwd},
			IDLength       => 16,
			Commit         => 1,
		}; 

		if ($session{timestamp} < $expire_time) {
			tied(%session)->delete;
		}

		untie(%session);
	}
}

0;
