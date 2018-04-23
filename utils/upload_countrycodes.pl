#!/usr/bin/perl -w
# Convert iso3166-countrycodes to mysql statements for uploading
# JPRO 12/01/2006
#

use strict;

my $divisor = '-------------------------------------------';

# Read header
while (<>) {
	last if /$divisor/;
}

# Read codes
while (<>) {
	last if /$divisor/;
	chomp;

	my ($number, $three_code, $two_code, @names) = reverse split;
	next unless $two_code && (@names);

	# Names is reversed as well
	my $name = join(" ", reverse @names);
	$name =~ s/\'/\\\'/g;

	print "INSERT INTO countrycodes VALUES(null, '$two_code', '$name');\n";
}

0;

