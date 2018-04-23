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
# v3.5 14/03/2006 Modified to handle tables that overflow
#

package Apache::Controller::PDF;

use strict;
use XML::Simple;
use XML::Quote qw(:all);
use PDF::Report;
use PDF::API2::Resource::Font::CoreFont;
use Text::Wrap;

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
		draw  => 0,
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

	foreach (@{ $report->{page} }) {
		if (defined($_->{'import'})) {
			my $imp = PDF::API2->open($_->{'import'});
			$pdf->{pdf}->{pdf}->importpage($imp, 1);
		} else {
			$pdf->generate_page($_);
		}
	}
	
	return $pdf->{pdf}->Finish('none');
}

sub generate_page {
	my ($pdf, $page) = @_;

	$pdf->{pdf}->newpage();

	# Assume header & footer fit
	foreach my $s (qw(header footer)) {
		if (defined($page->{$s}->{border})) {
			unshift(@{ $page->{$s}->{element} }, { type => 'rect', x1 => 0, y1 => 0, x2 => $page->{$s}->{width},
												   y2 => $page->{$s}->{height}, color => $page->{$s}->{color} || 'black' });
		}
		
		$pdf->{x0} = $page->{$s}->{x0} || 0;
		$pdf->{y0} = $page->{$s}->{y0} || 0;
		$pdf->{xm} = $page->{$s}->{width} || $pdf->{pxmax};
		$pdf->{ym} = $page->{$s}->{height} || $pdf->{pymax};
		
		$pdf->{draw} = 1;
		$pdf->add_elements($page->{$s}->{element});
	}

	# Now draw body
	# First pass just setup elements without drawing
	$pdf->{draw} = 0;
	$pdf->add_elements($page->{body}->{element});
	
	$pdf->{x0} = $page->{body}->{x0} || 0;
	$pdf->{y0} = $page->{body}->{y0} || 0;
	$pdf->{xm} = $page->{body}->{width} || $pdf->{pxmax};
	$pdf->{ym} = $page->{body}->{height} || $pdf->{pymax};
	
	$pdf->{draw} = 1;
	my $i = $pdf->add_elements($page->{body}->{element});

	

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

		$e->{height} = 0 unless $e->{height};
		
		if (($pdf->{ym} - $y >= $e->{height})) {
			my $cmd = '$e->{height} = $pdf->pdf_' . $e->{type} . '($e)';
			
			eval $cmd;
			
			$y += $e->{height};

			if ($@) {
				print STDERR Dumper($e), "\n";
				die "Error: $@";
			}
		} 
	}
	
	return $y;
}

# PDF drawing routines 
sub pdf_table { 
	my ($pdf, $e) = @_;
	
	my $y = 0;
	
	my ($tx, $tm) = ($pdf->{x0}, $pdf->{xm}); 
	
	$pdf->{x0} += $e->{x};
	$pdf->{xm} = $e->{width};
	
	foreach my $r (@{ $e->{row} }) {
		my $row_y = $pdf->row($r);
		
		$pdf->{y0} += $row_y;
		
		$y += $row_y;
	}
	
	if ($e->{border} && $pdf->{draw}) {
		$pdf->pdf_rect({ x1 => 0, x2 => $e->{width}, y1 => -$y, y2 => 0, color => $e->{color} });
	}
	
	($pdf->{x0}, $pdf->{xm}) = ($tx, $tm);
	
	return $y;
}

sub row {
	my ($pdf, $r) = @_;
	
	my $y = 0;
	
	$r->{margin_top} = 0 unless $r->{margin_top};
	
	my ($tx, $ty, $tm) = ($pdf->{x0}, $pdf->{y0}, $pdf->{xm});
	
	my @borders = ();
	
	foreach my $c (@{ $r->{cell} }) {
		$pdf->{y0} += $r->{margin_top};
		$pdf->{x0} += ($c->{x1} || 0);
		$pdf->{xm} = $c->{width};
		
		my $col_y = $pdf->add_elements($c->{element});
		
		if ($c->{border}) {
			push(@borders, { x1 => $c->{x1}, x2 => $c->{x1} + $c->{width}, y1 => 0, color => $c->{color} });
		}
		
		$y = $col_y if $col_y > $y;
		
		($pdf->{x0}, $pdf->{y0}, $pdf->{xm}) = ($tx, $ty, $tm);
	}
	
	$r->{margin_bottom} = 0 unless $r->{margin_bottom};
	
	$y += $r->{margin_top} + $r->{margin_bottom};
	
	foreach my $b (@borders) {
		$b->{y2} = $y;
		
		$pdf->pdf_rect($b) if $pdf->{draw};
	}
	
	if ($r->{border} && $pdf->{draw}) {
		$pdf->pdf_rect({ x1 => 0, x2 => $pdf->{xm}, y1 => 0, y2 => $y, color => $r->{color}});
	}
	
	return $y;
}

