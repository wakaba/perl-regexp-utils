package Regexp::Parser::JavaScript;
our $VERSION=do{my @r=(q$Revision: 1.3 $=~/\d+/g);sprintf "%d."."%02d" x $#r,@r};
use strict;
use warnings;

use Regexp::Parser::Perl58;
use Regexp::Parser qw(:original :RPe);
push our @ISA, 'Regexp::Parser::Perl58';

use constant RPJSe_OCTESC => 80130, 'Octal escape is obsolete';

my $IdentifierStart = qr/[
                          ## UnicodeLetter
                          \p{Lu}\p{Ll}\p{Lt}\p{Lm}\p{Lo}\p{Nl}

                          $ _ 
                         ]/x;

sub init ($) {
  my $self = shift;
  $self->SUPER::init;

  $self->{enum_to_level}->{[RPe_BADESC]->[0]} = 'm';
  $self->{enum_to_level}->{[RPe_BGROUP]->[0]} = 'm';
  $self->{enum_to_level}->{[RPJSe_OCTESC]->[0]} = 'm';
  $self->{enum_to_level}->{[RPe_FRANGE]->[0]} = 'm';

  $self->del_handler (qw/
                         \a \e \A \C \G \N \P \p \X \Z \z
                         (?# (?$ (?@ (?< (?> (?{ (?? (?p (?(
                        /);

  $self->add_handler('\v' => sub {
    my ($S, $cc) = @_;
    return $S->force_object(anyof_char => "\x0B", '\v') if $cc;
    return $S->object(exact => "\x0B" => '\v');
  });

  $self->add_handler('\n' => sub {
    my ($S, $cc) = @_;
    return $S->force_object(anyof_char => "\x0A", '\n') if $cc;
    return $S->object(exact => "\x0A" => '\n');
  });

  $self->add_handler('\r' => sub {
    my ($S, $cc) = @_;
    return $S->force_object(anyof_char => "\x0D", '\r') if $cc;
    return $S->object(exact => "\x0D" => '\r');
  });

  # backslash
  $self->add_handler('\\' => sub {
    my ($S, $cc) = @_;
    my $c = '\\';

    if (${&Rx} =~ m{ \G (.) }xgcs) {
      $c .= (my $n = $1);

      return $S->$c($cc) if $S->can($c);

      my $family = $cc ? 'anyof_char' : 'exact';

      if ($n =~ /\d/) {
        ## See <http://suika.fam.cx/%7Ewakaba/wiki/sw/n/%E5%85%AB%E9%80%B2%E3%82%A8%E3%82%B9%E3%82%B1%E3%83%BC%E3%83%97>.

        if ($n =~ /^[0-3]/ and ${&Rx} =~ m{ \G ([0-7]{1,2}) }xgc) {
          $n .= $1;
        }
        elsif ($n =~ /^[4-7]/ and ${&Rx} =~ m{ \G ([0-7]) }xgc) {
          $n .= $1;
        }

        # outside of char class, \nnn might be backref
        if (!&SIZE_ONLY and !$cc and $n !~ /^0/) {
          unless ($n > $S->{maxpar}) {
            return $S->object(ref => $n, "\\$n");
          }
        }
        if ($n =~ /^[89]/) {
          $S->warn(RPe_BGROUP);
          return $S->object($family => chr 0x30 + $n,
                            sprintf("\\x%02x", 0x30 + $n));
        }

        if ($n eq '0') {
          #
        } elsif ($n =~ /^0/ or $cc) {
          $S->warn(RPJSe_OCTESC);
        } elsif ($n > $S->{maxpar}) {
          $S->warn(RPe_BGROUP);
        }
        return $S->object($family => chr oct $n, sprintf("\\%03s", $n));
      }

      $S->warn(RPe_BADESC, $c = $n, "") if $n =~ /$IdentifierStart/o;

      return $S->object($family => $n, $c);
    }

    $S->error(RPe_ESLASH);
  });

  # control character
  $self->add_handler('\c' => sub {
    my ($S, $cc) = @_;
    ## See <http://suika.fam.cx/%7Ewakaba/wiki/sw/n/%5Cc>.
    if (${&Rx} =~ m{ \G ([A-Za-z]) }xgc) {
      my $c = $1;
      $c =~ tr/a-z/A-Z/;
      return $S->force_object(anyof_char => chr(64 ^ ord $c), "\\c$c") if $cc;
      return $S->object(exact => chr(64 ^ ord $c), "\\c$c");
    } else {
      my $c = 'c';
      $S->warn(RPe_BADESC, $c, "");
      return $S->object(($cc ? 'anyof_char' : 'exact') => $c, $c);
    }
  });

  # hex character
  $self->add_handler('\x' => sub {
    my ($S, $cc) = @_;

    my $num;
    if (${&Rx} =~ m{ \G ( [0-9A-Fa-f]{2} ) }sxgc) {
      $num = hex $1;
    } else {
      $num = ord 'x';
      $S->warn(RPe_BADESC, 'x', "");
    }

    my $rep = sprintf("\\x%02X", $num);
    return $S->force_object(anyof_char => chr $num, $rep) if $cc;
    return $S->object(exact => chr $num, $rep);
  });

  # \u
  $self->add_handler('\u' => sub {
    my ($S, $cc) = @_;

    my $num;
    if (${&Rx} =~ m{ \G ( [0-9A-Fa-f]{4} ) }sxgc) {
      $num = hex $1;
    } else {
      $num = ord 'u';
      $S->warn(RPe_BADESC, 'u', "");
    }
    
    my $rep = sprintf("\\u%04X", $num);
    return $S->force_object(anyof_char => chr $num, $rep) if $cc;
    return $S->object(exact => chr $num, $rep);
  });

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
      elsif (${&Rx} =~ m{ \G (.) }xgcs) {
        $$ret = $S->force_object(anyof_char => $1);
      }

      if ($ret == \$lhs) {
        if (${&Rx} =~ m{ \G (?= - ) }xgc) {
          if ($lhs->visual =~ /^\\[dDsSwW]/) {
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
        if ($rhs->visual =~ /^\\[dDsSwW]/) {
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

  # char class ] at beginning
  $self->add_handler('cc]' => sub {
    my ($S) = @_;
    return unless ${&Rx} =~ m{ \G ] }xgc;
    pop @{ $S->{next} }; # cc
    pop @{ $S->{next} }; # cce]
    return $S->object(anyof_close => "]");
  });

  # some kind of assertion...
  $self->add_handler('(?' => sub {
    my ($S) = @_;
    my $c = '(?';

    if (${&Rx} =~ m{ \G (.) }xgcs) {
      my $n = "$c$1";
      return $S->$n if $S->can($n);
      &RxPOS--;
    }
    else {
      $S->error(RPe_SEQINC);
    }

    my $old = &RxPOS;

    if (${&Rx} =~ m{ \G : }xgc) {
      push @{ $S->{flags} }, &Rf;
      push @{ $S->{next} }, qw< c) atom >;
      return $S->object('group', 0, 0);
    }

    &RxPOS++;
    $S->error(RPe_NOTREC, 0, substr(${&Rx}, $old));
  });

} # init

1;

__END__

=head1 LICENSE

Copyright 2008-2009 Wakaba <w@suika.fam.cx>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# $Date: 2009/03/08 14:30:51 $
