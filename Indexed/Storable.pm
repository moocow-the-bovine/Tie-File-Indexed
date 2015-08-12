##-*- Mode: CPerl -*-
##
## File: Tie/File/Indexed/Storable.pm
## Author: Bryan Jurish <moocow@cpan.org>
## Description: tied array access to indexed data files: Storable-encoded references (native byte-order)

package Tie::File::Indexed::Storable;
use Tie::File::Indexed;
use Storable;
use Fcntl qw(:DEFAULT :seek);
use strict;

##======================================================================
## Globals

our @ISA = qw(Tie::File::Indexed);

##======================================================================
## Subclass API: Data I/O: overrides

## $bool = $tfi->writeData($utf8_string)
##  + override transparently encodes data using Storable::store_fd()
sub writeData {
  return 1 if (!defined($_[1])); ##-- don't waste space on undef
  return Storable::store_fd($_[1]);
}

## $data_or_undef = $tfi->readData($offset,$length)
##  + override transparently decodes data using Storable::retrieve_fd()
sub readData {
  return undef if ($_[2]==0 || !CORE::seek($_[0]{datfh}, $_[1], SEEK_SET));
  return Storable::retrieve_fd($_[0]{datfh});
}


1; ##-- be happpy
