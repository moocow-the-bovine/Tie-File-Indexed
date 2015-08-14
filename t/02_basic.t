# -*- Mode: CPerl -*-
# t/02_basic.t; test basic functionality

$TEST_DIR = './t';
#use lib qw(../blib/lib ../blib/arch); $TEST_DIR = '.'; # for debugging

use Tie::File::Indexed;

##-- load common subs
do "$TEST_DIR/common.plt"
  or die("could not load $TEST_DIR/common.plt");

##-- plan tests
plan(test => 39);

##-- common variables
my $file = "$TEST_DIR/test.dat";
my $n    = 4; ##-- number of elements
my (@a,@w,$w);

##-- 1+1: tie (truncate)
isok("tie: rw", tie(@a, 'Tie::File::Indexed', $file, mode=>'rw') );

##-- 2+1: batch-store & fetch
@a = @w = map {"val$_"} (0..($n-1));
listok("assign: content", \@a,\@w);

##-- 3+4: append
isok("append: untie", untie(@a));
isok("append: tie: rwa", tie(@a, 'Tie::File::Indexed', $file, mode=>'rwa'));
isok("append: push", push(@a,'appended'), push(@w,'appended'));
listok("append: content", \@a,\@w);

##-- 7+3: read-only
untie(@a);
isok("read-only: untie", untie(@a));
isok("read-only: tie", tie(@a, 'Tie::File::Indexed', $file, mode=>'r'));
listok("read-only: content", \@a,\@w);

##-- 10+4: index-gaps
untie(@a);
tie(@a, 'Tie::File::Indexed', $file, mode=>'rw');
$a[8]  = 'days a week';
$a[24] = 'hours to go';
isok("gaps: \$#a == 24", $#a == 24);
isok("gaps: \$a[8] eq 'days a week'", $a[8] eq 'days a week');
isok("gaps: \$a[24] eq 'hours to go'", $a[24] eq 'hours to go');
isok("gaps: \$a[7] eq ''", $a[7] eq '');

##-- 14+1: overwrite
untie(@a);
tie(@a, 'Tie::File::Indexed', $file, mode=>'rw');
@a = qw(foo bar baz);
$a[1] = 'bonk';
$a[0] = 'blip';
@w    = qw(blip bonk baz);
listok("overwrite: content", \@a,\@w);

##-- 15+4: consolidate
isok("consolidate", tied(@a)->consolidate());
isok("consolidate: flush", tied(@a)->flush);
isok("consolidate: file-size", (-s $file)==11);
isok("consolidate: content", \@a,\@w);

##-- 19+4: pop
isok("pop", pop(@a) eq pop(@w));
isok("post-pop: size", @a == 2);
isok("post-pop: file-size", (-s $file) == 8);
listok("post-pop: content", \@a,\@w);

##-- 23+3: shift
isok("shift", shift(@a) eq shift(@w));
isok("post-shift: size", @a == 1);
isok("post-shift: content", \@a,\@w);

##-- 26+6: splice
@a = @w = (0..3);
listok("splice: add", [splice(@a,1,0,qw(x y))], [splice(@w,1,0,qw(x y))]);
listok("splice: add: content", \@a,\@w);

listok("splice: remove", [splice(@a,1,3)], [splice(@w,1,3)]);
listok("splice: remove: content", \@a,\@w);

listok("slice: add+remove", [splice(@a,1,1,qw(w v))], [splice(@w,1,1,qw(w v))]);
listok("slice: add+remove: content", \@a,\@w);

##-- 32+4: unlink
isok("unlink",  tied(@a)->unlink);
isok("unlink2: undef", !defined(tied(@a)->unlink));
isok("unlink: files", !grep {-e "${file}$_"} ('','.idx','.hdr'));
isok("unlink: untie", untie(@a));

##-- 36+4: temp
isok("temp: tie: rw", tie(@a, 'Tie::File::Indexed', $file, mode=>'rw', temp=>1) );
isok("temp: tie: files", !grep {!-e "${file}$_"} ('','.idx','.hdr'));
isok("temp: untie", untie(@a));
isok("temp: untie: files", !grep {-e "${file}$_"} ('','.idx','.hdr'));

# end of t/02_basic.t
