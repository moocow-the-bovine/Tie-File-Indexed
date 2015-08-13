# -*- Mode: CPerl -*-
# t/04_json.t: test json subclass

$TEST_DIR = './t';
#use lib qw(../blib/lib ../blib/arch); $TEST_DIR = '.'; # for debugging

use Tie::File::Indexed::JSON;

##-- load common subs
do "$TEST_DIR/common.plt"
  or die("could not load $TEST_DIR/common.plt");

##-- plan tests
plan(test => 5);

##-- common variables
my $file = "$TEST_DIR/test.dat";
my @w = (undef, 'string', 42, 24.7, {label=>'hash'}, [qw(a b c)]);

##-- 1+3: json data
isok("json: tie", tie(my @a, 'Tie::File::Indexed::JSON', $file, mode=>'rw') );
@a = @w;
isok("json: size", @a==@w);
my @atmp = map {tied(@a)->saveJsonString($_)} @a;
my @wtmp = map {tied(@a)->saveJsonString($_)} @w;
listok("json: content", \@atmp,\@wtmp);

##-- 4+1: gaps -> undef
my $gap = @a;
$a[$gap+1] = 'post-gap';
isok("json: gap ~ undef", !defined($a[$gap]));

##-- 5+1: unlink
isok("json: unlink", tied(@a)->unlink);

# end of t/04_json.t
