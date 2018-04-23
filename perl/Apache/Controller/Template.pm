# Apache 'Controller' Template module 
# Copyright (c) 2004, 2005 Jeremy Robst <jpr@robst.org>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# $Id$
#

package Apache::Controller::Template;
@ISA = qw(Exporter);
@EXPORT_OK = qw(template_assign);

use strict;
use Data::Dumper;
use CGI::FastTemplate;

sub new {
	my ($class, $dir, $name, $level, @ps) = @_;

	unshift(@ps, '.');

	# If no path info then add index
	if (scalar(@ps) == 1) {
		push(@ps, 'index');
	}

#	print STDERR "PS: ", join(":", @ps), "\n";

	my $tpl = bless {
		dir       => $dir,
		name      => $name,
		level     => $level,
		ps        => \@ps,
		cgi_tpl   => CGI::FastTemplate->new($dir),
		header    => '',
		content   => '',
		footer    => '',
		includes  => {},
	}, $class;

	$tpl->{cgi_tpl}->no_strict();

	# Load & defined standard page templates
	foreach my $t (qw(header content footer)) {
		$tpl->{$t} = $tpl->find_template_file($t);
		
#		print STDERR "Defining $t => " . $tpl->{$t} . "\n";
		$tpl->{cgi_tpl}->define($t => $tpl->{$t});
	}

	# Look for includes and define those as well
	$tpl->define_includes();
 
	return $tpl;
}

sub find_template_file {
	my ($tpl, $name) = @_;

	my $base = $tpl->{dir}. '/' . $tpl->{name};
	my $dir = '';
	my $file = '';

#	print STDERR "Looking for template for $name\n";

	foreach (@{ $tpl->{ps} }) {
		# Security check - necessary ?
		die "Invalid path info : $_\n" if /^\.\.$/;

		$dir .= "$_/";

#		print STDERR "Dir: $dir, base: $base\n";

		# Stop when directories run out
		last unless -d "$base/$dir";

		# General template
		$file = $tpl->{name} . "/$dir$name.tpl" if -r "$base/$dir$name.tpl";

#		print STDERR "Looking for [$file]\n";

		# Check for level specific template
		$file = $tpl->{name} . "/$dir" . $tpl->{level} ."_$name.tpl" if -r "$base/$dir" . $tpl->{level} . "_$name.tpl";
		
#		print STDERR "Looking for [$file]\n";
	}
	
#	print STDERR "Found Template: $file\n";

	print STDERR "Didn't find template for $name\n" if (!$file);
 
	return $file;
}

sub define_includes {
	my $tpl = shift;
	
	$tpl->{includes} = {};

	my $base = $tpl->{dir};

	# Start with standard templates
	foreach my $t (qw(header content footer)) {
		my $template = $base . '/' . $tpl->{$t};

#		print STDERR "Scanning: $template\n";

		open(TP, "< $template") or die "Cannot read: $template\n";
		while (<TP>) {
			if (/\$INCLUDE_([A-Z0-9\_]+)/) {
				$tpl->{includes}->{"include_$1"} = $tpl->find_template_file(lc($1));
			}
		}
		close(TP);
	}

	# Define all include files found
	foreach my $i (keys %{ $tpl->{includes} }) {
		$tpl->{cgi_tpl}->define($i => $tpl->{includes}->{$i});
	}
}

sub parse {
	my $tpl = shift;

	# Parse includes
	foreach my $i (keys %{ $tpl->{includes} }) {
		$tpl->{cgi_tpl}->parse(uc($i) => $i);
	}

	# Parse content, footer, header
	$tpl->{cgi_tpl}->parse(CONTENT => 'content');
	$tpl->{cgi_tpl}->parse(FOOTER => 'footer');
	$tpl->{cgi_tpl}->parse(HEADER => 'header');
}

sub print {
	my $tpl = shift;

	$tpl->{cgi_tpl}->print();
}

sub fetch {
	my $tpl = shift;

	return $tpl->{cgi_tpl}->fetch('HEADER');
}

# Assign values to variables 
# Recursively walk input
sub assign {
	my ($tpl, $op, $prefix, $var) = @_;
	$prefix = '' unless $prefix;

#	print STDERR "template_assign: $op, $prefix, ", Dumper($var), "\n";

	$_ = ref($var);
	if ($_) {
	  CASE: {
		  /HASH/ and do { 
			  $prefix .= '_' if $prefix ne '';
			  
			  # Sort by type - e.g scalar first, then hash, then array
			  foreach my $k (sort { ref($var->{$a}) cmp ref($var->{$b}) } keys %$var) {
				  $tpl->assign($op, $prefix . $k, $var->{$k});
			  }
			  
			  last CASE;
		  };

		  /ARRAY/ and do {
			  # Look for template 
			  my $tpl_name = $prefix;
			  my $file = $tpl->find_template_file($tpl_name);

			  # Skip if no template exists
			  last CASE unless $file;

			  $tpl->{cgi_tpl}->define($tpl_name => $file);

			  # Clear any previous arrays
			  $tpl->{cgi_tpl}->clear(uc($tpl_name . "S"));

			  foreach my $v (@{ $var }) {
				  # Save list of keys to clear once the array element has been parsed
				  my @ks = ();
				  if (ref($v) eq 'HASH') {
					  @ks = map { uc($prefix . '_' . $_) } keys(%$v);
				  }

				  $tpl->assign($op, $prefix, $v);

				  # Parse template
				  # print STDERR "Parsing " . uc($tpl_name . "S") . " -> .$tpl_name\n";
				  $tpl->{cgi_tpl}->parse(uc($tpl_name . "S") => ".$tpl_name");

				  $tpl->{cgi_tpl}->clear(@ks) if (scalar(@ks));
			  }

			  last CASE;
		  }
	  }

	} else {
		# print STDERR "Defining: " . uc($prefix) . " => $var\n" if uc($prefix) ne "JPEGPHOTO";
		$tpl->{cgi_tpl}->assign(uc($prefix) => $var);
	}
}


1;
__END__
