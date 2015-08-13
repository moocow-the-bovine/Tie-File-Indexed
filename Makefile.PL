use ExtUtils::MakeMaker;

##----------------------------------------------------------------------
## MAIN
##----------------------------------------------------------------------
WriteMakefile
  (
   NAME		=> 'Tie::File::Indexed',
   AUTHOR       => 'Bryan Jurish <moocow@cpan.org>',
   ABSTRACT	=> 'fast tied array access to indexed data files',
   VERSION_FROM	=> 'Indexed.pm',
   LICENSE      => 'perl_5',

   ##-- install these
   #EXE_FILES => [glob("*.perl")],

   ##-- prerequisites
   #MIN_PERL_VERSION => '5.8.0', ##-- perl 5.6 chokes with "Can't declare another package's variables at t/01_ini.t line 22."
   PREREQ_PM    => {
		    #'Module' => $version,
		    'Tie::Array' => undef,
		    'JSON' => undef,
		    'Storable' => undef,
		   },
  );


#-----------------------------------------------------------------------
# Extensions
#-----------------------------------------------------------------------

##---------------------------------------------------------------
sub MY::constants {
  package MY;
  my $inherited = shift->SUPER::constants(@_);
  return $inherited;
}

##---------------------------------------------------------------
sub MY::depend {
  package MY;
  my $inherited = shift->SUPER::depend(@_);
  $inherited .= (
		 ###-- depends -> README.txt
		 "\n\n"
		 .join('',
		      map {
			"$_: README.txt\n\n"
		      } qw(dist create_distdir distdir_am distcheck))
		);
  return $inherited;
}

##---------------------------------------------------------------
sub MY::special_targets {
  package MY;
  my $inherited = shift->SUPER::special_targets(@_);
  $inherited .=
"
.SUFFIXES: .pm .pod .rpod .man .txt .html

.pm.html:
\tpod2html --css=\$(CSS) --infile=\$< --outfile=\$@

.pm.txt:
\tpod2text \$< \$@

.pod.html:
\tpod2html --css=\$(CSS) --infile=\$< --outfile=\$@

.pod.txt:
\tpod2text \$< \$@

.rpod.html:
\tpod2html --css=\$(CSS) --infile=\$< --outfile=\$@

.rpod.txt:
\tpod2text \$< \$@

";
  return $inherited;
}

##---------------------------------------------------------------
sub MY::postamble {
  package MY;
  my $inherited = shift->SUPER::postamble(@_);
  return $inherited;
}
