#!/usr/local/bin/perl -w
#
# Testing Apache Session
#

use Apache::Session::MySQL;
use lib '/data/web/webapps/controller/current/perl';
use Apache::Controller::DB;
use Fcntl;
use Config::Simple;
use Data::Dumper;

use strict;

if (scalar(@ARGV) < 3) {
    die "Usage: $0 <conf file> <database> <add|list|del>\n";
}

my $cfg_file = shift @ARGV;
my $database = shift @ARGV;

# Read defaults from Config File
my $cfg = new Config::Simple(filename => $cfg_file, mode => O_RDONLY);
                                                                                
# Configuration file error
die "Error in configuration file: $cfg_file\n" if !$cfg;
                                                                                
# Get DB information
my $dbinfo = $cfg->param(-block => 'db');

my %session;
my $options = {
    DataSource => "dbi:mysql:database=$database:host=$dbinfo->{host}",
    UserName   => $dbinfo->{user},
    Password   => $dbinfo->{passwd},
    LockDataSource => "dbi:mysql:database=$database:host=$dbinfo->{host}",
    LockUserName   => $dbinfo->{user},
    LockPassword   => $dbinfo->{passwd},
    IDLength => '16',
};

if ($ARGV[0] eq "add") {
    tie %session, 'Apache::Session::MySQL', undef, $options;

    print "Added session: " . $session{_session_id} . "\n";

    $session{timestamp} = time();

    untie(%session);
    exit;
}

if ($ARGV[0] eq "list") {
    my $db = Apache::Controller::DB->new($database, $dbinfo );
    
    $db->query("SELECT id FROM sessions");
    while ($db->next_record()) {
		tie %session, 'Apache::Session::MySQL', $db->f(0), $options;
		
		print "Session: " . $db->f(0) . ": " , Dumper(\%session), "\n";
		
		untie(%session);
    }
    exit;
}

if ($ARGV[0] eq "del") {
    die "Usage: $0 <database> del <id>\n" unless $ARGV[1];

    tie %session, 'Apache::Session::MySQL', $ARGV[1], $options;

    tied(%session)->delete;

    print "Session: $ARGV[1] deleted\n";

    untie(%session);

    exit;
}

die "Usage: $0 <conf file> <database> <add|list|del>\n";

0;
