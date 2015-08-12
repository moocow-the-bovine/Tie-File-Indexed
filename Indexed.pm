##-*- Mode: CPerl -*-
##
## File: Tie/File/Indexed.pm
## Author: Bryan Jurish <moocow@cpan.org>
## Description: tied array access to indexed data files

package Tie::File::Indexed;
use Tie::Array;
use JSON qw();
use Fcntl qw(:DEFAULT :seek);
use IO::File;
use Carp qw(confess);
use strict;

##======================================================================
## Globals

our @ISA     = qw(Tie::Array);
our $VERSION = 0.01;

##======================================================================
## Constructors etc.

## $tfi = CLASS->new(%opts)
## $tfi = CLASS->new($file,%opts)
##  + %opts, object structure:
##    (
##     file   => $file,    ##-- file basename; uses files "${file}", "${file}.idx", "${file}.hdr"
##     mode   => $mode,    ##-- open mode (fcntl flags or perl-style; default='rwa')
##     perms  => $perms,   ##-- default: 0666 & ~umask
##     pack_o => $pack_o,  ##-- file offset pack template (default='N')
##     pack_l => $pack_l,  ##-- string-length pack template (default='N')
##     ##
##     ##-- pack lengths (after open())
##     len_o  => $len_o,   ##-- packsize($pack_o)
##     len_l  => $len_l,   ##-- packsize($pack_l)
##     len_ix => $len_ix,  ##-- packsize($pack_ix) == $len_o + $len_l
##     pack_ix=> $pack_ix, ##-- "${pack_o}${pack_l}"
##     ##
##     ##-- guts (after open())
##     idxfh => $idxfh,    ##-- $file.idx : [$i] => pack("${pack_o}${pack_l}",  $offset_in_datfh_of_item_i, $len_in_datfh_of_item_i)
##     datfh => $datfh,    ##-- $file     : raw data (concatenated)
##     size  => $nrecords, ##-- cached number of records for faster FETCHSIZE()
##    )
sub new {
  my $that = shift;
  my $file = (@_ % 2)==0 ? undef : shift;
  my %opts = @_;
  my $tfi = bless({
		   $that->defaults(),
		   file => $file,
		   @_,
		  }, ref($that)||$that);
  return $tfi->open() if (defined($tfi->{file}));
  return $tfi;
}

## %defaults = CLASS_OR_OBJECT->defaults()
##  + default attributes for constructor
sub defaults {
  return (
	  #file  => $file,
	  perms  => (0666 & ~umask),
	  mode   => 'rwa',
	  pack_o => 'N',
	  pack_l => 'N',
	 );
}

## undef = $tfi->DESTROY()
##  + implicitly calls close()
sub DESTROY {
  $_[0]->close();
}

##======================================================================
## Utilities

##--------------------------------------------------------------
## Utilities: fcntl

## $flags = CLASS_OR_OBJECT->fcflags($mode)
##  + returns Fcntl flags for symbolic string $mode
sub fcflags {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my $mode = shift;
  $mode //= 'r';
  return $mode if ($mode =~ /^[0-9]+$/); ##-- numeric mode is interpreted as Fcntl bitmask
  my $fread  = $mode =~ /[r<]/;
  my $fwrite = $mode =~ /[wa>\+]/;
  my $fappend = ($mode =~ /[a]/ || $mode =~ />>/);
  my $flags = ($fread
	       ? ($fwrite ? (O_RDWR|O_CREAT)   : O_RDONLY)
	       : ($fwrite ? (O_WRONLY|O_CREAT) : 0)
	      );
  $flags |= O_TRUNC  if ($fwrite && !$fappend);
  return $flags;
}

## $bool = CLASS_OR_OBJECT->fcread($mode)
##  + returns true if any read-bits are set for $mode
sub fcread {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my $flags = fcflags(shift);
  return ($flags&O_RDONLY)==O_RDONLY || ($flags&O_RDWR)==O_RDWR;
}

## $bool = CLASS_OR_OBJECT->fcwrite($mode)
##  + returns true if any write-bits are set for $mode
sub fcwrite {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my $flags = fcflags(shift);
  return ($flags&O_WRONLY)==O_WRONLY || ($flags&O_RDWR)==O_RDWR;
}

