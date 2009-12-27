#!/usr/bin/perl
use strict;
use ExtUtils::MakeMaker;
WriteMakefile (
    NAME         => 'Regexp::Visualize',
    DISTNAME     => 'Regexp-Visualize',
    VERSION => '1.5',
    PREREQ_PM => {
      'Carp' => 0,
      'CGI::Carp' => 0,
#      'manakai' => 0,
      'Encode' => 0,
      'Scalar::Util' => 0,
      'Path::Class' => 0,
      'UNIVERSAL::require' => 0,
      'Regexp::Parser' => 0,
      'Graph::Easy' => 0,
    },
    dist         => {COMPRESS => 'gzip', SUFFIX => '.gz'},
    AUTHOR       => q(Wakaba <w@suika.fam.cx>),
);
