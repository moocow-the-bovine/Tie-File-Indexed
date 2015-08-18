# -*- Mode: CPerl -*-
# t/04_storable.t: test storable subclasses

$TEST_DIR = './t';
#use lib qw(../blib/lib ../blib/arch); $TEST_DIR = '.'; # for debugging

use Tie::File::Indexed::Storable;
use Tie::File::Indexed::StorableN;
use Tie::File::Indexed::Freeze;
use Tie::File::Indexed::FreezeN;

##-- load common subs
do "$TEST_DIR/common.plt"
  or die("could not load $TEST_DIR/common.plt");

##-- plan tests
plan(test => 20);

##-- common variables
my $file = "$TEST_DIR/test.dat";
my @w = (undef, \undef, \'string', \42, \24.7, {label=>'hash'}, [qw(a b c)], \{label=>'hash-ref'}, \[qw(d e f)]);

##-- 1+(4*5): json data
foreach my $sub (qw(Storable StorableN Freeze FreezeN)) {
  $Storable::canonical = 0;
  my $class = "Tie::File::Indexed::$sub";
  untie(@a) if (tied(@a));
  isok("$sub: tie", tie(@a, $class, $file, mode=>'rw'));
  @a = @w;
  isok("$sub: size", @a==@w);

  $Storable::canonical = 1;
  my @atmp = map {defined($_) ? Storable::freeze($_) : undef} @a;
  my @wtmp = map {defined($_) ? Storable::freeze($_) : undef} @w;
  listok("$sub: content", \@atmp,\@wtmp);

  my $gap = @a;
  $a[$gap+1] = \'post-gap';
  isok("$sub: gap ~ undef", !defined($a[$gap]));

  isok("$sub: unlink", tied(@a)->unlink);
}

# end of t/05_storable.t
