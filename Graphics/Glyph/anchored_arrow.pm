package Bio::Graphics::Glyph::anchored_arrow;
# package to use for drawing an arrow

use strict;
use vars '@ISA';
use Bio::Graphics::Glyph::arrow;
@ISA = 'Bio::Graphics::Glyph::arrow';

sub draw_label {
  my $self = shift;
  my ($gd,$left,$top,$partno,$total_parts) = @_;
  my $label = $self->label or return;
  my $label_align = $self->option('label_align');
  if ($label_align && ($label_align eq 'center' || $label_align eq 'right')) {
      my $x = $self->left + $left;
      my $font = $self->option('labelfont') || $self->font;
      my $middle = $self->left + $left + ($self->right - $self->left) / 2;
      my $label_width = $font->width * length($label);
      if ($label_align eq 'center') {
          my $new_x = $middle - $label_width / 2;
          $x = $new_x if ($new_x > $x);;
      }
      else {
          my $new_x = $left + $self->right - $label_width;
          $x = $new_x if ($new_x > $x);
      }
      $x = $self->panel->left + 1 if $x <= $self->panel->left;
      #detect collision (mostlikely no bump when want centering label)
      #lay down all features on one line e.g. cyto bands
      return if (!$self->option('bump') && ($label_width + $x) > $self->right);
      $gd->string($font,
                  $x,
                  $self->top + $top,
                  $label,
                  $self->fontcolor);
  }
  else {
      $self->SUPER::draw_label(@_);
  }
}

sub arrowheads {
  my $self = shift;
  my ($ne,$sw,$base_e,$base_w);
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries(@_);

  my $gstart  = $x1;
  my $gend    = $x2;
  my $pstart  = $self->panel->left;
  my $pend    = $self->panel->right;

  if ($gstart < $pstart) {  # off left end
    $sw = 1;
  }
  if ($gend > $pend) { # off right end
    $ne = 1;
  }
  return ($sw,$ne,!$sw,!$ne);
}

1;

__END__

=head1 NAME

Bio::Graphics::Glyph::anchored_arrow - The "anchored_arrow" glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph draws an arrowhead which is anchored at one or both ends
(has a vertical base) or has one or more arrowheads.  The arrowheads
indicate that the feature does not end at the edge of the picture, but
continues.  For example:

    |-----------------------------|          both ends in picture
 <----------------------|                    left end off picture
         |---------------------------->      right end off picture
 <------------------------------------>      both ends off picture


=head2 OPTIONS

In addition to the standard options, this glyph recognizes the following:

  Option         Description                Default

  -tick          draw a scale               0
  -rel_coords    use relative coordinates   false
                 for scale

The argument for b<-tick> is an integer between 0 and 2 and has the same
interpretation as the b<-tick> option in Bio::Graphics::Glyph::arrow.

If b<-rel_coords> is set to a true value, then the scale drawn on the
glyph will be in relative (1-based) coordinates relative to the beginning
of the glyph.

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Ace::Sequence>, L<Ace::Sequence::Feature>, L<Bio::Graphics::Panel>,
L<Bio::Graphics::Track>, L<Bio::Graphics::Glyph::anchored_arrow>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::box>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,

=head1 AUTHOR

Allen Day <day@cshl.org>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut
