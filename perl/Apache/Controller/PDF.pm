# Apache Controller PDF module
# Copyright (c) 2004,2006 Jeremy Robst <jpro@robst.me.uk>
#
# This program is free software released under the GPL.
# See the file COPYING included with this release or
# http://www.gnu.org/copyleft/copyleft.html
#
# v3.0 15/01/2006 Rewritten for new XML markup
# v3.1 16/02/2006 Flip coordinate system so (0, 0) is top left
# v3.2 17/02/2006 Change string functions so point is bottom left of string
# v3.3 21/02/2006 Added text wrapping
# v3.4 06/03/2006 Changed string functions so point is top left of string (like page)
# v4.0 19/03/2006 Element setup first
#

package Apache::Controller::PDF;

use strict;
use XML::Simple;
use XML::Quote qw(:all);
use PDF::Report;
use PDF::API2::Resource::Font::CoreFont;
use Text::Wrap;
use Image::Info qw(image_info);

use Data::Dumper;

my $PAGESIZE = 'A4';
my $ORIENTATION = 'Portrait';

my @STR_OPTS = qw(color underline indent rotate);

# Inpur sizes in mm
my $SIZES = {
	a4 => { xmax => 210, ymax => 297 },
};

# Convert points to mm
use constant mm => 25.4/72;
use constant pt => 1;
use constant afm => 1/1000;

# Size of text lines (gap between text)
my $LINE_GAP = 1.2;

sub new {
	my $class = shift;
	
	my $pdf = bless {
		font  => { name => undef, size => undef },
		pdf   => undef,
		xs    => undef,
		ys    => undef,
		pymax => undef,       # Page Y Max
		pxmax => undef,       # Page X Max
		x0    => 0,           # Relative X origin
		y0    => 0,           # Relative Y origin
		xm    => undef,       # Relative X maximum
		ym    => undef,       # Relative Y maximum
		relative => 1,
	}, $class;

	return $pdf
}

sub generate_pdf {
	my ($pdf, $xml) = @_;

	my $report = XMLin($xml, ForceArray => [ 'element', 'page', 'row', 'cell' ]);

#	print STDERR Dumper($report), "\n";
#	exit(0);

	my $orient = $report->{orientation} || $ORIENTATION;
	my $size = $report->{size} || $PAGESIZE;
	$pdf->{pdf} = PDF::Report->new(PageSize => $size, PageOrientation => $orient);
	
	# Generate scaling factor
	my ($px, $py) = $pdf->{pdf}->getPageDimensions();
	$pdf->{xs} = $px / $SIZES->{$size}->{xmax};
	$pdf->{ys} = $py / $SIZES->{$size}->{ymax};

	$pdf->{pymax} = $SIZES->{$size}->{ymax};
	$pdf->{pxmax} = $SIZES->{$size}->{xmax};

	if ($orient eq 'Landscape') {
		$pdf->{xs} = $px / $SIZES->{$size}->{ymax};
		$pdf->{ys} = $py / $SIZES->{$size}->{xmax};

		$pdf->{pymax} = $SIZES->{$size}->{xmax};
		$pdf->{pxmax} = $SIZES->{$size}->{ymax};
	}

	$pdf->{xm} = $pdf->{pxmax};
	$pdf->{ym} = $pdf->{pymax};

	foreach (@{ $report->{page} }) {
		if (defined($_->{'import'})) {
			my $imp = PDF::API2->open($_->{'import'});
			$pdf->{pdf}->{pdf}->importpage($imp, 1);
		} else {
			$pdf->{pdf}->newpage();

			$pdf->setup_page($_);
			$pdf->generate_page($_);
		}
	}
	
	return $pdf->{pdf}->Finish('none');
}

