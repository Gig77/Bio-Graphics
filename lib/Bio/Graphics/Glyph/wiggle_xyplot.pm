package Bio::Graphics::Glyph::wiggle_xyplot;

use strict;
use base qw(Bio::Graphics::Glyph::wiggle_minmax 
            Bio::Graphics::Glyph::xyplot 
            Bio::Graphics::Glyph::smoothing);
use IO::File;
use File::Spec;


sub my_description {
    return <<END;
This glyph draws quantitative data as an xyplot. It is designed to be
used in conjunction with features in "wiggle" format as generated by
Bio::Graphics::Wiggle, or base pair coverage data generated by the
Bio::DB::Sam module.

For this glyph to work, the feature must define one of the following tags:

  wigfile -- a path to a Bio::Graphics::Wiggle file

  wigdata -- Wiggle data in the Bio::Graphics::Wiggle "wif" format, as created
             by \$wig->export_to_wif().

  coverage-- a simple comma-delimited string containing the quantitative values,
             assumed to be one value per pixel.

END
}

sub my_options {
    {
	basedir => [
	    'string',
	    undef,
	    'If a relative path is used for "wigfile", then this option provides',
	    'the base directory on which to resolve the path.'
	    ],
	variance_band => [
	    'boolean',
	    0,
	    'If true, draw a semi-transparent band across the image that indicates',
	    'the mean and standard deviation of the data set. Only of use when a wig',
	    'file is provided.'
        ],
	z_score_bounds => [
	    'integer',
            4,
	    'When using z_score autoscaling, this option controls how many standard deviations',
	    'above and below the mean to show.'
	],
	autoscale => [
	    ['local','chromosome','global','z_score','clipped_global'],
            'clipped_global',
	    'If set to "global" , then the minimum and maximum values of the XY plot',
	    'will be taken from the wiggle file as a whole. If set to "chromosome", then',
            'scaling will be to minimum and maximum on the current chromosome.',
	    '"clipped_global" is similar to "global", but clips the top and bottom values',
	    'to the multiples of standard deviations indicated by "z_score_bounds"',
	    'If set to "z_score", then the whole plot will be rescaled to z-scores in which',
	    'the "0" value corresponds to the mean across the genome, and the units correspond',
	    'to standard deviations above and below the mean. The number of SDs to show are',
	    'controlled by the "z_score_bound" option.',
	    'Otherwise, the plot will be',
	    'scaled to the minimum and maximum values of the region currently on display.',
	    'min_score and max_score override autoscaling if one or both are defined'
        ],
    };
}

# Added pad_top subroutine (pad_top of Glyph.pm, which is called when executing $self->pad_top
# returns 0, so we need to override it here)
sub pad_top {
  my $self = shift;
  my $pad = $self->Bio::Graphics::Glyph::generic::pad_top(@_);
  if ($pad < ($self->font('gdTinyFont')->height)) {
    $pad = $self->font('gdTinyFont')->height;  # extra room for the scale
  }
  $pad;
}

sub pad_left {
    my $self = shift;
    my $pad  = $self->SUPER::pad_left(@_);
    return $pad unless $self->option('variance_band');
    $pad    += length('+1sd')/2 * $self->font('gdTinyFont')->width+3;
    return $pad;
}

sub clip_color {
    my $self = shift;
    return $self->translate_color('orange');
}

# we override the draw method so that it dynamically creates the parts needed
# from the wig file rather than trying to fetch them from the database

# sub draw() { } is now mostly in wiggle_minmax.pm 
sub draw {
  my $self = shift;
  my ($gd,$dx,$dy) = @_;
  my $result = $self->Bio::Graphics::Glyph::wiggle_minmax::draw(@_);

  # inhibit the scale if we are non-bumping
  $self->configure(-scale => 'none') if $self->bump eq 'overlap';
  return $result;
}