## $bool = CLASS_OR_OBJECT->fctrunc($mode)
##  + returns true if truncate-bits are set for $mode
sub fctrunc {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my $flags = fcflags(shift);
  return ($flags&O_TRUNC)==O_TRUNC;
}

## $bool = CLASS_OR_OBJECT->fccreat($mode)
sub fccreat {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my $flags = fcflags(shift);
  return ($flags&O_CREAT)==O_CREAT;
}

## $str = CLASS_OR_OBJECT->fcperl($mode)
##  + return perl mode-string for $mode
sub fcperl {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my $flags = fcflags(shift);
  return (fcread($flags)
	  ? (fcwrite($flags)    ##-- +read
	     ? (fctrunc($flags) ##-- +read,+write
		? '+>' : '+<')  ##-- +read,+write,+/-trunc
	     : '<')
	  : (fcwrite($flags)    ##-- -read
	     ? (fctrunc($flags) ##-- -read,+write
		? '>' : '>>')   ##-- -read,+write,+/-trunc
	     : '<')             ##-- -read,-write : default
	 );
}

## $fh_or_undef = CLASS_OR_OBJECT->fcopen($file,$mode)
## $fh_or_undef = CLASS_OR_OBJECT->fcopen($file,$mode,$perms)
##  + opens $file with fcntl- or perl-style mode $mode
sub fcopen {
  shift if (UNIVERSAL::isa($_[0],__PACKAGE__));
  my ($file,$flags,$perms) = @_;
  $flags    = fcflags($flags);
  $perms  //= (0666 & ~umask);
  my $mode = fcperl($flags);

  my ($sysfh);
  if (ref($file)) {
    ##-- dup an existing filehandle
    $sysfh = $file;
  }
  else {
    ##-- use sysopen() to honor O_CREAT and O_TRUNC
    sysopen($sysfh, $file, $flags, $perms) or return undef;
  }

  ##-- now open perl-fh from system fh
  open(my $fh, "${mode}&=", fileno($sysfh)) or return undef;
  if (fcwrite($flags) && !fctrunc($flags)) {
    ##-- append mode: seek to end of file
    seek($fh, 0, SEEK_END) or return undef;
  }
  return $fh;
}

##--------------------------------------------------------------
## Utilities: pack sizes

