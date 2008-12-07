#!/usr/bin/perl
use strict;
use warnings;
use feature 'state';
use CGI::Carp qw(fatalsToBrowser);

use FindBin;
use lib qq[$FindBin::Bin/../lib];
use lib q[/home/wakaba/work/manakai2/lib];
use Message::CGI::Util qw/percent_decode htescape/;
use Message::CGI::HTTP;

use Regexp::Parser::Perl58;

my $cgi = Message::CGI::HTTP->new;

my $regexp = percent_decode $cgi->get_parameter ('s') // '';
$regexp = '(?:)' unless length $regexp;

my $parser = Regexp::Parser::Perl58->new;

eval {
  $parser->parse ($regexp);
};
my $eregexp = htescape $regexp;

if ($parser->errnum) {
  binmode STDOUT, ':encoding(utf-8)';
  print "Content-Type: text/html; charset=utf-8\n\n";
  print q[<!DOCTYPE HTML><html lang=en>
<title>Regular expression visualizer: $eregexp</title>
<link rel="stylesheet" href="/www/style/html/xhtml"/>
</head>
<body>
<h1>Regular expression visualizer</h1>

<p>Input: <code>], $eregexp, q[</code></p>

<p>Error: ], htescape ($parser->errmsg);
  exit;
}

require Regexp::Visualize::Simple;
my $v = Regexp::Visualize::Simple->new;
$v->push_regexp_node ($parser->root);

binmode STDOUT, ':encoding(utf-8)';
print "Content-Type: application/xhtml+xml; charset=utf-8\n\n";

print q[<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head><title>Regular expression visualizer: $eregexp</title>
<link rel="stylesheet" href="/www/style/html/xhtml"/>
</head>
<body>
<h1>Regular expression visualizer</h1>

<p>Input: <code>], $eregexp, q[</code></p>];

while ($v->has_regexp_node) {
  my ($g, $index) = $v->next_graph;

  print "<section><h2>Regexp #$index</h2>\n\n";
  print $g->as_svg;
  print "</section>\n";
}

print q[</body></html>];