sub draw_plot {
    my $self            = shift;
    my $parts           = shift;
    my ($gd,$dx,$dy)    = @_;
    my $pivot = $self->bicolor_pivot;

    $self->panel->startGroup($gd);

    my ($left,$top,$right,$bottom) = $self->calculate_boundaries($dx,$dy);

    # There is a minmax inherited from xyplot as well as wiggle_minmax, and I don't want to
    # rely on Perl's multiple inheritance DFS to find the right one.
    my ($min_score,$max_score,$mean,$stdev)     = $self->minmax($parts);
    my $rescale  = $self->option('autoscale') eq 'z_score';
    my $side    = $self->_determine_side();

    my ($scaled_min,$scaled_max);
    if ($rescale) {
	$scaled_min = int(($min_score-$mean)/$stdev + 0.5);
	$scaled_max = int(($max_score-$mean)/$stdev + 0.5);
	my $bound  = $self->z_score_bound;
	$scaled_max = $bound  if $scaled_max > $bound;
	$scaled_min = -$bound if $scaled_min < -$bound;
    }
    elsif ($side) {
	$scaled_min = int($min_score - 0.5);
	$scaled_max = int($max_score + 0.5);
    } else {
	($scaled_min,$scaled_max) = ($min_score,$max_score);
    }

    my $height = $bottom - $top;
    my $y_scale  = $scaled_max > $scaled_min ? $height/($scaled_max-$scaled_min)
	                                   : 1;
    my $x = $left;
    my $y = $top;
    
    my $x_scale     = $self->scale;
    my $panel_start = $self->panel->start;
    my $feature     = $self->feature;
    my $f_start     = $feature->start > $panel_start 
	                  ? $feature->start 
			  : $panel_start;

    $y += $self->pad_top;

    # position of "0" on the scale
    my $y_origin = $scaled_min <= 0 && $pivot ne 'min' ? $bottom - (0 - $scaled_min) * $y_scale : $bottom;
    $y_origin    = int($y_origin+0.5);

    $self->panel->startGroup($gd);
    $self->_draw_grid($gd,$x_scale,$scaled_min,$scaled_max,$dx,$dy,$y_origin) unless ($self->option('no_grid') == 1);
    $self->panel->endGroup($gd);

    return unless $scaled_max > $scaled_min;

    my $lw       = $self->linewidth;
    my $positive = $self->pos_color;
    my $negative = $self->neg_color;
    my $midpoint = $self->midpoint;
    my $clip_color =  $self->clip_color;
    my $flip     = $self->{flip};
    $midpoint    = ($midpoint - $mean)/$stdev if $rescale;

    my ($clip_top,$clip_bottom);

    my @points = map {
	my ($start,$end,$score) = @$_;
	$score     = ($score-$mean)/$stdev if $rescale;
	my $x1     = $left    + ($start - $f_start) * $x_scale;
	my $x2     = $left    + ($end   - $f_start) * $x_scale;
	if ($x2 >= $left and $x1 <= $right) {
	    my $y1     = $bottom  - ($score - $scaled_min) * $y_scale;
	    my $y2     = $y_origin;
	    $y1        = $top    if $y1 < $top;
	    $y1        = $bottom if $y1 > $bottom;

	    $x1        = $left   if $x1 < $left;
	    $x2        = $right  if $x2 > $right;

	    $x1        = $right - ($x1-$left) if $flip;
	    $x2        = $right - ($x2-$left) if $flip;
 
	    my $color = $score > $midpoint ? $positive : $negative;
	    [int($x1+0.5),int($y1+0.5),int($x2+0.5),int($y2+0.5),$color,$lw];
	} else {
	    ();
	}
    } @$parts;

    my $svg_workaround = $gd->isa('GD::SVG::Image');

    $self->panel->startGroup($gd);
    my $type           = $self->graph_type;
    if ($type eq 'boxes') {
	for (@points) {
	    my ($x1,$y1,$x2,$y2,$color,$lw) = @$_;
	    next unless abs($y2-$y1) > 0;
	    if ($svg_workaround && $x1==$x2) {
		$gd->line($x1,$y1,$x2,$y2,$color);
	    } else {
		$gd->filledRectangle($x1,$y1,$x2,$y2,$color);
	    }
# this tops off clipped peaks with a distinct color, but I just don't like how it looks
#	    $gd->line($x1+1,$top-2,     $x1-1,$top,      $clip_color) if $y1 == $top;
#	    $gd->line($x1+1,$bottom,    $x1-1,$bottom+2, $clip_color) if $y1 == $bottom;
	}
    }

    if ($type eq 'line' or $type eq 'linepoints') {
	my $current = shift @points;
	my $lw      = $self->option('linewidth');
	$gd->setThickness($lw) if $lw > 1;
	for (@points) {
	    my ($x1,$y1,$x2,$y2,$color,$lw) = @$_;
	    $gd->line(@{$current}[0,1],@{$_}[0,1],$color);
	    $current = $_;
	}
	$gd->setThickness(1);
    }

    if ($type eq 'points' or $type eq 'linepoints') {
	my $symbol_name = $self->option('point_symbol') || 'point';
	my $filled      = $symbol_name =~ s/^filled_//;
	my $symbol_ref  = $self->symbols->{$symbol_name};
	my $pr          = $self->point_radius;
	for (@points) {
	    my ($x1,$y1,$x2,$y2,$color,$lw) = @$_;
	    $symbol_ref->($gd,$x1,$y1,$pr,$color,$filled);
	}
    }

    if ($type eq 'histogram') {
	my $current = shift @points;
	for (@points) {
	    my ($x1, $y1, $x2, $y2, $color, $lw)  = @$_;
	    my ($y_start,$y_end) = $y1 < $y_origin ? ($y1,$y_origin) : ($y_origin,$y1);
	    if ($y1-$y2) {
		my $delta = abs($x2-$current->[0]);
		$gd->filledRectangle($current->[0],$y_start,$x2,$y_end,$color) if $delta > 1;
		$gd->line($current->[0],$y_start,$current->[0],$y_end,$color)  if $delta == 1;
		$current = $_;
	    }
	}	
    }


    if ($self->option('variance_band') && 
	(my ($mean,$variance) = $self->global_mean_and_variance())) {
	if ($rescale) {
	    $mean     = 0;
	    $variance = 1;
	}
	my $y1             = $bottom - ($mean+$variance   - $scaled_min) * $y_scale;
	my $y2             = $bottom - ($mean-$variance   - $scaled_min) * $y_scale;
	my $yy1            = $bottom - ($mean+$variance*2 - $scaled_min) * $y_scale;
	my $yy2            = $bottom - ($mean-$variance*2 - $scaled_min) * $y_scale;
	my ($clip_top,$clip_bottom);
	if ($y1 < $top) {
	    $y1                = $top;
	    $clip_top++;
	}
	if ($yy1 < $top) {
	    $yy1 = $top;
	    $clip_top++;
	}
	if ($y2 > $bottom) {
	    $y2                = $bottom;
	    $clip_bottom++;
	}
	if ($yy2 > $bottom) {
	    $yy2 = $bottom;
	    $clip_bottom++;
	}
	my $y              = $bottom - ($mean - $scaled_min) * $y_scale;
	my $mean_color     = $self->panel->translate_color('yellow:0.80');
	my $onesd_color = $self->panel->translate_color('grey:0.30');
	my $twosd_color = $self->panel->translate_color('grey:0.20');
	$gd->filledRectangle($left,$y1,$right,$y2,$onesd_color);
	$gd->filledRectangle($left,$yy1,$right,$yy2,$twosd_color);
	$gd->line($left,$y,$right,$y,$mean_color);

	my $side = $self->_determine_side();
	my $fcolor=$self->panel->translate_color('grey:0.50');
	my $font  = $self->font('gdTinyFont');
	my $x1    = $left - length('+2sd') * $font->width - ($side=~/left|three/ ? 15 : 0);
	my $x2    = $left - length('mn')   * $font->width - ($side=~/left|three/ ? 15 : 0);
	$gd->string($font,$x1,$yy1-$font->height/2,'+2sd',$fcolor) unless $clip_top;
	$gd->string($font,$x1,$yy2-$font->height/2,'-2sd',$fcolor) unless $clip_bottom;
	$gd->string($font,$x2,$y -$font->height/2,'mn',  $fcolor);
    }
    $self->panel->endGroup($gd);

    $self->panel->startGroup($gd);
    $self->_draw_scale($gd,$x_scale,$scaled_min,$scaled_max,$dx,$dy,$y_origin);
    $self->panel->endGroup($gd);

    $self->Bio::Graphics::Glyph::xyplot::draw_label(@_)       if $self->option('label');
    $self->draw_description(@_) if $self->option('description');

    $self->panel->endGroup($gd);
}

