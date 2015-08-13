# -*- Mode: CPerl -*-
# t/03_utf8.t: test utf8 subclass

$TEST_DIR = './t';
#use lib qw(../blib/lib ../blib/arch); $TEST_DIR = '.'; # for debugging

use Tie::File::Indexed::Utf8;

##-- load common subs
do "$TEST_DIR/common.plt"
  or die("could not load $TEST_DIR/common.plt");

##-- plan tests
plan(test => 4);

##-- common variables
my $file = "$TEST_DIR/test.dat";
my @u = ("\x{f6}de", "Ha\x{364}u\x{17f}er", "\x{262e}\x{2665}\x{2615}", "\x{0372}\x{2107}\x{01a7}\x{a68c}");

##-- 1+3: utf8 data
isok("utf8: tie", tie(my @a, 'Tie::File::Indexed::Utf8', $file, mode=>'rw') );
@a = @u;
isok("utf8: size", @a==@u);
listok("utf8: content", \@a,\@u);

##-- 4+1: unlink
isok("utf8: unlink", tied(@a)->unlink);

# end of t/03_utf8.t