sub setup_page {
	my ($pdf, $page) = @_;

	foreach my $s (qw(header footer body)) {
		if (defined($page->{$s}->{border})) {
			unshift(@{ $page->{$s}->{element} }, { type => 'rect', x1 => 0, y1 => 0, x2 => $page->{$s}->{width},
												   y2 => $page->{$s}->{height}, color => $page->{$s}->{color} || 'black' });
		}

		$pdf->setup_elements($page->{$s}->{element});
	}
}

sub setup_elements {
	my ($pdf, $elements) = @_;

	my $h = 0;

	foreach my $e (@$elements) {
		my $cmd = '$pdf->setup_' . $e->{type} . '($e)';
		
		eval $cmd;

		if ($@) {
			die "Setup Error: $@\n";
		}

		$h += $e->{height};
	}

	return $h;
}

sub generate_page {
	my ($pdf, $page) = @_;

	# Assume header & footer fit
	foreach my $s (qw(header footer)) {
		$pdf->{x0} = $page->{$s}->{x0} || 0;
		$pdf->{y0} = $page->{$s}->{y0} || 0;
		$pdf->{xm} = $page->{$s}->{width} || $pdf->{pxmax};
		$pdf->{ym} = $page->{$s}->{height} || $pdf->{pymax};

		$pdf->{relative} = 0;
		$pdf->add_elements($page->{$s}->{element});
	}

	$pdf->{relative} = 1;

	# Now draw body
	$pdf->{x0} = $page->{body}->{x0} || 0;
	$pdf->{y0} = $page->{body}->{y0} || 0;
	$pdf->{xm} = $page->{body}->{width} || $pdf->{pxmax};
	$pdf->{ym} = $page->{body}->{height} || $pdf->{pymax};

	my $elements = $page->{body}->{element};

	my ($idx, $new_elem) = $pdf->add_elements($elements);

	# add_elements may change number of elements so don't count them until now
	my $num_elem = scalar(@$elements);

	# Didn't fit on one page - have some elements left over
	if ($idx != $num_elem) {
		my $new_page = { header => $page->{header}, footer => $page->{footer} };

		$new_page->{body} = { 
			x0      => $page->{body}->{x0}     || 0,
			y0      => $page->{body}->{y0}     || 0,
			width   => $page->{body}->{width}  || $pdf->{pxmax},
			height  => $page->{body}->{height} || $pdf->{pymax},
			element => [],
		};

		# new_elem defined if an element has been split
		push(@{ $new_page->{body}->{element} }, $new_elem) if $new_elem;

		for (my $i=$idx; $i<$num_elem; $i++) {
			push(@{ $new_page->{body}->{element} }, $elements->[$i]);
		}

		$pdf->{pdf}->newpage();
		$pdf->generate_page($new_page);
	}
}

sub _y {
	my ($pdf, $y) = @_;

	return ($pdf->{ys} * ($pdf->{pymax} - ($pdf->{y0} + $y)));
}

sub _x {
	my ($pdf, $x) = @_;

	return ($pdf->{xs} * ($pdf->{x0} + $x));
}

