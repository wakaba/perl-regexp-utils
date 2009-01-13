package Regexp::Visualize::Simple;
our $VERSION=do{my @r=(q$Revision: 1.5 $=~/\d+/g);sprintf "%d."."%02d" x $#r,@r};
use strict;
use warnings;

use Graph::Easy;

use Scalar::Util qw/refaddr/;

my $default_map = {};
for (qw/. \C \w \W \s \S \d \D \X \1 \2 \3 \4 \5 \6 \7 \8 \9
        \A ^ \B \b \G \Z \z $/) {
  $default_map->{$_} = $_;
}

my $assertion_map = {
    ifmatch => '(?=)',
    '<ifmatch' => '(?<=)',
    unlessm => '(?!)',
    '<unlessm' => '(?<!)',
};

sub new ($) {
  my $self = bless {}, shift;
  $self->{next_index} = 0;
  $self->{regexp_nodes} = [];
  return $self;
} # new

sub _escape_value ($) {
  my $v = shift;
  $v =~ s/(\W)/sprintf '\x{%04X}', ord $1/ge;
  $v;
} # _escape_value

sub _escape_code ($) {
  my $v = shift;
  $v =~ s/([^\x20-\x5B\x5D-\x7E])/sprintf '\x{%04X}', ord $1/ge;
  $v;
} # _escape_code

sub push_regexp_node ($$) {
  my $self = shift;
  my $nodes = shift; # Regexp::Parser's node or array ref of nodes
  push @{$self->{regexp}}, $nodes;
  return $self->get_graph_index ($nodes);
} # push_regexp_node

sub shift_regexp_node ($) {
  my $self = shift;
  return shift @{$self->{regexp}};
} # shift_regexp_node

sub has_regexp_node ($) {
  my $self = shift;
  return scalar @{$self->{regexp}};
} # has_regexp_node

sub get_graph_index ($$) {
  my $self = shift;
  my $nodes = shift;
  $self->{index}->{$nodes} //= $self->{next_index}++;
  return $self->{index}->{$nodes};
} # get_graph_index

sub next_graph ($) {
  my $self = shift;
  my $root_nodes = $self->shift_regexp_node;
  return (undef, undef) unless $root_nodes;

  my $g = Graph::Easy->new;

  $g->set_attributes ('node.start' => {fill => 'blue', color => 'white'});
  $g->set_attributes ('node.success' => {fill => 'green', color => 'white'});
  $g->set_attributes ('node.fail' => {fill => 'red', color => 'white'});
  $g->set_attributes ('edge.fail' => {color => 'gray'});
  
  my $start_n = $g->add_node ('START');
  $start_n->set_attribute (class => 'start');
  my $success_n = $g->add_node ('SUCCESS');
  $success_n->set_attribute (class => 'success');
  my $fail_n = $g->add_node ('FAIL');
  $fail_n->set_attribute (class => 'fail');

  my ($first_ns, $last_ns, $is_optional)
      = $self->_add_to_graph ($root_nodes => $g);
  $g->add_edge ($start_n => $_) for @$first_ns;
  $g->add_edge ($_ => $success_n) for @$last_ns;
  $g->add_edge ($start_n => $success_n) if $is_optional;

  $g->del_node ($success_n) unless $success_n->incoming;
  $g->del_node ($fail_n) unless $fail_n->incoming;
  $_->set_attribute ('class' => 'fail') for $fail_n->outgoing;
  
  return ($g, $self->get_graph_index ($root_nodes));
} # next_graph

sub _add_to_graph ($$$) {
  my ($self, $node, $g) = @_;

  my $family = ref $node eq 'ARRAY' ? '' : $node->family;
  my $type = ref $node eq 'ARRAY' ? '' : $node->type;
  if ($family eq 'quant') {
    my ($min, $max) = ($node->min, $node->max);
    return ([], [], 1) if $max eq '0';
    my ($first_ns, $last_ns, $is_optional)
        = $self->_add_to_graph ($node->data => $g);

    my $label;
    if ($max eq '') {
      if ($min == 0) {
        $is_optional = 1;
        $label = '';
        
      } elsif ($min == 1) {
        $label = '';
        
      } else {
        $label = 'at least ' . ($min - 1);
        
      }
    } elsif ($max == 1) {
      if ($min == 0) {
        $is_optional = 1;
        
      } else {
        
      }
    } else {
      $label = 'at most ' . ($max - 1);
      if ($min == 0) {
        $is_optional = 1;
        

      } elsif ($min == 1) {
        
      } else {
        $label = 'at least ' . ($min - 1) . ', ' . $label;

      }
    }
    
    if (@$first_ns != 1 or @$last_ns != 1) {
      my $n = $g->add_node (refaddr $first_ns);
      $n->set_attribute (label => '');
      my $m = $n;
      unless ($is_optional) {
        $m = $g->add_node (refaddr $last_ns);
        $m->set_attribute (label => '');
      } else {
        $is_optional = 0;
      }
      $g->add_edge ($n => $_) for @$first_ns;
      $g->add_edge ($_ => $m) for @$last_ns;
      $first_ns = [$n];
      $last_ns = [$m];
    }

    if (defined $label) {
      my $e = $g->add_edge ($last_ns->[0] => $first_ns->[0]);
      $e->set_attribute (label => $label);
    }

    return ($first_ns, $last_ns, $is_optional);
  } elsif ($type eq 'branch') {
    my @first_n;
    my @last_n;
    my $is_optional = 0;
    for (@{$node->data}) {
      my ($f_ns, $l_ns, $is_opt) = $self->_add_to_graph ($_ => $g);
      push @first_n, @$f_ns;
      push @last_n, @$l_ns;
      $is_optional |= $is_opt;
    }
    return (\@first_n, \@last_n, $is_optional);
  } elsif ($type eq 'anyof') {
    my $data = $node->data;
    if ($node->neg) {
      if (@$data) {
        my $nodes = Regexp::Parser::branch->new ($node->{rx});
        $nodes->{data} = $node->data;
        
        $self->push_regexp_node ($nodes);
        
        my $n = $g->add_node (refaddr $nodes);
        my $label = 'NOT #' . $self->get_graph_index ($nodes);
        $n->set_attribute (label => $label);
        
        return ([$n], [$n], 0);      
      } else {
        my $n = $g->add_node (refaddr $node);
        my $label = 'Any character';
        $n->set_attribute (label => $label);

        return ([$n], [$n], 0);
      }
    } else {
      if (@$data) {
        my @first_n;
        my @last_n;
        for (@{$node->data}) {
          my ($f_ns, $l_ns) = $self->_add_to_graph ($_ => $g);
          push @first_n, @$f_ns;
          push @last_n, @$l_ns;
        }
        return (\@first_n, \@last_n, 0);
      } else {
        my $fail_n = $g->node ('FAIL');
        return ([$fail_n], [$fail_n], 0);
      }
    }
  } elsif ($family eq '' and $type eq '') {
    my $prev_ns;
    my $first_ns;
    my $is_optional = 1;
    for (@{$node}) {
      my ($f_ns, $l_ns, $is_opt) = $self->_add_to_graph ($_ => $g);
      if ($prev_ns) {
        if (@$prev_ns > 1 and @$f_ns > 1) {
          my $n = $g->add_node (refaddr $f_ns);
          $n->set_attribute (label => '');
          $g->add_edge ($_ => $n) for @$prev_ns;
          $g->add_edge ($n => $_) for @$f_ns;
        } else {
          for my $prev_n (@$prev_ns) {
            for my $f_n (@$f_ns) {
              $g->add_edge ($prev_n => $f_n);
            }
          }
        }
        if ($is_optional) {
          push @$first_ns, @$f_ns;
        }
        if ($is_opt) {
          push @$prev_ns, @$l_ns;
        } else {
          $prev_ns = $l_ns if @$l_ns;
        }
      } else {
        $first_ns = $f_ns;
        $prev_ns = $l_ns if @$l_ns;
      }
      $is_optional &= $is_opt;
    }
    return ($first_ns || [], $prev_ns || [], $is_optional);
  } elsif ($family eq 'group' or $family eq 'open' or $type eq 'suspend') {
    ## TODO: (?:) vs () vs (?>), (?:)->on, (?:)->off
    my ($f_ns, $l_ns, $is_opt) = $self->_add_to_graph ($node->data => $g);
    return ($f_ns, $l_ns, $is_opt);
  } elsif ($type eq 'ifthen') {
    my $nodes = $node->data;
    
    my $groupp = $nodes->[0];
    my $label = $groupp ? '(?' . $groupp->visual . ')' : '';
    my $n = $g->add_node (refaddr $groupp);
    $n->set_attribute (label => $label);

    my $l = $g->add_node (refaddr $nodes);
    $l->set_attribute (label => '');
    
    my $branch = $nodes->[1];
    my $branches = $branch ? $branch->data : [];
    
    my $true = $branches->[0];
    if ($true) {
      my ($f_ns, $l_ns, $is_opt) = $self->_add_to_graph ($true => $g);
      $g->add_edge ($n => $_)->set_attribute (label => 'true') for @$f_ns;
      $g->add_edge ($_ => $l) for @$l_ns;
      $g->add_edge ($n => $l)->set_attribute (label => 'true') if $is_opt;
    }

    my $false = $branches->[1];
    if ($false) {
      my ($f_ns, $l_ns, $is_opt) = $self->_add_to_graph ($false => $g);
      $g->add_edge ($n => $_)->set_attribute (label => 'false') for @$f_ns;
      $g->add_edge ($_ => $l) for @$l_ns;
      $g->add_edge ($n => $l)->set_attribute (label => 'false') if $is_opt;
    }
    
    return ([$n], [$l], 0);
  } elsif ($type eq 'eval' or $type eq 'logical') {
    my $n = $g->add_node (refaddr $node);
    my $label = $type eq 'eval' ? '(?{})' : '(??{})';
    $label .= ' ' . _escape_code $node->data;
    $n->set_attribute (label => $label);
    return ([$n], [$n], 0);
  } elsif ($family eq 'assertion') {
    my $nodes = $node->data;
    $self->push_regexp_node ($nodes);
    
    my $n = $g->add_node (refaddr $nodes);
    $type = '<' . $type if $node->dir < 0;
    my $label = $assertion_map->{$type} // $type;
    $label .= ' #' . $self->get_graph_index ($nodes);
    $n->set_attribute (label => $label);
    
    return ([$n], [$n], 0);
  } elsif ($family eq 'anyof_class') {
    my $data = $node->data;
    my $label;
    if ($data eq 'POSIX') {
      my $how = ${$node->{how}};
      if ($how eq ':') {
        $label = 'POSIX ' . $node->{type};
        $label = 'NOT ' . $label if $node->neg;
      } else {
        $label = $how . $node->neg . $node->{type} . $how;
      }
    } else {
      my $data_family = $data->family;
      if ($data_family eq 'prop') {
        $label = 'property ' . $node->type;
        $label = 'NOT ' . $label if $node->neg;
      } elsif ($data_family eq 'space') {
        $label = $data->neg ? '\S' : '\s';
      } elsif ($data_family eq 'alnum') {
        $label = $data->neg ? '\W' : '\w';
      } elsif ($data_family eq 'digit') {
        $label = $data->neg ? '\D' : '\d';
      } else {
        $label = $data->visual;
      }
    }
  
    my $n = $g->add_node (refaddr $node);
    $n->set_attribute (label => $label);
    
    return ([$n] => [$n]);
  } elsif ($family eq 'exact' or $type eq 'anyof_char') {
    my $n = $g->add_node (refaddr $node);

    my $label = _escape_value $node->data;
    $n->set_attribute (label => qq[ "$label" ]);

    return ([$n] => [$n]);
  } elsif ($family eq 'flags') {
    ## TODO: scope
    my $n = $g->add_node (refaddr $node);

    my $label = $node->visual;
    $n->set_attribute (label => $label);

    return ([$n] => [$n], 0);
  } elsif ($family eq 'minmod') {
    my $nodes = $node->data;
    $self->push_regexp_node ($nodes);

    my $n = $g->add_node (refaddr $nodes);
    my $label = 'non-greedy #' . $self->get_graph_index ($nodes);
    $n->set_attribute (label => $label);

    return ([$n], [$n], 0);
  } elsif ($family eq 'anyof_range') {
    my $n = $g->add_node (refaddr $node);

    my $start = _escape_value $node->data->[0]->data;
    my $end = _escape_value $node->data->[1]->data;
    my $label = qq[ one of "$start" .. "$end" ];
    $n->set_attribute (label => $label);

    return ([$n] => [$n], 0);
  } elsif ($family eq 'prop') {
    my $n = $g->add_node (refaddr $node);

    my $label = 'property ' . $node->type;
    $label = 'NOT ' . $label if $node->neg;
    $n->set_attribute (label => $label);

    return ([$n], [$n], 0);
  } else {
    my $n = $g->add_node (refaddr $node);
    
    my $label = $node->visual;
    $label = $default_map->{$label} // _escape_value $label;
    $label .= ' (' . $type . ')' unless $default_map->{$label};
    $n->set_attribute (label => $label);
    
    return ([$n] => [$n], 0);
  }
} # _add_to_graph

1;

__END__

=head1 LICENSE

Copyright 2008-2009 Wakaba <w@suika.fam.cx>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# $Date: 2009/01/13 14:15:46 $