## $len = CLASS->packsize($packfmt)
## $len = CLASS->packsize($packfmt,@args)
##  + get pack-size for $packfmt with args @args
sub packsize {
  use bytes; ##-- deprecated in perl v5.18.2
  no warnings;
  return bytes::length(pack($_[0],@_[1..$#_]));
}


##--------------------------------------------------------------
## Utilities: JSON

## $data = CLASS->loadJsonString( $string,%opts)
## $data = CLASS->loadJsonString(\$string,%opts)
##  + %opts passed to JSON::from_json(), e.g. (relaxed=>0)
##  + supports $opts{json} = $json_obj
sub loadJsonString {
  my $that = UNIVERSAL::isa($_[0],__PACKAGE__) ? shift : __PACKAGE__;
  my $bufr = ref($_[0]) ? $_[0] : \$_[0];
  my %opts = @_[1..$#_];
  return $opts{json}->decode($$bufr) if ($opts{json});
  return JSON::from_json($$bufr, {utf8=>!utf8::is_utf8($$bufr), relaxed=>1, allow_nonref=>1, %opts});
}

## $data = CLASS->loadJsonFile($filename_or_handle,%opts)
sub loadJsonFile {
  my $that = UNIVERSAL::isa($_[0],__PACKAGE__) ? shift : __PACKAGE__;
  my $file = shift;
  my $fh = ref($file) ? $file : IO::File->new("<$file");
  return undef if (!$fh);
  binmode($fh,':raw');
  local $/=undef;
  my $buf = <$fh>;
  close($fh) if (!ref($file));
  return $that->loadJsonString(\$buf,@_);
}

## $str = CLASS->saveJsonString($data)
## $str = CLASS->saveJsonString($data,%opts)
##  + %opts passed to JSON::to_json(), e.g. (pretty=>0, canonical=>0)'
##  + supports $opts{json} = $json_obj
sub saveJsonString {
  my $that = UNIVERSAL::isa($_[0],__PACKAGE__) ? shift : __PACKAGE__;
  my $data = shift;
  my %opts = @_;
  return $opts{json}->encode($data)  if ($opts{json});
  return JSON::to_json($data, {utf8=>1, allow_nonref=>1, allow_unknown=>1, allow_blessed=>1, convert_blessed=>1, pretty=>1, canonical=>1, %opts});
}

## $bool = CLASS->saveJsonFile($data,$filename_or_handle,%opts)
sub saveJsonFile {
  my $that = UNIVERSAL::isa($_[0],__PACKAGE__) ? shift : __PACKAGE__;
  my $data = shift;
  my $file = shift;
  my $fh = ref($file) ? $file : IO::File->new(">$file");
  logconfess((ref($that)||$that)."::saveJsonFile() failed to open file '$file': $!") if (!$fh);
  binmode($fh,':raw');
  $fh->print($that->saveJsonString($data,@_)) or return undef;
  if (!ref($file)) { close($fh) || return undef; }
  return 1;
}

##======================================================================
## Subclass API: Data I/O

## $bool = $tfi->writeData($data)
##  + write item $data to $tfi->{datfh} at its current position
##  + after writing, $tfi->{datfh} should be positioned to the first byte following the written item
##  + $tfi is assumed to be opened in write-mode
##  + can be overridden by subclasses to perform transparent encoding of complex data
sub writeData {
  return $_[0]{datfh}->print($_[1]//'');
}

## $data_or_undef = $tfi->readData($offset,$length)
##  + read item data from $tfi->{datfh} from its current position
sub readData {
  CORE::seek($_[0]{datfh}, $_[1], SEEK_SET) or return undef;
  CORE::read($_[0]{datfh}, my $buf, $_[2])==$_[2] or return undef;
  return $buf;
}

##======================================================================
## Object API

##--------------------------------------------------------------
## Object API: header

## @keys = $tfi->headerKeys()
##  + keys to save as header
sub headerKeys {
  return grep {!ref($_[0]{$_}) && $_ !~ m{^(?:file|mode|perms)$}} keys %{$_[0]};
}

## \%header = $tfi->headerData()
##  + data to save as header
sub headerData {
  my $tfi = shift;
  return {(map {($_=>$tfi->{$_})} $tfi->headerKeys), class=>ref($tfi)};
}

## $tfi_or_undef = $tfi->loadHeader()
## $tfi_or_undef = $tfi->loadHeader($headerFile,%opts)
##  + loads header from "$tfi->{file}.hdr"
##  + %opts are passed to loadJsonFile()
sub loadHeader {
  my ($tfi,$hfile,%opts) = @_;
  $hfile //= $tfi->{file}.".hdr" if (defined($tfi->{file}));
  confess(ref($tfi)."::loadHeader(): no header-file specified and no 'file' attribute defined") if (!defined($hfile));
  my $hdata = $tfi->loadJsonFile($hfile,%opts)
    or confess(ref($tfi)."::loadHeader(): failed to load header data from '$hfile'");
  @$tfi{keys %$hdata} = values %$hdata;
  return $tfi;
}

## $tfi_or_undef = $tfi->saveHeader()
## $tfi_or_undef = $tfi->saveHeader($headerFile)
##  + saves header data to $headerFile
##  + %opts are passed to saveJsonFile()
sub saveHeader {
  my ($tfi,$hfile,%opts) = @_;
  $hfile //= $tfi->{file}.".hdr" if (defined($tfi->{file}));
  confess(ref($tfi)."::saveHeader(): no header-file specified and no 'file' attribute defined") if (!defined($hfile));
  return $tfi->saveJsonFile($tfi->headerData(), $hfile, %opts);
}

##--------------------------------------------------------------
## Object API: open/close

## $tfi_or_undef = $tfi->open($file,$mode)
## $tfi_or_undef = $tfi->open($file)
## $tfi_or_undef = $tfi->open()
##  + opens file(s)
sub open {
  my ($tfi,$file,$mode) = @_;
  $file //= $tfi->{file};
  $mode //= $tfi->{mode};
  $tfi->close() if ($tfi->opened);
  $tfi->{file} = $file;
  $tfi->{mode} = $mode = fcflags($mode);

  if (fcread($mode) && !fctrunc($mode)) {
    (!-e "$file.hdr" && fccreat($mode))
      or $tfi->loadHeader()
      or confess(ref($tfi)."::failed to load header from '$tfi->{file}.hdr': $!");
  }

  $tfi->{idxfh} = fcopen("$file.idx", $mode, $tfi->{perms})
    or confess(ref($tfi)."::open failed for index-file $file.idx: $!");
  $tfi->{datfh} = fcopen("$file", $mode, $tfi->{perms})
    or confess(ref($tfi)."::open failed for data-file $file: $!");
  binmode($_) foreach (@$tfi{qw(idxfh datfh)});

  ##-- pack lengths
  #use bytes; ##-- deprecated in perl v5.18.2
  $tfi->{len_o}   = packsize($tfi->{pack_o});
  $tfi->{len_l}   = packsize($tfi->{pack_l});
  $tfi->{len_ix}  = $tfi->{len_o} + $tfi->{len_l};
  $tfi->{pack_ix} = $tfi->{pack_o}.$tfi->{pack_l};

  return $tfi;
}

## $tfi_or_undef = $tfi->close()
##   + close any opened file, writes header if opened in write mode
sub close {
  my $tfi = shift;
  return $tfi if (!$tfi->opened);
  if ($tfi->opened && fcwrite($tfi->{mode})) {
    $tfi->saveHeader() or
      confess(ref($tfi)."::close(): failed to save header file");
  }
  delete @$tfi{qw(idxfh datfh)}; ##-- should auto-close if not shared
  undef $tfi->{file};
  return $tfi;
}

## $bool = $tfi->opened()
##  + returns true iff object is opened
sub opened {
  my $tfi = shift;
  return (ref($tfi)
	  && defined($tfi->{idxfh})
	  && defined($tfi->{datfh})
	 );
}

## $tfi_or_undef = $tfi->flush()
##  + attempts to flush underlying filehandles using IO::Handle::flush
##  + also writes header file
sub flush {
  return ($_[0]->opened
	  && $_[0]->saveHeaderFile()
	  && UNIVERSAL::can($_[0]->{idxfh},'flush') && $_[0]->{idxfh}->flush
	  && UNIVERSAL::can($_[0]->{datfh},'flush') && $_[0]->{datfh}->flush)
    ? $_[0]
    : undef;
}


##--------------------------------------------------------------
## Object API: consolidate

## $tfi_or_undef = $tfi->consolidate()
## $tfi_or_undef = $tfi->consolidate($tmpfile)
##  + consolidates file data: ensures data in $tfi->{datfh} are in index-order and contain no gaps or unused blocks
##  + object must be opened in write-mode
##  + uses $tmpfile as a temporary file for consolidation (default="$tfi->{file}.tmp")
sub consolidate {
  my ($tfi,$tmpfile) = @_;

  ##-- open tempfile
  $tmpfile //= "$tfi->{file}.tmp";
  my $tmpfh = fcopen($tmpfile, $tfi->{mode}, $tfi->{perms})
    or confess(ref($tfi)."::open failed for temporary data-file $tmpfile: $!");
  binmode($tmpfh);

  ##-- copy data
  my ($idxfh,$datfh,$len_ix,$pack_ix) = @$tfi{qw(idxfh datfh len_ix pack_ix)};
  my ($buf,$off,$len);
  my $size = $tfi->size;
  CORE::seek($idxfh, 0, SEEK_SET) or return undef;
  CORE::seek($tmpfh, 0, SEEK_SET) or return undef;
  for (my $i=0; $i < $size; ++$i) {
    CORE::read($idxfh, $buf, $len_ix)==$len_ix or return undef;
    ($off,$len) = unpack($pack_ix, $buf);

    ##-- update index record (in-place)
    CORE::seek($idxfh, $i*$len_ix, SEEK_SET) or return undef;
    $idxfh->print(pack($pack_ix, CORE::tell($tmpfh),$len)) or return undef;

    ##-- copy data record
    next if ($len == 0);
    CORE::seek($datfh, $off, SEEK_SET) or return undef;
    CORE::read($datfh, $buf, $len)==$len or return undef;
    $tmpfh->print($buf) or return undef;
  }

  ##-- swap data filehandle
  undef  $datfh;
  delete $tfi->{datfh};
  CORE::unlink($tfi->{file})
      or confess(ref($tfi)."::consolidate(): failed to unlink old data-file '$tfi->{file}': $!");
  CORE::rename($tmpfile, $tfi->{file})
      or confess(ref($tfi)."::consolidate(): failed to rename temp-file '$tmpfile' to '$tfi->{file}': $!");
  $tfi->{datfh} = $tmpfh;

  return $tfi;
}

##======================================================================
## API: Tied Array

##--------------------------------------------------------------
## API: Tied Array: mandatory methods

## $tied = tie(@array, $tieClass, $file,%opts)
## $tied = TIEARRAY($tieClass, $file,%opts)
BEGIN { *TIEARRAY = \&new; }

## $count = $tied->FETCHSIZE()
##  + like scalar(@array)
##  + may cache $tied->{size}
BEGIN { *size = \&FETCHSIZE; }
sub FETCHSIZE {
  return undef if (!$_[0]{idxfh});
  return $_[0]{size} //= ((-s $_[0]{idxfh}) / $_[0]{len_ix});
}

## $val = $tied->FETCH($index)
## $val = $tied->FETCH($index)
sub FETCH {
  my ($tfi,$i) = @_;
  return undef if ($i >= $tfi->size);

  ##-- get (offset,length)
  my ($buf);
  CORE::seek($tfi->{idxfh}, $i*$tfi->{len_ix}, SEEK_SET) or return undef;
  CORE::read($tfi->{idxfh}, $buf, $tfi->{len_ix})==$tfi->{len_ix} or return undef;
  my ($off,$len) = unpack($tfi->{pack_ix}, $buf);

  ##-- get data
  return $tfi->readData($off,$len);
}

## $val = $tied->STORE($index,$val)
##  + no consistency checking or optimization; just appends a new record to the end of $datfh and updates $idxfh
sub STORE {
  my $tfi = shift;

  ##-- append encoded record to $datfh
  CORE::seek($tfi->{datfh}, 0, SEEK_END) or return undef;
  my $off0 = CORE::tell($tfi->{datfh});
  $tfi->writeData($_[1]) or return undef;
  my $off1 = CORE::tell($tfi->{datfh});

  ##-- update index record in $idxfh
  CORE::seek($tfi->{idxfh}, $_[0]*$tfi->{len_ix}, SEEK_SET) or return undef;
  $tfi->{idxfh}->print(pack($tfi->{pack_ix}, $off0, ($off1-$off0))) or return undef;

  ##-- mybe update {size}
  $tfi->{size} = $_[0]+1 if ($_[0] >= ($tfi->{size}//0));

  ##-- return
  return $_[1];
}

## $count = $tied->STORESIZE($count)
sub STORESIZE {
  if ($_[1] < $_[0]->size) {
    ##-- shrink
    CORE::truncate($_[0]{idxfh}, $_[1]*$_[0]{len_ix}) or return undef;
  } elsif ($_[1] > $_[0]->size) {
    ##-- grow (idxfh only)
    CORE::seek($_[0]{idxfh}, $_[1]*$_[0]{len_ix}-1, SEEK_SET) or return undef;
    $_[0]{idxfh}->print("\0");
  }
  $_[0]{size} = $_[1];
  return $_[1];
}

## $bool = $tied->EXISTS($index)
sub EXISTS {
  return $_[1] < $_[0]->size;
}

## undef = $tied->DELETE($index)
##  + really just wraps $tied->STORE($index,undef)
sub DELETE {
  return $_[0]->STORE($_[1],undef);
}

##--------------------------------------------------------------
## API: Tied Array: optional methods

## undef = $tied->CLEAR()
sub CLEAR {
  CORE::truncate($_[0]{idxfh}, 0) or return undef;
  CORE::truncate($_[0]{datfh}, 0) or return undef;
  $_[0]{size} = 0;
  return $_[0];
}

## @vals = $tied->PUSH(@vals)
## $val = $tied->POP()
## $val = $tied->SHIFT()
## @vals = $tied->UNSHIFT(@vals)
## @newvals = $tied->SPLICE($offset, $length, @newvals)
## ? = $tied->EXTEND($newcount)


1; ##-- be happpy
