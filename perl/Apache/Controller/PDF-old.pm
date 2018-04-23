# Apache Controller PDF module
# Copyright (c) 2004,2006 Jeremy Robst <jpro@robst.me.uk>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# v1.0 JPR 28/04/2004 Initial release.
# v2.0 JPR 31/05/2004 Added page size/orientation to XML file
#                     General warning fixes
#                     Added get_stringOpts
#                     Allow x1/y1 or x/y in string/stringLeft/stringRight 
#                     Add quote_vals to handle nested structures
# v2.1 JPR 27/06/2004 Added generate_sheet_pdf
# v2.2 JPR 28/06/2004 Added '-' if splitting a word
# v3.0 JPR 15/01/2006 Modified for new Apache::Controller::Template
#

package Apache::Controller::PDF;
@ISA = qw(Exporter);
@EXPORT_OK = qw(generate_pdf generate_sheet_pdf);

use strict;
use XML::Simple;
use XML::Quote qw(:all);
use Time::HiRes qw(gettimeofday tv_interval);
use PDF::Report;
use Storable qw(dclone);

use Data::Dumper;

my @STR_OPTS = qw(color underline indent rotate);

# Generate PDF given XML file as template
sub generate_pdf {
	my ($config, $op, $vars) = @_;

	my $t0 = [gettimeofday];

	my $template = $config->{name} . "/$template_file.tpl";
	$config->{tpl}->define($config->{name} => $template);

	$vars = quote_vals($vars);

	template_assign($config, $op, '', $vars);

	$config->{tpl}->parse(XML => $config->{name});

	my $xml = $config->{tpl}->fetch('XML');

#	print STDERR "Template Time: " . sprintf("%0.2f", tv_interval($t0, [gettimeofday])) . "\n";

#	open(TMP, "> /tmp/report.xml");
#	print TMP $$xml;
#	close(TMP);

	my $report = XMLin($$xml, ForceArray => [ 'element', 'page' ]);

#	print STDERR "XML Time: " . sprintf("%0.2f", tv_interval($t0, [gettimeofday])) . "\n";

	# Hardcoded now - convert to user supplied values later
	my $pdf = new PDF::Report(PageSize => ($report->{size} || 'A4'), PageOrientation => ($report->{orientation} || 'Portrait'),
							  File => '');

	foreach my $page (@{ $report->{page} }) {
		$pdf->newpage(1);
	
		foreach my $elem (@{ $page->{element} }) {
			my $cmd = 'pdf_' . $elem->{type} . '($pdf, $elem)';
			
			eval $cmd;
			
			if ($@) {
				print STDERR "Error: $@";
			}
		}
	}

#	print STDERR "PDF Time: " . sprintf("%0.2f", tv_interval($t0, [gettimeofday])) . "\n";

	return $pdf->Finish('none');
}

# Generate 'spreadsheet' PDF given XML template
# Probably just generate pages then call generate_pdf
sub generate_sheet_pdf {
	my ($config, $template_file, $op, $vars) = @_;

	my $pdf = new PDF::Report(PageSize => 'A4', (PageOrientation => $vars->{page_orientation} || 'Portrait'), File => '');
	$pdf->newpage(1);
	
	my($pagewidth, $pageheight) = $pdf->getPageDimensions();
 
	$vars->{pages} = ();

	my $page_no = 1;
	my $page = { 
		header      => $vars->{header}, 
		rows        => [], 
		cur_page    => $page_no, 
		report_name => $vars->{report_name},
		start       => 1,
		end         => 0,
	};

	my $ypos = $vars->{row_0_y};

	# Fixed font at the moment
	$pdf->setFont("Helvetica");
	$pdf->setSize(10);

	
	my $row_color = '#a0a0a0';

	my $count = 0;

	while (my $r = shift(@{ $vars->{rows} })) {
		# Check for a new 'original row'
		if (! $r->{split} ) {
			$count++;
			$row_color = ($row_color eq '#a0a0a0' ? '#ffffff' : '#a0a0a0');
		}

		my $row_ypos = $ypos;

		my $new_row = undef;

		my $idx = 0;
		foreach my $c (@{ $r->{cols} }) {
			my $remainder = undef;

			# If any CRs split at first CR
			if ($c->{content} =~ m/\n/) {
				($c->{content}, $remainder) = split(/\n/, $c->{content}, 2);
			}

			# Now check string width
			my $w = $pdf->getStringWidth($c->{content});
			my $col_width = $c->{x2} - $c->{x1};

			# Split if too big
			if ($w > $col_width) {
				my $bp = length($c->{content});
				
				while (($bp > 0) && ($w > $col_width)) {
					$bp--;
					$w = $pdf->getStringWidth(substr($c->{content}, 0, $bp));
				}

				# Break words with a '-'
				my $dash = '';
				if ((substr($c->{content}, $bp-1, 1) !~ /\s/) && (substr($c->{content}, $bp, 1) !~ /\s/)) {
					$bp--;
					$dash = '-';
				}
				
				$remainder    = substr($c->{content}, $bp) . $remainder;
				$c->{content} = substr($c->{content}, 0, $bp) . $dash;
			}

			# If we have a remainder create a new row
			if ($remainder) {
				# Create a new row if we haven't already for an earlier column
				$new_row = dclone($r) unless $new_row;
				
				foreach my $new_c (@{ $new_row->{cols}}) {
					$new_c->{content} = '' unless $new_c->{split};

					# Mark this as an already split row so we don't overwite content
					$new_c->{split} = 1;
				}

				$new_row->{cols}->[$idx]->{content} = $remainder;
				
			}
			
			$c->{y1} = $row_ypos;

			$idx++;
		}

		# We split into a new row so put to head of rows list
		if ($new_row) {
			# Remove split marks to prevent allow new row_creation to clear content
			# if another new row is necessary
			foreach my $new_c (@{ $new_row->{cols} }) {
				delete $new_c->{split};
			}

			# Mark row as a split row
			$new_row->{split} = 1;

			unshift(@{ $vars->{rows} }, $new_row);					
		}

		# Add row dimensions / color
#		$r->{y1}    = $ypos + $vars->{row_height};
#		$r->{y2}    = $ypos;
#		$r->{x1}    = $r->{cols}->[0]->{x1};
#		$r->{x2}    = $r->{cols}->[$#{$r->{cols}}]->{x2};
			
#		$r->{color} = $row_color; 
		
		push (@{ $page->{rows} }, $r);

		$ypos -= $vars->{row_height};

		# New page if we get close to the bottom
		if ($ypos <= $vars->{row_height}) {
			$ypos = $vars->{row_0_y};
			
			$page->{end} = $count;

			push(@{ $vars->{pages} } , $page);
			
			$page_no++;
			
			$page = { 
				header      => $vars->{header}, 
				rows        => [], 
				cur_page    => $page_no, 
				report_name => $vars->{report_name}, 
				start       => $count + 1,
				end         => 0,
			};
		}
	}
	
	# Finish last page
	if (scalar(@{ $page->{rows} })) {
		$page->{end} = $count;

		push(@{ $vars->{pages} } , $page);
	}

	# Add total page number / row count to each page
	foreach (@{ $vars->{pages} }) {
		$_->{count} = $count;
		$_->{total} = $page_no;
	}

#	open(TMP, ">/tmp/pages");
#	print TMP Dumper($vars), "\n";
#	close(TMP);

	return generate_pdf($config, $template_file, $op, $vars);
}

