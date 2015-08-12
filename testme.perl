#!/usr/bin/perl -w
#-*- Mode: CPerl; coding: utf-8 -*-

use lib qw(.);
use Tie::File::Indexed;
use Tie::File::Indexed::Utf8;
use Tie::File::Indexed::JSON;
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
  $a[0]  = 'zero';
  $a[24] = 'hour party people';
  $a[42] = 'answer';

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

  ##-- test: utf8
  untie(@a);
  tie(@a, 'Tie::File::Indexed::Utf8', $file, mode=>'rw')
    or die("$0: re-tie via utf8 failed for $file: $!");
  @want = ("\x{f6}de", "Ha\x{364}u\x{17f}er");
  do { utf8::upgrade($_) if (!utf8::is_utf8($_)) } foreach (@want);
  @a = @want;
  isok("utf8::is_utf8(a[$_]) && a[$_] eq $want[$_]", utf8::is_utf8($a[$_]) && $a[$_] eq $want[$_]) foreach (0..$#want);

  ##-- test: json
  untie(@a);
  tie(@a, 'Tie::File::Indexed::JSON', $file, mode=>'rw')
    or die("$0: re-tie via json failed for $file: $!");
  @want = map {{s=>"item$_",i=>$_}} (0..($n-1));
  @a = @want;
  isok("a[$_] ~ $want[$_]", tied(@a)->saveJsonString($a[$_]) eq tied(@a)->saveJsonString($want[$_])) foreach (0..$#want);

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