sub draw_label {
    my $self = shift;
    my ($gd,$left,$top,$partno,$total_parts) = @_;
    return $self->Bio::Graphics::Glyph::xyplot::draw_label(@_) unless $self->option('variance_band');
    return $self->Bio::Graphics::Glyph::xyplot::draw_label($gd,$left,$top,$partno,$total_parts);
}


1;

__END__

=head1 NAME

Bio::Graphics::Glyph::wiggle_xyplot - An xyplot plot compatible with dense "wig"data

=head1 SYNOPSIS

  See <Bio::Graphics::Panel> and <Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph works like the regular xyplot but takes value data in
Bio::Graphics::Wiggle file format:

 reference = chr1
 ChipCHIP Feature1 1..10000 wigfile=./test.wig
 ChipCHIP Feature2 10001..20000 wigfile=./test.wig
 ChipCHIP Feature3 25001..35000 wigfile=./test.wig

The "wigfile" attribute gives a relative or absolute pathname to a
Bio::Graphics::Wiggle format file. The data consist of a packed binary
representation of the values in the feature, using a constant step
such as present in tiling array data. Wigfiles are created using the
Bio::Graphics::Wiggle module or the wiggle2gff3.pl script, currently
both part of the gbrowse package.

Alternatively, you can place an array of quantitative data directly in
the "wigdata" attribute. This can be an arrayref of quantitative data
starting at feature start and ending at feature end, or the
data string returned by Bio::Graphics::Wiggle->export_to_wif64($start,$end).

