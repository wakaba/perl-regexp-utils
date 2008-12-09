package Regexp::Parser::Perl58;
use strict;
use warnings;

BEGIN {
  $Regexp::Parser::EXPORT_TAGS{original}
      = [qw/Rx RxPOS RxCUR RxLEN Rf SIZE_ONLY LATEST/];
  my @error = qw(RPe_ZQUANT RPe_NOTIMP RPe_NOTERM RPe_LOGDEP RPe_NOTBAL
                 RPe_SWNREC RPe_SWBRAN RPe_SWUNKN RPe_SEQINC RPe_BADFLG
                 RPe_NOTREC RPe_LPAREN RPe_RPAREN RPe_BCURLY RPe_NULNUL
                 RPe_NESTED RPe_LBRACK RPe_EQUANT RPe_BRACES RPe_RBRACE
                 RPe_BGROUP RPe_ESLASH RPe_BADESC RPe_BADPOS RPe_OUTPOS
                 RPe_EMPTYB RPe_FRANGE RPe_IRANGE);
  push @Regexp::Parser::EXPORT_OK, @error;
  $Regexp::Parser::EXPORT_TAGS{RPe} = \@error;
}

use Regexp::Parser 0.20 qw(:original :RPe);
push our @ISA, 'Regexp::Parser';

my $error_pos_diff = {
  [RPe_NOTERM]->[0] => 0,
  [RPe_LOGDEP]->[0] => 4, # (?p{
  [RPe_NOTBAL]->[0] => 3, # (?p{, (?p{, (??{
  [RPe_SWNREC]->[0] => 0, # (?(12_aa)
  [RPe_NOTREC]->[0] => 3, # (?_
  [RPe_RBRACE]->[0] => 0, # \p{_
  [RPe_BRACES]->[0] => 2, # \N
  [RPe_BGROUP]->[0] => 2, # \[0-9]{1}
  [RPe_BADESC]->[0] => 2, # \_
};

sub init ($) {
  my $self = shift;

  $self->SUPER::init;

  ## NOTE: Regexp::Parser 0.20 supports Perl 5.8 regular expression,
  ## but it's [x-y] range support has a bug.
  
  # start of char class range (or maybe just char)
  $self->add_handler('cc' => sub {
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
        elsif ($lhs->data gt $rhs->data) { ## ->visual in the original code.
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
} # init

sub regex {
  my ($self, $rx) = @_;
  %$self = (
    regex => \"$rx",
    len => length $rx,
    tree => undef,
    stack => [],
    maxpar => 0,
    nparen => 0,
    captures => [],
    flags => [0],
    next => ['atom'],
    onerror => $self->{onerror},
  );

  # do the initial scan (populates maxpar)
  # because tree is undef, nothing gets built
  &RxPOS = 0;
  eval { $self->parse };
  $self->{errmsg} = $@, return if $@;

  # reset things, define tree as []
  &RxPOS = 0;
  $self->{tree} = [];
  $self->{flags} = [0];
  $self->{next} = ['atom'];

  return 1;
}

sub nextchar {
  my ($self) = @_;

  {
    if ($self->can('(?#') and
        ${&Rx} =~ m{ \G \(\?\# [^)]* }xgc) {
      ${&Rx} =~ m{ \G \) }xgc and redo;
      $self->error(RPe_NOTERM);
    }
    &Rf & $self->FLAG_x and ${&Rx} =~ m{ \G (?: \s+ | \# .* )+ }xgc and redo;
  }
}

sub error {
  my ($self, $enum, $err, @args) = @_;
  if ($self->{onerror}) {
    my $pos_diff = $error_pos_diff->{$enum} // 1;
    $self->{onerror}->(code => $enum, type => $err,
                       valueref => &Rx,
                       pos_start => &RxPOS - $pos_diff, pos_end => &RxPOS,
                       level => 'm', args => \@args);
  }
  shift->SUPER::error (@_);
} # error

sub warn {
  my ($self, $enum, $err, @args) = @_;
  if ($self->{onerror} and &SIZE_ONLY) {
    my $pos_diff = $error_pos_diff->{$enum} // 1;
    $self->{onerror}->(code => $enum, type => $err,
                       valueref => &Rx,
                       pos_start => &RxPOS - $pos_diff, pos_end => &RxPOS,
                       level => 'w', args => \@args);
  }
  shift->SUPER::warn (@_);
} # warn

sub onerror {
  my $self = $_[0];
  if (@_ > 1) {
    if ($_[1]) {
      $self->{onerror} = $_[1];
    } else {
      delete $self->{onerror};
    }
  }
  return $self->{onerror};
} # onerror

1;