sub add_elements {
	my ($pdf, $elements) = @_;

	my $y = 0;

	for (my $i=0; $i<scalar(@$elements); $i++) {
		my $e = $elements->[$i];

		my $gap = $pdf->{ym} - $y;

		if ($gap >= $e->{height}) {
			my $cmd = '$pdf->pdf_' . $e->{type} . '($e)';
			
			eval $cmd;
			
			$y += $e->{height} if $pdf->{relative};

			if ($@) {
				print STDERR Dumper($e), "\n";
				die "Error: $@";
			}
		} else {
			if (($e->{type} ne 'table') || (defined($e->{break}) && ($e->{break} eq 'no'))) {
				return ($i, undef);
			} else {
				# Have to break table 
				my $new_table = { type => 'table', x => $e->{x}, width => $e->{width}, border => $e->{border}, 
								  color => $e->{color}, break => $e->{break}, row => [], height => 0 };

				my $height = 0;
				my $r = 0;
				while ($r<scalar(@{ $e->{row} })) {
					last if ($height + $e->{row}->[$r]->{height} > $gap);

					# Copy header rows to new_table
					if ($e->{row}->[$r]->{header}) {
						push(@{ $new_table->{row} }, $e->{row}->[$r]);
						
						$new_table->{height} += $e->{row}->[$r]->{height};
					}
					
					$height += $e->{row}->[$r]->{height};
					$r++;
				}

				# None of table fits - just put whole lot on next page
				if ($r == 0) {
					return ($i, undef);
				}

				for (; $r<scalar(@{ $e->{row} }); $r++) {
					push(@{ $new_table->{row} }, $e->{row}->[$r]);

					$new_table->{height} += $e->{row}->[$r]->{height};

					$e->{height} -= $e->{row}->[$r]->{height};

					delete $e->{row}->[$r];
				}

				
				# Check to make sure old table isn't just header
				my $header = 0;
				foreach my $row (@{ $e->{row} }) {
					$header++ if $row->{header};
				}

				# Only header, so put whole thing on next page
				return ($i+1, $new_table) if ($header == scalar(@{ $e->{row} }));

				# Add partial table to this page
				$pdf->pdf_table($e);

				return ($i+1, $new_table);
			}
		}
	}

	return (scalar(@$elements), undef);
}

# PDF drawing routines 

sub setup_table {
	my ($pdf, $e) = @_;
	
	$e->{height} = 0;

	my ($tx, $tm) = ($pdf->{x0}, $pdf->{xm}); 
	
	$pdf->{x0} += $e->{x};
	$pdf->{xm} = $e->{width};
	
	foreach my $r (@{ $e->{row} }) {
		$e->{height} += $pdf->setup_row($r);
	}
	
	($pdf->{x0}, $pdf->{xm}) = ($tx, $tm);
}

sub pdf_table { 
	my ($pdf, $e) = @_;
	
	my ($tx, $tm) = ($pdf->{x0}, $pdf->{xm}); 
	
	$pdf->{x0} += $e->{x};
	$pdf->{xm} = $e->{width};
	
	foreach my $r (@{ $e->{row} }) {
		$pdf->row($r);
		
		$pdf->{y0} += $r->{height};
	}
	
	if ($e->{border}) {
		$pdf->pdf_rect({ x1 => 0, x2 => $e->{width}, y1 => -$e->{height}, y2 => 0, color => $e->{color} });
	}
	
	($pdf->{x0}, $pdf->{xm}) = ($tx, $tm);
}

sub setup_row {
	my ($pdf, $r) = @_;

	$r->{margin_top}    = 0 unless $r->{margin_top};
	$r->{margin_bottom} = 0 unless $r->{margin_bottom};

	$r->{height} = 0;

	my ($tx, $ty, $tm) = ($pdf->{x0}, $pdf->{y0}, $pdf->{xm});

	foreach my $c (@{ $r->{cell} }) {
		$pdf->{y0} += $r->{margin_top};
		$pdf->{x0} += ($c->{x1} || 0);
		$pdf->{xm} = $c->{width};

		$c->{height} = $pdf->setup_elements($c->{element});

		$r->{height} = $c->{height} if $c->{height} > $r->{height};

		($pdf->{x0}, $pdf->{y0}, $pdf->{xm}) = ($tx, $ty, $tm);
	}

	$r->{height} += $r->{margin_top} + $r->{margin_bottom};
}

sub row {
	my ($pdf, $r) = @_;
	
	my $y = 0;
	
	my ($tx, $ty, $tm) = ($pdf->{x0}, $pdf->{y0}, $pdf->{xm});
	
	my @borders = ();
	
	foreach my $c (@{ $r->{cell} }) {
		$pdf->{y0} += $r->{margin_top};
		$pdf->{x0} += ($c->{x1} || 0);
		$pdf->{xm} = $c->{width};
		
		$pdf->add_elements($c->{element});
		
		if ($c->{border}) {
			push(@borders, { x1 => $c->{x1}, x2 => $c->{x1} + $c->{width}, y1 => 0, y2 => $r->{height}, color => $c->{color} });
		}
		
		($pdf->{x0}, $pdf->{y0}, $pdf->{xm}) = ($tx, $ty, $tm);
	}
	
	foreach my $b (@borders) {
		$pdf->pdf_rect($b);
	}
	
	if ($r->{border}) {
		$pdf->pdf_rect({ x1 => 0, x2 => $pdf->{xm}, y1 => 0, y2 => $r->{height}, color => $r->{color}});
	}
}

