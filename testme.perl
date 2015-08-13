#!/usr/bin/perl -w
#-*- Mode: CPerl; coding: utf-8 -*-

use lib qw(.);
use Tie::File::Indexed;
use Tie::File::Indexed::Utf8;
use Tie::File::Indexed::JSON;
use Tie::File::Indexed::Storable;
use Tie::File::Indexed::StorableN;
use utf8;

BEGIN {
  binmode(\*STDOUT,':utf8');
  binmode(\*STDERR,':utf8');
}

##--------------------------------------------------------------
## tests: generic
sub isok {
  my $label = shift;
  print "$label: ", ($_[0] ? "ok" : "NOT ok"), "\n";
}

sub listok {
  my ($label,$l1,$l2) = shift;
  my $rc = ($#$l1==$#$l2);
  foreach (my $i=0; $rc && $i < @$l1; ++$i) {
    $rc &&= ((!defined($l1->[$i]) && !defined($l2->[$i]))
	     ||
	     (defined($l1->[$i]) && defined($l2->[$i]) && $l1->[$i] eq $l2->[$i]));
  }

  print "$label: ", ($rc ? "ok": "NOT ok"), "\n";
}


##--------------------------------------------------------------
## test: basic

sub test_basic {
  my ($file,$n) = @_;
  $file //= 'basic.dat';
  $n    //= 4;

  ##-- test: tie
  my (@a);
  tie(@a, 'Tie::File::Indexed', $file, mode=>'rwa') ##-- truncate
    or die("$0: tie failed for $file: $!");

  ##-- test: assign: batch: strings
  print STDERR "test: assign: batch: strings\n";
  my @want = map {"val$_"} (0..($n-1));
  @a = @want;
  isok("a[$_] eq $want[$_]", $a[$_] eq $want[$_]) foreach (0..$#want);

  ##-- test: append
  print STDERR "test: append\n";
  untie(@a);
  tie(@a, 'Tie::File::Indexed', $file, mode=>'rwa')
    or die("$0: append tie failed for $file: $!");
  push(@want,'appended');
  push(@a,   'appended');
  isok("a[$_] eq $want[$_]", $a[$_] eq $want[$_]) foreach (0..$#want);

  ##-- test: read-only
  print STDERR "test: read-only\n";
  untie(@a);
  tie(@a, 'Tie::File::Indexed', $file, mode=>'r')
    or die("$0: read-only tie failed for $file: $!");
  isok("a[$_] eq $want[$_]", $a[$_] eq $want[$_]) foreach (0..$#want);

  ##-- test: read-only: error (shown, but not catchable)
  #eval { $a[0] = 'foo'; };

  ##-- test: gaps
  print STDERR "test: gaps\n";
  untie(@a);
  tie(@a, 'Tie::File::Indexed', $file, mode=>'rw')
    or die("$0: re-tie failed for $file: $!");
  $a[8]  = 'days a week';
  $a[24] = 'hours to go';
  isok("#a == 24", $#a == 24);
  isok("a[8] eq days a week", $a[8] eq 'days a week');
  isok("a[24] eq hours to go", $a[24] eq 'hours to go');
  isok("a[7] eq ''", $a[7] eq '');

  ##-- test: overrwrite
  print STDERR "test: overwrite\n";
  untie(@a);
  tie(@a, 'Tie::File::Indexed', $file, mode=>'rw')
    or die("$0: re-tie failed for $file: $!");
  @a    = qw(foo bar baz);
  $a[1] = 'bonk';
  $a[0] = 'blip';
  @want = qw(blip bonk baz);
  isok("a[$_] eq $want[$_]", $a[$_] eq $want[$_]) foreach (0..$#want);
  isok("size($file)==17", (-s $file)==17);

  ##-- test: consolidate
  print STDERR "test: consolidate\n";
  isok("consolidate", tied(@a)->consolidate());
  tied(@a)->flush;
  isok("size($file)==11", (-s $file)==11);

  ##-- test: pop
  print STDERR "test: pop, shift\n";
  isok("pop(a) eq baz", pop(@a) eq 'baz');
  isok("#a == 1", $#a == 1);
  isok("size($file) == 8", (-s $file) == 8);
  isok("shift(a) eq blip", shift(@a) eq 'blip');
  isok("#a == 0", $#a == 0);

  ##-- test: splice
  print STDERR "test: splice: add\n";
  @a = @b = (0..3);
  splice(@b,1,0,qw(x y));
  splice(@a,1,0,qw(x y));
  isok("a[$_] eq $b[$_]", $#a==$#b && $a[$_] eq $b[$_]) foreach (0..$#b);
  ##
  print "test: splice (remove)\n";
  splice(@b,1,3,qw());
  splice(@a,1,3,qw());
  isok("a[$_] eq $b[$_]", $#a==$#b && $a[$_] eq $b[$_]) foreach (0..$#b);
  ##
  print "test: splice (add+remove)\n";
  splice(@b,1,1,qw(w v));
  splice(@a,1,1,qw(w v));
  isok("a[$_] eq $b[$_]", $#a==$#b && $a[$_] eq $b[$_]) foreach (0..$#b);

  ##-- test: utf8
  untie(@a);
  tie(@a, 'Tie::File::Indexed::Utf8', $file, mode=>'rw')
    or die("$0: re-tie via utf8 failed for $file: $!");
  @want = ("\x{f6}de", "Ha\x{364}u\x{17f}er", "\x{262e}\x{2665}\x{2615}", "\x{0372}\x{2107}\x{01a7}\x{a68c}");
  ##-- utf8 chars:
  # \x{2615}: coffee
  # \x{263a}: smiley
  # \x{26a0}: warning sign
  # \x{2672}: recycling sign
  ##
  #do { utf8::upgrade($_) if (!utf8::is_utf8($_)) } foreach (@want);
  @a = @want;
  isok("utf8::is_utf8(a[$_]) && a[$_] eq $want[$_]", utf8::is_utf8($a[$_]) && $a[$_] eq $want[$_]) foreach (0..$#want);

  ##-- test: json, storable, storableN
  foreach my $sub (qw(JSON Storable StorableN)) {
    my $class = "Tie::File::Indexed::$sub";
    print STDERR "test: subclass: $sub\n";
    untie(@a) if (tied(@a));
    tie(@a, $class, $file, mode=>'rw')
      or die("$0: re-tie via class $class failed for $file: $!");
    @want = map {{s=>"item$_",i=>$_}} (0..($n-1));
    @a = @want;
    isok("a[$_] ~ $want[$_]", tied(@a)->saveJsonString($a[$_]) eq tied(@a)->saveJsonString($want[$_])) foreach (0..$#want);
  }

  untie(@a) if (tied(@a));
  exit 0;
}
test_basic(@ARGV);


##--------------------------------------------------------------
## MAIN

sub main_dummy {
  foreach $i (1..3) {
    print "--dummy($i)--\n";
  }
}
main_dummy();

