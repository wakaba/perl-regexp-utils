#!/usr/bin/perl
use strict;
use warnings;
use feature 'state';
use CGI::Carp qw(fatalsToBrowser);

use lib q[/home/wakaba/work/manakai2/lib];
use Message::CGI::Util qw/percent_decode/;

use Regexp::Parser;
use Graph::Easy;

use Scalar::Util qw/refaddr/;

my $default_map = {};
for (qw/. \C \w \W \s \S \d \D \X \1 \2 \3 \4 \5 \6 \7 \8 \9
        \A ^ \B \b \G \Z \z $/) {
  $default_map->{$_} = qq[Perl /$_/];
}

my $assertion_map = {
    ifmatch => '(?=)',
    '<ifmatch' => '(?<=)',
    unlessm => '(?!)',
    '<unlessm' => '(?<!)',
};

my $regexp = percent_decode $ENV{QUERY_STRING};
$regexp = '(?:)' unless length $regexp;

my $parser = Regexp::Parser->new;

package Regexp::Parser;

  # start of char class range (or maybe just char)
  $parser->add_handler('cc' => sub {
    my ($S) = @_;
    return if ${&Rx} =~ m{ \G (?= ] | \z ) }xgc;
    push @{ $S->{next} }, qw< cc >;
    my ($lhs, $rhs, $before_range);
    my $ret = \$lhs;

{
  if (${&Rx} =~ m{ \G ( \\ ) }xgcs) {
        my $c = $1;
        $$ret = $S->$c(1);
      }
elsif (${&Rx} =~ m{ \G \[ ([.=:]) (\^?) (.*?) \1 \] }xgcs) {
        my ($how, $neg, $name) = ($1, $2, $3);
        my $posix = "POSIX_$name";
        if ($S->can($posix)) { $$ret = $S->$posix($neg, $how) }
        else { $S->error(RPe_BADPOS, "$how$neg$name$how") }
      }
      elsif (${&Rx} =~ m{ \G (.) }xgcs) {
        $$ret = $S->force_object(anyof_char => $1);
      }

if ($ret == \$lhs) {
  if (${&Rx} =~ m{ \G (?= - ) }xgc) {
  if ($lhs->visual =~ /^(?:\[[:.=]|\\[dDsSwWpP])/) {
            $S->warn(RPe_FRANGE, $lhs->visual, "");
            $ret = $lhs;
            last;
          }
          $before_range = &RxPOS++;
          $ret = \$rhs;
          redo;
}
        $ret = $lhs;
      }
elsif ($ret == \$rhs) {
  if ($rhs->visual =~ /^(?:\[[:.=]|\\[dDsSwWpP])/) {
          $S->warn(RPe_FRANGE, $lhs->visual, $rhs->visual);
          &RxPOS = $before_range;
          $ret = $lhs;
        }
  elsif ($lhs->data gt $rhs->data) {
          $S->error(RPe_IRANGE, $lhs->visual, $rhs->visual);
        }
        else {
          $ret = $S->object(anyof_range => $lhs, $rhs);
        }
}
    }

    return if &SIZE_ONLY;
    return $ret;
  });

package main;

$parser->parse ($regexp);

binmode STDOUT, ':encoding(utf-8)';
print "Content-Type: application/xhtml+xml; charset=utf-8\n\n";

print $parser->errnum, $parser->errmsg;

add_regexp ($parser->root);

print q[<html xmlns="http://www.w3.org/1999/xhtml">
<head><title></title>
</head>
<body>];

my @regexp;
while (@regexp) {
  my $nodes = shift @regexp;

  my $index = get_graph_index ($nodes);
  print "<section><h1>Regexp #$index</h1>\n\n";

  my $g = generate_graph ($nodes);
  print $g->as_svg;

  print "</section>\n";
}

print q[</body></html>];

sub escape_value ($) {
  my $v = shift;
  $v =~ s/(\W)/sprintf '\x{%04X}', ord $1/ge;
  $v;
} # escape_value

sub escape_code ($) {
  my $v = shift;
  $v =~ s/([^\x20-\x5B\x5D-\x7E])/sprintf '\x{%04X}', ord $1/ge;
  $v;
} # escape_code

sub add_regexp ($) {
  my $nodes = shift;
  push @regexp, $nodes;
} # add_regexp

sub get_graph_index ($) {
  state $index;
  state $next_index ||= 0;

  my $nodes = shift;
  $index->{$nodes} //= $next_index++;
  return $index->{$nodes};
} # get_graph_index

sub generate_graph ($$) {
  my ($root_nodes) = @_;

  my $g = Graph::Easy->new;

  $g->set_attributes ('node.start' => {fill => 'blue', color => 'white'});
  $g->set_attributes ('node.success' => {fill => 'green', color => 'white'});
  
  my $start_n = $g->add_node ('START');
  $start_n->set_attribute (class => 'start');
  my $success_n = $g->add_node ('SUCCESS');
  $success_n->set_attribute (class => 'success');

  my ($first_ns, $last_ns, $is_optional) = add_to_graph ($root_nodes => $g);
  $g->add_edge ($start_n => $_) for @$first_ns;
  $g->add_edge ($_ => $success_n) for @$last_ns;
  $g->add_edge ($start_n => $success_n) if $is_optional;
  
  return $g;
} # generate_graph

sub add_to_graph ($$) {
  my ($node, $g) = @_;

  my $family = ref $node eq 'ARRAY' ? '' : $node->family;
  my $type = ref $node eq 'ARRAY' ? '' : $node->type;
  if ($family eq 'quant') {
    my ($min, $max) = ($node->min, $node->max);
    return ([], [], 1) if $max eq '0';
    my ($first_ns, $last_ns, $is_optional) = add_to_graph ($node->data => $g);

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
      my ($f_ns, $l_ns, $is_opt) = add_to_graph ($_ => $g);
      push @first_n, @$f_ns;
      push @last_n, @$l_ns;
      $is_optional |= $is_opt;
    }
    return (\@first_n, \@last_n, $is_optional);
  } elsif ($type eq 'anyof') {
    if ($node->neg) {
      my $nodes = Regexp::Parser::branch->new ($node->{rx});
      $nodes->{data} = $node->data;
      
      add_regexp ($nodes);
      
      my $n = $g->add_node (refaddr $nodes);
      my $label = 'NOT #' . get_graph_index ($nodes);
      $n->set_attribute (label => $label);
      
      return ([$n], [$n], 0);      
    } else {
      my @first_n;
      my @last_n;
      for (@{$node->data}) {
        my ($f_ns, $l_ns) = add_to_graph ($_ => $g);
        push @first_n, @$f_ns;
        push @last_n, @$l_ns;
      }
      return (\@first_n, \@last_n, 0);
    }
  } elsif ($type eq '') {
    my $prev_ns;
    my $first_ns;
    my $is_optional = 1;
    for (@{$node}) {
      my ($f_ns, $l_ns, $is_opt) = add_to_graph ($_ => $g);
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
    my ($f_ns, $l_ns, $is_opt) = add_to_graph ($node->data => $g);
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
      my ($f_ns, $l_ns, $is_opt) = add_to_graph ($true => $g);
      $g->add_edge ($n => $_)->set_attribute (label => 'true') for @$f_ns;
      $g->add_edge ($_ => $l) for @$l_ns;
      $g->add_edge ($n => $l)->set_attribute (label => 'true') if $is_opt;
    }

    my $false = $branches->[1];
    if ($false) {
      my ($f_ns, $l_ns, $is_opt) = add_to_graph ($false => $g);
      $g->add_edge ($n => $_)->set_attribute (label => 'false') for @$f_ns;
      $g->add_edge ($_ => $l) for @$l_ns;
      $g->add_edge ($n => $l)->set_attribute (label => 'false') if $is_opt;
    }
    
    return ([$n], [$l], 0);
  } elsif ($type eq 'eval' or $type eq 'logical') {
    my $n = $g->add_node (refaddr $node);
    my $label = $type eq 'eval' ? '(?{})' : '(??{})';
    $label .= ' ' . escape_code $node->data;
    $n->set_attribute (label => $label);
    return ([$n], [$n], 0);
  } elsif ($family eq 'assertion') {
    my $nodes = $node->data;
    add_regexp ($nodes);
    
    my $n = $g->add_node (refaddr $nodes);
    $type = '<' . $type if $node->dir < 0;
    my $label = $assertion_map->{$type} // $type;
    $label .= ' #' . get_graph_index ($nodes);
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
        $label = $data->neg ? 'Perl /\S/' : 'Perl /\s/';
      } elsif ($data_family eq 'alnum') {
        $label = $data->neg ? 'Perl /\W/' : 'Perl /\w/';
      } elsif ($data_family eq 'digit') {
        $label = $data->neg ? 'Perl /\D/' : 'Perl /\d/';
      } else {
        $label = $data->visual;
      }
    }
  
    my $n = $g->add_node (refaddr $node);
    $n->set_attribute (label => $label);
    
    return ([$n] => [$n]);
  } elsif ($family eq 'exact' or $type eq 'anyof_char') {
    my $n = $g->add_node (refaddr $node);

    my $label = escape_value $node->data;
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
    add_regexp ($nodes);

    my $n = $g->add_node (refaddr $nodes);
    my $label = 'non-greedy #' . get_graph_index ($nodes);
    $n->set_attribute (label => $label);

    return ([$n], [$n], 0);
  } elsif ($family eq 'anyof_range') {
    my $n = $g->add_node (refaddr $node);

    my $start = escape_value $node->data->[0]->data;
    my $end = escape_value $node->data->[1]->data;
    my $label = qq[ one of "$start" .. "$end" ];
    $n->set_attribute (label => $label);

    return ([$n] => [$n], 0);
  } else {
    # anyof_char
    # anyof_range

    my $n = $g->add_node (refaddr $node);
    
    my $label = $node->visual;
    $label = $default_map->{$label} // escape_value $label;
    $label .= ' (' . $type . ')';
    $n->set_attribute (label => $label);
    
    return ([$n] => [$n], 0);
  }
} # add_to_graph

