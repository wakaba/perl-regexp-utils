#!/usr/bin/perl
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use Path::Tiny;
use lib path (__FILE__)->parent->parent->child ('lib')->stringify;
use Web::Encoding;

sub htescape ($) {
  my $s = shift;
  $s =~ s/&/&amp;/g;
  $s =~ s/</&lt;/g;
  $s =~ s/"/&quot;/g;
  return $s;
} # htescape

my %qp = map { s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge; $_ } map { split /=/, $_, 2 } split /&/, $ENV{QUERY_STRING} // '';

my $regexp = decode_web_utf8 $qp{s} // '';
$regexp = '(?:)' unless length $regexp;
my $eregexp = htescape $regexp;

my $lang = $qp{l} // 'perl58';
my $class = $lang eq 'js'
    ? 'Regexp::Parser::JavaScript'
    : 'Regexp::Parser::Perl58';

eval qq{ require $class } or die $@;
my $parser = $class->new;

my $footer = q[
  <footer>
  [<a href="input">Input</a>]
  [<a href="../doc/readme">Source</a>]
  </footer>
];

my @error;
$parser->onerror (sub {
  my %args = @_;
  my $r = '<li>';
  if ($args{level} eq 'w') {
    $r .= '<strong>Warning</strong>: ';
  } else {
    $r .= '<strong>Error</strong>: ';
  }

  $r .= htescape sprintf $args{type}, @{$args{args}};

  $r .= ': <code>';
  $r .= htescape substr ${$args{valueref}}, 0, $args{pos_start};
  $r .= '<mark>';
  $r .= htescape substr ${$args{valueref}},
      $args{pos_start}, $args{pos_end} - $args{pos_start};
  $r .= '</mark>';
  $r .= htescape substr ${$args{valueref}}, $args{pos_end};
  $r .= '</code></li>';

  push @error, $r;
});

eval {
  $parser->parse ($regexp);
};

if ($parser->errnum) {
  binmode STDOUT, ':encoding(utf-8)';
  print "Content-Type: text/html; charset=utf-8\n\n";
  print q[<!DOCTYPE HTML><html lang=en>
<title>Regular expression visualizer: ], $eregexp, q[</title>
<link rel="stylesheet" href="/www/style/html/xhtml">

<h1>Regular expression visualizer</h1>

<p>Input: <code>], $eregexp, q[</code></p>

<p>Error:
<ul>];
  print join '', @error;
  print q[</ul>];

  print $footer;

  exit;
}

require Regexp::Visualize::Simple;
my $v = Regexp::Visualize::Simple->new;
$v->push_regexp_node ($parser->root);

binmode STDOUT, ':encoding(utf-8)';
print "Content-Type: application/xhtml+xml; charset=utf-8\n\n";

print q[<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head><title>Regular expression visualizer: ], $eregexp, q[</title>
<link rel="stylesheet" href="/www/style/html/xhtml"/>
</head>
<body>
<h1>Regular expression visualizer</h1>

<p>Input: <code>], $eregexp, q[</code></p>];

if (@error) {
  print q[<ul>];
  print join '', @error;
  print q[</ul>];
}

while ($v->has_regexp_node) {
  my ($g, $index) = $v->next_graph;

  print "<section><h2>Regexp #$index</h2>\n\n";
  print $g->as_svg;
  print "</section>\n";
}

print $footer;

print q[</body></html>];