sub pdf_line {
	my ($pdf, $e) = @_;
	
	my $gfx = $pdf->{pdf}->{page}->gfx;
	$gfx->strokecolor($e->{color}) if $e->{color};
	
	$pdf->{pdf}->drawLine($pdf->_x($e->{x1}), $pdf->_y($e->{y1}), $pdf->_x($e->{x2}), $pdf->_y($e->{y2})) if $pdf->{draw};
	
	return 0;
}

sub pdf_rect {
	my ($pdf, $e) = @_;
	
	my $gfx = $pdf->{pdf}->{page}->gfx;
	$gfx->strokecolor($e->{color}) if $e->{color};
	
	$pdf->{pdf}->drawRect($pdf->_x($e->{x1}), $pdf->_y($e->{y1}), $pdf->_x($e->{x2}), $pdf->_y($e->{y2})) if $pdf->{draw};
	
	return 0;
}

sub pdf_shadeRect {
	my ($pdf, $e) = @_;
	
	$pdf->{pdf}->shadeRect($pdf->_x($e->{x1}), $pdf->_y($e->{y1}), $pdf->_x($e->{x2}), $pdf->_y($e->{y2}), $e->{shade}) if 
		$pdf->{draw};
	
	return 0;
}

sub pdf_img {
	my ($pdf, $e) = @_;
	
	$pdf->{pdf}->addImg($e->{file}, $pdf->_x($e->{x}), $pdf->_y($e->{y})) if $pdf->{draw};
	
	return 0;
}

sub pdf_imgScaled {
	my ($pdf, $e) = @_;
	
	my $img = $pdf->{pdf}->{pdf}->image_jpeg($e->{file});
	my $gfx = $pdf->{pdf}->{page}->gfx;
	$gfx->image($img, $pdf->_x($e->{x}), $pdf->_y($e->{y}), $e->{scale}) if $pdf->{draw};
	
	return 0;
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
	
	return 0;
}

sub pdf_string {
	my ($pdf, $e) = @_;
	
	if ($pdf->{draw}) {
		$pdf->{pdf}->setAddTextPos($pdf->_x($e->{x} || $e->{x1}), $pdf->_y($e->{y} || $e->{y1}));
		$pdf->{pdf}->addText($e->{content});
	}
	return 0;
}

sub pdf_stringCenter {
	my ($pdf, $e) = @_;
	
	my ($h, $strs) = $pdf->_wrap_text($e->{x1}, $e->{content});
	my $height = 0;
	
	if ($pdf->{draw}) {
		foreach my $s (@$strs) {
			$pdf->{pdf}->centerString($pdf->_x($e->{x1}), $pdf->_x($e->{x2}), 
									  $pdf->_y($e->{y1} + $height + $pdf->{font}->{ascender}), $s, $pdf->get_stringOpts($e));
			
			$height += $h;
		}
	} else {
		$height = $h * scalar(@$strs);
	}
	
	return $height;
}

sub pdf_stringLeft {
	my ($pdf, $e) = @_;

	my ($h, $strs) = $pdf->_wrap_text($e->{x}, $e->{content});
	my $height = 0;

	if ($pdf->{draw}) {
		foreach my $s (@$strs) {
			my $w = 1 + $pdf->{pdf}->getStringWidth($s);
			
			$pdf->{pdf}->centerString($pdf->_x($e->{x}), $pdf->_x($e->{x}) + $w, 
									  $pdf->_y($e->{y} + $height + $pdf->{font}->{ascender}), $s, $pdf->get_stringOpts($e));
			
			$height += $h;
		}
	} else {
		$height = $h * scalar(@$strs);
	}
	
	return $height;
}

sub pdf_stringRight {
	my ($pdf, $e) = @_;
	
	my ($h, $strs) = $pdf->_wrap_text($e->{x}, $e->{content}, 'right');
	my $height = 0;
	
	if ($pdf->{draw}) {
		foreach my $s (@$strs) {
			my $w = 1 + $pdf->{pdf}->getStringWidth($s);
			$pdf->{pdf}->centerString($pdf->_x($e->{x}) - $w, $pdf->_x($e->{x}), 
									  $pdf->_y($e->{y} + $height + $pdf->{font}->{ascender}), $s, $pdf->get_stringOpts($e));
		
			$height += $h;
		}
	} else {
		$height = $h * scalar(@$strs);
	}
	
	return $height;
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

