#!/usr/local/bin/perl -w
# Modify modules table
# $Id$
#

use Config::Simple;
use lib '/data/web/webapps/controller/current/perl';
use Apache::Controller::DB;
use Fcntl;
use Term::Prompt;

use strict;

my @COLS = qw(Name Site TemplateDir GlobalFile IntFile Title);
my $DISP_SIZE = 16;
my $CFG_FILE = '/data/web/webapps/controller/current/conf/controller.conf';

my $action = $ARGV[0];
die "Usage: $0 list|del|add|modify\n" unless $action;

# Read defaults from Config File
my $cfg = new Config::Simple(filename => $CFG_FILE, mode => O_RDONLY);

# Configuration file error
die "Error in configuration file: [$CFG_FILE]\n" if !$cfg;

# Get DB information
my $dbinfo = $cfg->param(-block => 'db');
my $db = Apache::Controller::DB->new($dbinfo->{name}, $dbinfo);

if ($action eq 'list') {
	# Get list of existing modules
	$db->query("SELECT * FROM modules");

	while ($db->next_record()) {
		for (my $c=0; $c<scalar(@COLS); $c++) {
			my $padding = (" " x ($DISP_SIZE - length($COLS[$c]))); 
			print $COLS[$c], "$padding: ", $db->f($c), "\n";
		}
		print "\n";
	}
}

if ($action eq 'add') {
	my %cs = ();

	foreach my $c (@COLS) {
		$cs{lc($c)} = prompt('x', "Value for column '$c' :", '', '');
	}

	$db->prepare("INSERT INTO modules VALUES(" . join(", ", map { '?' } @COLS) . ")");
	$db->execute((map { $cs{lc($_)} } @COLS));
}

0;