=head2 OPTIONS

In addition to all the xyplot glyph options, the following options are
recognized:

   Name        Value        Description
   ----        -----        -----------

   basedir     path         Path to be used to resolve "wigfile" and "densefile"
                                tags giving relative paths. Default is to use the
                                current working directory. Absolute wigfile &
                                densefile paths will not be changed.

   autoscale   "local" or "global"
                             If one or more of min_score and max_score options 
                             are absent, then these values will be calculated 
                             automatically. The "autoscale" option controls how
                             the calculation is done. The "local" value will
                             scale values according to the minimum and maximum
                             values present in the window being graphed. "global"   
                             will use chromosome-wide statistics for the entire
                             wiggle or dense file to find min and max values.


   smoothing   method name  Smoothing method: one of "mean", "max", "min" or "none"

   smoothing_window 
               integer      Number of values across which data should be smoothed.

   variance_band boolean    If true, draw a grey band across entire plot showing mean
                               and +/- 1 standard deviation (for wig files only).

   bicolor_pivot
               name         Where to pivot the two colors when drawing bicolor plots.
                               Options are "mean" and "zero". A numeric value can
                               also be provided.

   pos_color   color        When drawing bicolor plots, the fill color to use for values
                              that are above the pivot point.

   neg_color   color        When drawing bicolor plots, the fill color to use for values
                              that are below the pivot point.

=head2 SPECIAL FEATURE TAGS

The glyph expects one or more of the following tags (attributes) in
feature it renders:

   Name        Value        Description
   ----        -----        -----------

   wigfile     path name    Path to the Bio::Graphics::Wiggle file or object
                            for quantitative values.

   wigdata     string       Data exported from a Bio::Graphics::Wiggle in WIF
                            format using its export_to_wif64() method.

   densefile   path name    Path to a Bio::Graphics::DenseFeature object
                               (deprecated)

   denseoffset integer      Integer offset to where the data begins in the
                               Bio::Graphics::DenseFeature file (deprecated)

   densesize   integer      Integer size of the data in the Bio::Graphics::DenseFeature
                               file (deprecated)

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Glyph>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::cds>,
L<Bio::Graphics::Glyph::crossbox>,
L<Bio::Graphics::Glyph::diamond>,
L<Bio::Graphics::Glyph::dna>,
L<Bio::Graphics::Glyph::dot>,
L<Bio::Graphics::Glyph::ellipse>,
L<Bio::Graphics::Glyph::extending_arrow>,
L<Bio::Graphics::Glyph::generic>,
L<Bio::Graphics::Glyph::graded_segments>,
L<Bio::Graphics::Glyph::heterogeneous_segments>,
L<Bio::Graphics::Glyph::line>,
L<Bio::Graphics::Glyph::pinsertion>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::rndrect>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::ruler_arrow>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::translation>,
L<Bio::Graphics::Glyph::allele_tower>,
L<Bio::DB::GFF>,
L<Bio::SeqI>,
L<Bio::SeqFeatureI>,
L<Bio::Das>,
L<GD>

=head1 AUTHOR

Lincoln Stein E<lt>steinl@cshl.eduE<gt>.

Copyright (c) 2007 Cold Spring Harbor Laboratory

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut
