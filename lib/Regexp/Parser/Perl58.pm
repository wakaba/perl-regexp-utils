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

1;