sub pdf_line {
	my ($pdf, $e) = @_;
	
	my $gfx = $pdf->{pdf}->{page}->gfx;
	$gfx->strokecolor($e->{color}) if $e->{color};
	
	$pdf->{pdf}->drawLine($pdf->_x($e->{x1}), $pdf->_y($e->{y1}), $pdf->_x($e->{x2}), $pdf->_y($e->{y2}));
	
	return 0;
}

sub setup_rect {
	my ($pdf, $e) = @_;

	$e->{height} = 0;
}

sub pdf_rect {
	my ($pdf, $e) = @_;
	
	my $gfx = $pdf->{pdf}->{page}->gfx;
	$gfx->strokecolor($e->{color}) if $e->{color};
	
	$pdf->{pdf}->drawRect($pdf->_x($e->{x1}), $pdf->_y($e->{y1}), $pdf->_x($e->{x2}), $pdf->_y($e->{y2}));
}

sub pdf_shadeRect {
	my ($pdf, $e) = @_;
	
	$pdf->{pdf}->shadeRect($pdf->_x($e->{x1}), $pdf->_y($e->{y1}), $pdf->_x($e->{x2}), $pdf->_y($e->{y2}), $e->{shade});
	
	return 0;
}

sub pdf_img {
	my ($pdf, $e) = @_;
	
	$pdf->{pdf}->addImg($e->{file}, $pdf->_x($e->{x}), $pdf->_y($e->{y}));
	
	return 0;
}

sub setup_imgScaled {
	my ($pdf, $e) = @_;
	
	$e->{img} = $pdf->{pdf}->{pdf}->image_jpeg($e->{file});

	my $info = image_info($e->{file});
	$e->{height} = $e->{scale} * $info->{height} * mm;
}

sub pdf_imgScaled {
	my ($pdf, $e) = @_;

	my $gfx = $pdf->{pdf}->{page}->gfx;	
	$gfx->image($e->{img}, $pdf->_x($e->{x}), $pdf->_y($e->{y}), $e->{scale});
}

sub setup_font {
	my ($pdf, $e) = @_;

	$pdf->pdf_font($e);

	$e->{height} = 0;
}

sub pdf_font {
	my ($pdf, $e) = @_;
	
	$pdf->{pdf}->setSize($e->{size} / pt);
	$pdf->{pdf}->setFont($e->{font});	
	
	$pdf->{font}->{name} = $e->{font};
	$pdf->{font}->{size} = $e->{size};
	
	my $font = PDF::API2::Resource::Font::CoreFont->new_api($pdf->{pdf}->{pdf}, $e->{font}); 
	($pdf->{font}->{ascender}, $pdf->{font}->{descender}) = ($font->ascender() * afm  * $e->{size} * mm, 
															 $font->descender() * afm * $e->{size} * mm);
}

sub pdf_string {
	my ($pdf, $e) = @_;
	
	if ($pdf->{draw}) {
		$pdf->{pdf}->setAddTextPos($pdf->_x($e->{x} || $e->{x1}), $pdf->_y($e->{y} || $e->{y1}));
		$pdf->{pdf}->addText($e->{content});
	}
	return 0;
}