# Quota characters to prevent problems for XMLin
sub quote_vals {
	my $var = shift;

	$_ = ref($var);
	if ($_) {
	  CASE: {
		  /HASH/ and do {
			  foreach my $k (keys %$var) {
				$var->{$k} = quote_vals($var->{$k});  
			  }

			  last CASE;
		  };

		  /ARRAY/ and do {
			  my @qs = ();

			  foreach my $e (@$var) {
				  push(@qs, quote_vals($e));
			  }

			  $var = \@qs;

			  last CASE;
		  };
	  }
	} else {
		# XML Quota
		$var = xml_quote($var);
		
		# Convert non-ASCII characters to Unicode representation
		$var =~ s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
	}

	return $var;
}

# PDF drawing routines 
sub pdf_line {
	my ($pdf, $elem) = @_;
	
	$pdf->drawLine($elem->{x1}, $elem->{y1}, $elem->{x2}, $elem->{y2});
}

sub pdf_rect {
	my ($pdf, $elem) = @_;

	$pdf->drawRect($elem->{x1}, $elem->{y1}, $elem->{x2}, $elem->{y2});
}

sub pdf_shadeRect {
	my ($pdf, $elem) = @_;

	$pdf->shadeRect($elem->{x1}, $elem->{y1}, $elem->{x2}, $elem->{y2}, $elem->{shade});

}

sub pdf_font {
	my ($pdf, $elem) = @_;

	$pdf->setSize($elem->{size});
	$pdf->setFont($elem->{font});
}

sub pdf_string {
	my ($pdf, $elem) = @_;

	$pdf->setAddTextPos($elem->{x} || $elem->{x1}, $elem->{y} || $elem->{y1});
	$pdf->addText($elem->{content});
}

sub pdf_stringCenter {
	my ($pdf, $elem) = @_;

	$pdf->centerString($elem->{x1}, $elem->{x2}, $elem->{y1}, $elem->{content}, get_stringOpts($elem));
}

sub pdf_stringLeft {
	my ($pdf, $elem) = @_;

	$elem->{x} = $elem->{x1} unless $elem->{x};
	$elem->{y} = $elem->{y1} unless $elem->{y};

	my $w = 1 + $pdf->getStringWidth($elem->{content});
	$pdf->centerString($elem->{x}, $elem->{x}+$w, $elem->{y}, $elem->{content}, get_stringOpts($elem));
}

sub pdf_stringRight {
	my ($pdf, $elem) = @_;

	$elem->{x} = $elem->{x2} unless $elem->{x};
	$elem->{y} = $elem->{y1} unless $elem->{y};

	my $w = 1 + $pdf->getStringWidth($elem->{content});
	$pdf->centerString($elem->{x}-$w, $elem->{x}, $elem->{y}, $elem->{content}, get_stringOpts($elem));
}

sub get_stringOpts {
	my $elem = shift;

	my %opts = ();

	foreach (@STR_OPTS) {
		$opts{$_} = $elem->{$_} if $elem->{$_};
	}

	return \%opts;
}

1;
__END__

