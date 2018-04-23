#!/usr/local/bin/perl -w
# Check XML syntax 
# JPRO 03/02/2006
#

use strict;
use XML::Simple;
use Data::Dumper;

die "Usage: $0 <file name>\n" unless scalar(@ARGV) == 1;

my $xml = XMLin($ARGV[0]);

print Dumper($xml), "\n";

0;

