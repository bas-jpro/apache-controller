# Apache::Controller XML Caching Code
# Copyright (c) 2000, 2005, 2006, 2011 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# $Id$
#

package Apache::XMLCache;
use strict;

use XML::Simple;

my %XMLCache;

sub get_xml_file {
	my $filename = shift @_;

	return undef if !$filename;

	if (!defined($XMLCache{$filename})) { 
		$XMLCache{$filename} = XMLin($filename, ForceArray => [ 'form', 'level', 'op', 'modules' ]); 
	}
	
	return $XMLCache{$filename};
}

1;
__END__