sub _setup_string {
	my ($pdf, $e, $align) = @_;

	my $txm = $pdf->{xm};

	if ($align eq 'center') {
		$e->{x} = $e->{x1};
		
		$pdf->{xm} = $e->{x2};
	}

	($e->{h}, $e->{strs}) = $pdf->_wrap_text($e->{x}, $e->{content}, $align);

	if ($align eq 'center') {
		$pdf->{xm} = $txm;
	}

	$e->{height} = $e->{h} * scalar(@{ $e->{strs} });
}

sub setup_stringCenter {
	my ($pdf, $e) = @_;

	$pdf->_setup_string($e, 'center');
}

sub pdf_stringCenter {
	my ($pdf, $e) = @_;
	
	my $height = 0;
	
	foreach my $s (@{ $e->{strs} }) {
		$pdf->{pdf}->centerString($pdf->_x($e->{x1}), $pdf->_x($e->{x2}), 
								  $pdf->_y($e->{y1} + $height + $pdf->{font}->{ascender}), $s, $pdf->get_stringOpts($e));
			
		$height += $e->{h};
	}
}

sub setup_stringLeft {
	my ($pdf, $e) = @_;

	$pdf->_setup_string($e, 'left');
}

sub pdf_stringLeft {
	my ($pdf, $e) = @_;

	my $height = 0;

	foreach my $s (@{ $e->{strs} }) {
		my $w = 1 + $pdf->{pdf}->getStringWidth($s);
			
		$pdf->{pdf}->centerString($pdf->_x($e->{x}), $pdf->_x($e->{x}) + $w, 
								  $pdf->_y($e->{y} + $height + $pdf->{font}->{ascender}), $s, $pdf->get_stringOpts($e));
		
		$height += $e->{h};
	}
}

sub setup_stringRight {
	my ($pdf, $e) = @_;

	$pdf->_setup_string($e, 'right');
}

sub pdf_stringRight {
	my ($pdf, $e) = @_;
	
	my $height = 0;

	foreach my $s (@{ $e->{strs} }) {
		my $w = 1 + $pdf->{pdf}->getStringWidth($s);
		$pdf->{pdf}->centerString($pdf->_x($e->{x}) - $w, $pdf->_x($e->{x}), 
								  $pdf->_y($e->{y} + $height + $pdf->{font}->{ascender}), $s, $pdf->get_stringOpts($e));
		
		$height += $e->{h};
	}
}

sub get_stringOpts {
	my ($pdf, $e) = @_;

	my @opts = ();

	foreach (@STR_OPTS) {
		push(@opts, $e->{$_}); 
	}

	return @opts;
}

sub _wrap_text {
	my ($pdf, $x, $str, $align) = @_;
	$align = 'left' unless $align && $align eq 'right';
	$str = " " unless defined($str);

	# Split each line if we have '\n's'
	if ($str =~ /\n/) {
		my @lines = split("\n", $str);
		
		my @strs = ();
		my ($h, $ss) = (0, undef);

		foreach my $l (@lines) {
			($h, $ss) = $pdf->_wrap_text($x, $l, $align);

			foreach my $s (@$ss) {
				push(@strs, $s);
			}
		}

		return ($h, \@strs);
	}

	if ($str =~ /^\s*(\S.*\S+)\s*$/) {
		$str = $1;
	}

	my $h = $LINE_GAP * $pdf->{pdf}->getSize() * mm;
	my $w = $pdf->{pdf}->getStringWidth($str) + 1;

	my $width = $pdf->_x($pdf->{xm}) - $pdf->_x($x);
	$width = $pdf->_x($x) - $pdf->_x(0) if $align eq 'right';

	# Generate list of strings to display
	my @strs = ();
	
	if ($w > $width) {
		my $char_width = $w / length($str); # try an compute average char width
		
		my $cols = int($width / $char_width);
		$cols = 2 if ($cols < 2); # fixed minimum width
		
		$Text::Wrap::columns = $cols;
		
		push(@strs, split("\n", wrap('', '', $str)));
	} else {
		push(@strs, $str);
	}

	return ($h, \@strs);
}


1;
__END__

