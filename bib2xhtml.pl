#!/usr/bin/perl -w
# -*- perl -*-
# vim: syntax=perl
eval 'exec /usr/bin/perl -w -S $0 ${1+"$@"}'
    if 0;

$version = '@VERSION@';

#
# Convert from bibtex to XHTML.
#
# (C) Copyright 1995, 1996 David Hull.
# (David Hull / hull@cs.uiuc.edu / http://www.uiuc.edu/ph/www/dlhull)
#
# (C) Copyright 2002-2010 Diomidis Spinellis
# http://www.spinellis.gr
#
# This program is free software.  You can redistribute it and/or modify
# it under the terms of the GNU General Public License.  See the
# files README and COPYING for details.
#
# This source code contains UTF-8 characters.  You might want to use
# an appropriate editor, if you want to view/modify the LaTeX to Unicode
# substitution commands.
#

use Getopt::Std;
use open IO => ':crlf';

eval "use PDF::API2";
$have_pdf_api = 1 unless (defined $@ && $@ ne '');

# Label styles.
$label_styles{'plain'} = 	$LABEL_PLAIN = 		1;
$label_styles{'numbered'} = 	$LABEL_NUMBERED = 	2;
$label_styles{'default'} = 	$LABEL_DEFAULT = 	3;
$label_styles{'paragraph'} = 	$LABEL_PARAGRAPH = 	4;

$list_start[$LABEL_PLAIN] = 'ul class="bib2xhtml"';
$list_end[$LABEL_PLAIN] = "/ul";
$list_start[$LABEL_NUMBERED] = 'dl class="bib2xhtml"';
$list_end[$LABEL_NUMBERED] = "/dl";
$list_start[$LABEL_DEFAULT] = 'dl class="bib2xhtml"';
$list_end[$LABEL_DEFAULT] = "/dl";
$list_start[$LABEL_PARAGRAPH] = 'div class="bib2xhtml"';
$list_end[$LABEL_PARAGRAPH] = "/div";

@tmpfiles = ();

sub usage {
    $program = $0;
    $program =~ s+^.*/++;
    print STDERR <<_EOF_;
usage: $program [-a] [-b bibtex-options] [-B bibtex-executable]
                [-c] [-d delim] [-D mappings]
                [-e extended-information] [-h heading] [-i] [-k]
		[-m macro file] [-n name] [-r] [-R] [-s style] [-t] [-u] [-v]
		sourcefile [htmlfile]

    -a  Write abstract to htmlfile.
    -b bibtex-options
	Options to pass to bibtex.
    -B bibtex executable name.
    -c Sort chronologically, by year, month, day, and then by author.
    -d delim
	Specify bibliography delimiter.
    -D mappings
	Specify file path to URL mappings.
    -e extended-information
	Specify the extended metadata information (page count, size, PDF icon)
	that will be included in each citation.
    -h heading
	String to use instead of default title when creating a new htmlfile.
	If updating an existing htmlfile, this option is ignored.
    -i Use included citations
    -k In labeled styles append to the label of each entry its BibTeX key.
    -m macro file
	Specify an additional macro file.
    -n name
	Highlight the specified author name in the output.
    -r Sort in reverse chronological order.
    -R Reference numbers increase from bottom to top, not from top to bottom.
    -s style
	Control style of bibliography:
	(empty, plain, alpha, named, paragraph, unsort, or unsortlist).
    -t  Write timestamp to htmlfile.
    -u  Output a Unicode-coded document.
    -v  Report the version number.
_EOF_
    exit(1);
}

# Return the command needed to open a (perhaps compressed) file,
# as well as the type of compression.
sub openCommand {
    local($path) = @_;
    local($cmd);
    local($cmp);

command: {
	($path =~ m/\.Z$/ &&
	  ($cmd = "uncompress -c $path |", $cmp = "Compressed", last command));
	($path =~ m/\.g?z$/ &&
	  ($cmd = "gzip -d -c $path |", $cmp = "Gzipped", last command));
	($cmd = "<$path", $cmp = "", last command);
    }

    ($cmd, $cmp);
}

@paperTypes = ("PostScript", "PDF", "DVI", "DOI", "DJVU");

sub DJVUPageCount {
    return undef;
    # could be implemented later but it is not crucial...
}

sub PostScriptPageCount {
    local($cmd) = @_;
    local($pageCount);

    #print "in PostScriptPageCount $cmd\n";

    open(FILE, $cmd) || (warn "error opening $cmd: $!\n", return undef);

    local($_);
    local($/) = "\n";

line:
    while (<FILE>) {
	last line if m/^%%EndComments/;
	if (m/^%%Pages:\s*(\d+)/) {
	    $pageCount = $1 if ($1 > 0);
	    last line;
	}
    }
    close(FILE);

    $pageCount;
}

sub PDFPageCount {
    return undef unless ($have_pdf_api);
    my($file) = @_;
    $file =~ s/^\<//;
    # print "in PDFPageCount $file\n";
    my($pdf);
    eval {$pdf = PDF::API2->open($file)};
    return undef if (defined $@ && $@ ne '');
    return $pdf->pages;
}

sub DVIPageCount {
    local($cmd) = @_;
    local($pageCount);

    #print "in DVIPageCount $cmd\n";

    if ($cmd =~ m/^</) {
	# Simple file.
	$cmd = "dviselect : $cmd >/dev/null";
    } else {
	# Compressed file.
	$cmd .= "dviselect : >/dev/null";
    }

    # Look at dviselect's stderr.
    open(DVISELECT, "-|") || (open(STDERR, ">&STDOUT"), exec $cmd);

    local($_);
    local($/) = "\n";
line:
    while (<DVISELECT>) {
	if (m/[Ww]rote (\d+) pages/) {
	    $pageCount = $1;
	    last line;
	}
    }
    close(DVISELECT);

    $pageCount;
}

# Make an intelligent link to a paper file.
sub doPaperLinks {
    local($file);
    local($url);
    local($paper, $ppaper);
    local($cstr, $pstr, $sstr);

papertype:
    foreach $paper (@paperTypes) {

	$ppaper = $paper unless defined($notype);	# Paper type
	$sstr = "";					# size string
	$pstr = "";					# pages string
	$cstr = "";					# compression type string

	if (($url) = m/\<\!\-\- $paper:[\s\n]+(\S+)[\s\n]+\-\-\>/) {

	    # If $url looks like a file (doesn't begin with http://, ftp://, 
	    # etc.), get more info.
	    if ($paper ne 'DOI' && $url !~ m/^[^\:\/]+\:\//) {
		local($file) = $url;
		local($path);
		local($dir);
		foreach $dir (@filedir) {
		    $path = join('/', $dir, $file);
		    if ( -f $path) {
			if (defined $dirmap{$dir}) {
			    $url = join('/', $dirmap{$dir}, $file);
			} else {
			    $url = $path;
			}
			last;
		    }
		}

		if (! -f $path) {
		    print STDERR "couldn't find $file\n";
		    next papertype;
		}

		local($opencmd);
		local($size);
		local($pageCountRoutine);
		local($pageCount) = 0;

		($opencmd, $cstr) = &openCommand($path);

		# Get size.
		$size = -s _;
		$sstr = ", $size bytes" unless(defined($nosize));

		# Get page count.
		$pageCountRoutine = $paper . "PageCount";
		$pageCount = &$pageCountRoutine($opencmd);
		$pstr = ", $pageCount pages" if (defined $pageCount && !defined $nopages);

		# Get compression type.
		$cstr = "$cstr " if ($cstr ne "");
		undef $cstr if (defined $nocompression);
	    } elsif ($paper eq 'DOI' &&
	             (($url =~ m/^doi:(.*)/i) ||
	              ($url =~ m/^http:\/\/[\w.]+\/(.*)/i) ||
	              ($url =~ m/^(.*)$/))) {
			# Convert the DOI URL into an HTTP link
			$url = html_encode("http://dx.doi.org/$1");
			$ppaper = "doi:" . html_encode($1) unless (defined($nodoi));
	    }

	    $ppaper = $typeicon{$paper} if (defined $typeicon{$paper});

	    #print STDERR "found $paper $file$pstr$sstr\n";

	    if ($nobrackets) {
	        s/\<\!\-\- $paper:[\s\n]+\S+[\s\n]+\-\-\>/<a href=\"$url\">${cstr}$ppaper<\/a>$pstr$sstr/;
	    } else {
		s/\<\!\-\- $paper:[\s\n]+\S+[\s\n]+\-\-\>/(<a href=\"$url\">${cstr}$ppaper<\/a>$pstr$sstr)/;
	    }
	}
    }
}

# highlight_name(string)
# Return name with Highlighted name if it was passed in as an option from the command line.
#
sub highlight_name {
    local($name) = @_;
    if (defined($highlighted_name) && $name =~ /$highlighted_name/) {
        return "<strong>$name</strong>";
    } else {
        return $name;
    }
}

# html_encode(string)
#   Protect character entities in string.
sub html_encode {
    local($_) = @_;

    s/&/&amp;/g;        # Must be first.
    s/</&lt;/g;
    s/>/&gt;/g;
    s/"/&quot;/g;

    $_;
}

# Convert $_ into an HTML entity representation
sub html_ent {
	# Accents.
	s/\\i\b/i/g;					# dotless i.
	s/\\\'(\001\d+)\{([AEIOUaeiou])\1\}/&$2acute;/gs;	# acute accent \'{x}
	s/\\\'([AEIOUaeiou])/&$1acute;/g;			# acute accent \'x
	s/\\\`(\001\d+)\{([AEIOUaeiou])\1\}/&$2grave;/gs;	# grave accent \`{x}
	s/\\\`([AEIOUaeiou])/&$1grave;/g;			# grave accent \`x
	s/\\\"(\001\d+)\{([AEIOUaeiouy])\1\}/&$2uml;/gs;	# umlaut \"{x}
	s/\\\"([AEIOUaeiouy])/&$1uml;/g;			# umlaut \"x
	s/\\\~(\001\d+)\{([ANOano])\1\}/&$2tilde;/gs;	# tilde \~{x}
	s/\\\~([ANOano])/&$1tilde;/g;			# tilde \~x
	s/\\\^(\001\d+)\{([AEIOUaeiou])\1\}/&$2circ;/gs;	# circumflex \^{x}
	s/\\\^([AEIOUaeiou])/&$1circ;/g;		# circumflex \^x
	s/\\c(\001\d+)\{([Cc])\1\}/&$2cedil;/gs;		# cedilla \c{x}
	# The following accents have no HTML equivalent.
	# (This list is still not complete.)
	s/\\u(\001\d+)\{(.)\1\}/$2/gs;			# breve accent \u{x}
	s/\\v(\001\d+)\{(.)\1\}/$2/gs;			# hacek accent \v{x}
	s/\\([lL])\b/$1/g;					# slashed l
	s/\\\=(\001\d+)\{(.)\1\}/$2/gs;			# macron \={x}
	s/\\\=(.)/$1/g;					# macron accent \=x
	s/\\\.(\001\d+)\{(.)\1\}/$2/gs;			# dot \.{x}
	s/\\\.(.)/$1/g;					# dot accent \.x

	# Other special characters.
	s/\\([Oo])\b\s*/&$1slash;/g;	# \[Oo] -> &[Oo]slash;
	s/\\AA\b\s*/&Aring;/g;		# \AA -> &Aring;
	s/\\aa\b\s*/&aring;/g;		# \aa -> &aring;
	s/\\AE\b\s*/&AElig;/g;		# \AE -> &AElig;
	s/\\ae\b\s*/&aelig;/g;		# \ae -> &aelig;
	s/\\ss\b\s*/&szlig;/g;		# \ss -> &szlig;
	s/\\S\b\s*/&sect;/g;		# \S -> &sect;
	s/\\P\b\s*/&para;/g;		# \P -> &para;
	s/\\pounds\b\s*/&pound;/g;	# \pounds -> &pound;
	s/\?\`/&iquest;/g;		# ?` -> &iquest;
	s/\!\`/&iexcl;/g;		# !` -> &iexcl;

	# Other special characters.
	# Try to be careful to not change the dashes in HTML comments
	# (<!-- comment -->) to &ndash;s.
	s/\-\-\-/&mdash;/g;		# --- -> &mdash;
	s/([^\!])\-\-([^\>])/$1&ndash;$2/g;	# -- -> &ndash;
	#s/\-\-\-/\227/g;		# --- -> &mdash;
	#s/([^\!])\-\-([^\>])/$1\226$2/g;	# -- -> &ndash;

	# Upper and lower case greek
	s/\\([aA]lpha)\b/&$1;/g;
	s/\\([bB]eta)\b/&$1;/g;
	s/\\([gG]amma)\b/&$1;/g;
	s/\\([dD]elta)\b/&$1;/g;
	s/\\varepsilon\b/&epsilon;/g;
	s/\\([eE]psilon)\b/&$1;/g;
	s/\\([zZ]eta)\b/&$1;/g;
	s/\\([eE]ta)\b/&$1;/g;
	s/\\([tT]heta)\b/&$1;/g;
	s/\\vartheta\b/&theta;/g;
	s/\\([iI]ota)\b/&$1;/g;
	s/\\([kK]appa)\b/&$1;/g;
	s/\\([lL]ambda)\b/&$1;/g;
	s/\\([mM]u)\b/&$1;/g;
	s/\\([nN]u)\b/&$1;/g;
	s/\\([xX]i)\b/&$1;/g;
	s/\\([oO]micron)\b/&$1;/g;
	s/\\([pP]i)\b/&$1;/g;
	s/\\varpi\b/&pi;/g;
	s/\\([rR]ho)\b/&$1;/g;
	s/\\varrho\b/&rho;/g;
	s/\\([sS]igma)\b/&$1;/g;
	s/\\varsigma\b/&sigmaf;/g;
	s/\\([tT]au)\b/&$1;/g;
	s/\\([uU]psilon)\b/&$1;/g;
	s/\\([pP]hi)\b/&$1;/g;
	s/\\varphi\b/&phi;/g;
	s/\\([cC]hi)\b/&$1;/g;
	s/\\([pP]si)\b/&$1;/g;
	s/\\([oO]mega)\b/&$1;/g;
}

# Convert $_ into a UTF-8 character
sub utf_ent {
	# Accents.
	s/\\i\b/ı/g;					# dotless i.

	# acute accent \'{x}
	s/\\\'(\001\d+)\{A\1\}/Á/gs;
	s/\\\'(\001\d+)\{C\1\}/Ć/gs;
	s/\\\'(\001\d+)\{E\1\}/É/gs;
	s/\\\'(\001\d+)\{I\1\}/Í/gs;
	s/\\\'(\001\d+)\{L\1\}/Ĺ/gs;
	s/\\\'(\001\d+)\{N\1\}/Ń/gs;
	s/\\\'(\001\d+)\{O\1\}/Ó/gs;
	s/\\\'(\001\d+)\{R\1\}/Ŕ/gs;
	s/\\\'(\001\d+)\{S\1\}/Ś/gs;
	s/\\\'(\001\d+)\{U\1\}/Ú/gs;
	s/\\\'(\001\d+)\{Y\1\}/Ý/gs;
	s/\\\'(\001\d+)\{Z\1\}/Ź/gs;
	s/\\\'(\001\d+)\{a\1\}/á/gs;
	s/\\\'(\001\d+)\{c\1\}/ć/gs;
	s/\\\'(\001\d+)\{e\1\}/é/gs;
	s/\\\'(\001\d+)\{ı\1\}/í/gs;
	s/\\\'(\001\d+)\{i\1\}/í/gs;
	s/\\\'(\001\d+)\{l\1\}/ĺ/gs;
	s/\\\'(\001\d+)\{n\1\}/ń/gs;
	s/\\\'(\001\d+)\{o\1\}/ó/gs;
	s/\\\'(\001\d+)\{r\1\}/ŕ/gs;
	s/\\\'(\001\d+)\{s\1\}/ś/gs;
	s/\\\'(\001\d+)\{u\1\}/ú/gs;
	s/\\\'(\001\d+)\{y\1\}/ý/gs;
	s/\\\'(\001\d+)\{z\1\}/ź/gs;

	# acute accent \'x
	s/\\\'A/Á/g;
	s/\\\'C/Ć/g;
	s/\\\'E/É/g;
	s/\\\'I/Í/g;
	s/\\\'L/Ĺ/g;
	s/\\\'N/Ń/g;
	s/\\\'O/Ó/g;
	s/\\\'R/Ŕ/g;
	s/\\\'S/Ś/g;
	s/\\\'U/Ù/g;
	s/\\\'Y/Ý/g;
	s/\\\'Z/Ź/g;
	s/\\\'a/á/g;
	s/\\\'c/ć/g;
	s/\\\'e/é/g;
	s/\\\'i/í/g;
	s/\\\'ı/í/g;
	s/\\\'l/ĺ/g;
	s/\\\'n/ń/g;
	s/\\\'o/ó/g;
	s/\\\'r/ŕ/g;
	s/\\\'s/ś/g;
	s/\\\'u/ú/g;
	s/\\\'y/ý/g;
	s/\\\'z/ź/g;

	# grave accent \`{x}
	s/\\\`(\001\d+)\{A\1\}/À/gs;
	s/\\\`(\001\d+)\{E\1\}/È/gs;
	s/\\\`(\001\d+)\{I\1\}/Ì/gs;
	s/\\\`(\001\d+)\{O\1\}/Ò/gs;
	s/\\\`(\001\d+)\{U\1\}/Ù/gs;
	s/\\\`(\001\d+)\{a\1\}/à/gs;
	s/\\\`(\001\d+)\{e\1\}/è/gs;
	s/\\\`(\001\d+)\{i\1\}/ì/gs;
	s/\\\`(\001\d+)\{o\1\}/ò/gs;
	s/\\\`(\001\d+)\{u\1\}/ù/gs;

	# grave accent \`x
	s/\\\`A/À/g;
	s/\\\`E/È/g;
	s/\\\`I/Ì/g;
	s/\\\`O/Ò/g;
	s/\\\`U/Ù/g;
	s/\\\`a/à/g;
	s/\\\`e/è/g;
	s/\\\`i/ì/g;
	s/\\\`o/ò/g;
	s/\\\`u/ù/g;

	# umlaut \"{x}
	s/\\\"(\001\d+)\{A\1\}/Ä/gs;
	s/\\\"(\001\d+)\{E\1\}/Ë/gs;
	s/\\\"(\001\d+)\{I\1\}/Ï/gs;
	s/\\\"(\001\d+)\{O\1\}/Ö/gs;
	s/\\\"(\001\d+)\{U\1\}/Ü/gs;
	s/\\\"(\001\d+)\{Y\1\}/Ÿ/gs;
	s/\\\"(\001\d+)\{a\1\}/ä/gs;
	s/\\\"(\001\d+)\{e\1\}/ë/gs;
	s/\\\"(\001\d+)\{i\1\}/ï/gs;
	s/\\\"(\001\d+)\{o\1\}/ö/gs;
	s/\\\"(\001\d+)\{u\1\}/ü/gs;
	s/\\\"(\001\d+)\{y\1\}/ÿ/gs;

	# umlaut \"x
	s/\\\"A/Ä/g;
	s/\\\"E/Ë/g;
	s/\\\"I/Ï/g;
	s/\\\"O/Ö/g;
	s/\\\"U/Ü/g;
	s/\\\"Y/Ÿ/g;
	s/\\\"a/ä/g;
	s/\\\"e/ë/g;
	s/\\\"i/ï/g;
	s/\\\"o/ö/g;
	s/\\\"u/ü/g;
	s/\\\"y/ÿ/g;

	# tilde \~{x}
	s/\\\~(\001\d+)\{A\1\}/Ã/gs;
	s/\\\~(\001\d+)\{N\1\}/Ñ/gs;
	s/\\\~(\001\d+)\{O\1\}/Õ/gs;
	s/\\\~(\001\d+)\{a\1\}/ã/gs;
	s/\\\~(\001\d+)\{n\1\}/ñ/gs;
	s/\\\~(\001\d+)\{o\1\}/õ/gs;

	# tilde \~x
	s/\\\~A/Ã/g;
	s/\\\~N/Ñ/g;
	s/\\\~O/Õ/g;
	s/\\\~a/ã/g;
	s/\\\~n/ñ/g;
	s/\\\~O/õ/g;

	# circumflex \^{x}
	s/\\\^(\001\d+)\{A\1\}/Â/gs;
	s/\\\^(\001\d+)\{E\1\}/Ê/gs;
	s/\\\^(\001\d+)\{G\1\}/Ĝ/gs;
	s/\\\^(\001\d+)\{H\1\}/Ĥ/gs;
	s/\\\^(\001\d+)\{I\1\}/Î/gs;
	s/\\\^(\001\d+)\{J\1\}/Ĵ/gs;
	s/\\\^(\001\d+)\{O\1\}/Ô/gs;
	s/\\\^(\001\d+)\{U\1\}/Û/gs;
	s/\\\^(\001\d+)\{W\1\}/Ŵ/gs;
	s/\\\^(\001\d+)\{Y\1\}/Ŷ/gs;
	s/\\\^(\001\d+)\{a\1\}/â/gs;
	s/\\\^(\001\d+)\{e\1\}/ê/gs;
	s/\\\^(\001\d+)\{g\1\}/ĝ/gs;
	s/\\\^(\001\d+)\{h\1\}/ĥ/gs;
	s/\\\^(\001\d+)\{i\1\}/î/gs;
	s/\\\^(\001\d+)\{j\1\}/ĵ/gs;
	s/\\\^(\001\d+)\{o\1\}/ô/gs;
	s/\\\^(\001\d+)\{u\1\}/û/gs;
	s/\\\^(\001\d+)\{w\1\}/ŵ/gs;
	s/\\\^(\001\d+)\{y\1\}/ŷ/gs;

	# circumflex \^x
	s/\\\^A/Â/g;
	s/\\\^E/Ê/g;
	s/\\\^G/Ĝ/g;
	s/\\\^H/Ĥ/g;
	s/\\\^I/Î/g;
	s/\\\^J/Ĵ/g;
	s/\\\^O/Ô/g;
	s/\\\^U/Û/g;
	s/\\\^W/Ŵ/g;
	s/\\\^Y/Ŷ/g;
	s/\\\^a/â/g;
	s/\\\^e/ê/g;
	s/\\\^g/ĝ/g;
	s/\\\^h/ĥ/g;
	s/\\\^i/î/g;
	s/\\\^J/ĵ/g;
	s/\\\^o/ô/g;
	s/\\\^u/û/g;
	s/\\\^w/ŵ/g;
	s/\\\^y/ŷ/g;

	# cedilla \c{x}
	s/\\c(\001\d+)\{C\1\}/Ç/gs;
	s/\\c(\001\d+)\{c\1\}/ç/gs;
	s/\\c(\001\d+)\{K\1\}/Ķ/gs;
	s/\\c(\001\d+)\{k\1\}/ķ/gs;
	s/\\c(\001\d+)\{L\1\}/Ļ/gs;
	s/\\c(\001\d+)\{l\1\}/ļ/gs;
	s/\\c(\001\d+)\{N\1\}/Ņ/gs;
	s/\\c(\001\d+)\{n\1\}/ņ/gs;
	s/\\c(\001\d+)\{N\1\}/Ŗ/gs;
	s/\\c(\001\d+)\{n\1\}/ŗ/gs;

	# double acute accent \H{x}
	s/\\H(\001\d+)\{O\1\}/Ő/gs;
	s/\\H(\001\d+)\{U\1\}/Ű/gs;
	s/\\H(\001\d+)\{o\1\}/ő/gs;
	s/\\H(\001\d+)\{u\1\}/ű/gs;

	# breve accent \u{x}
	s/\\u(\001\d+)\{A\1\}/Ă/gs;
	s/\\u(\001\d+)\{E\1\}/Ĕ/gs;
	s/\\u(\001\d+)\{G\1\}/Ğ/gs;
	s/\\u(\001\d+)\{I\1\}/Ĭ/gs;
	s/\\u(\001\d+)\{O\1\}/Ŏ/gs;
	s/\\u(\001\d+)\{U\1\}/Ŭ/gs;
	s/\\u(\001\d+)\{a\1\}/ă/gs;
	s/\\u(\001\d+)\{e\1\}/ĕ/gs;
	s/\\u(\001\d+)\{g\1\}/ğ/gs;
	s/\\u(\001\d+)\{i\1\}/ĭ/gs;
	s/\\u(\001\d+)\{o\1\}/ŏ/gs;
	s/\\u(\001\d+)\{u\1\}/ŭ/gs;

	# hacek/caron? accent \v{x}
	s/\\v(\001\d+)\{C\1\}/Č/gs;
	s/\\v(\001\d+)\{D\1\}/Ď/gs;
	s/\\v(\001\d+)\{E\1\}/Ě/gs;
	s/\\v(\001\d+)\{L\1\}/Ľ/gs;
	s/\\v(\001\d+)\{N\1\}/Ň/gs;
	s/\\v(\001\d+)\{R\1\}/Ř/gs;
	s/\\v(\001\d+)\{S\1\}/Š/gs;
	s/\\v(\001\d+)\{T\1\}/Ť/gs;
	s/\\v(\001\d+)\{Z\1\}/Ž/gs;
	s/\\v(\001\d+)\{c\1\}/č/gs;
	s/\\v(\001\d+)\{d\1\}/ď/gs;
	s/\\v(\001\d+)\{e\1\}/ě/gs;
	s/\\v(\001\d+)\{l\1\}/ľ/gs;
	s/\\v(\001\d+)\{n\1\}/ň/gs;
	s/\\v(\001\d+)\{r\1\}/ř/gs;
	s/\\v(\001\d+)\{s\1\}/š/gs;
	s/\\v(\001\d+)\{t\1\}/ť/gs;
	s/\\v(\001\d+)\{z\1\}/ž/gs;

	# macron \={x}
	s/\\\=(\001\d+)\{A\1\}/Ā/gs;
	s/\\\=(\001\d+)\{E\1\}/Ē/gs;
	s/\\\=(\001\d+)\{O\1\}/Ō/gs;
	s/\\\=(\001\d+)\{U\1\}/Ū/gs;
	s/\\\=(\001\d+)\{a\1\}/ā/gs;
	s/\\\=(\001\d+)\{e\1\}/ē/gs;
	s/\\\=(\001\d+)\{o\1\}/ō/gs;
	s/\\\=(\001\d+)\{u\1\}/ū/gs;

	# macron \=x
	s/\\\=A/Ā/g;
	s/\\\=E/Ē/g;
	s/\\\=O/Ō/g;
	s/\\\=U/Ū/g;
	s/\\\=a/ā/g;
	s/\\\=e/ē/g;
	s/\\\=o/ō/g;
	s/\\\=u/ū/g;

	# dot \.{x}
	s/\\\.(\001\d+)\{G\1\}/Ġ/gs;
	s/\\\.(\001\d+)\{L\1\}/Ŀ/gs;
	s/\\\.(\001\d+)\{Z\1\}/Ż/gs;
	s/\\\.(\001\d+)\{g\1\}/ġ/gs;
	s/\\\.(\001\d+)\{l\1\}/ŀ/gs;
	s/\\\.(\001\d+)\{z\1\}/ż/gs;

	# dot \.x
	s/\\\.G/Ġ/g;
	s/\\\.L/Ŀ/g;
	s/\\\.Z/Ż/g;
	s/\\\.g/ġ/g;
	s/\\\.l/ŀ/g;
	s/\\\.z/ż/g;


	# slashed l
	s/\\l\b/ł/g;
	s/\\L\b/Ł/g;

	# krouzek \accent23x or \accent'27
	s/\{\\accent2[37]\s*u\}/ů/g;
	s/\\accent2[37]\s*u/ů/g;

	# Other special characters.
	s/\\O\b\s*/Ø/g;
	s/\\o\b\s*/ø/g;
	s/\\AA\b\s*/Å/g;
	s/\\aa\b\s*/å/g;
	s/\\AE\b\s*/Æ/g;
	s/\\ae\b\s*/æ/g;
	s/\\OE\b\s*/Œ/g;
	s/\\oe\b\s*/œ/g;
	s/\\ss\b\s*/ß/g;
	s/\\S\b\s*/§/g;
	s/\\P\b\s*/¶/g;
	s/\\pounds\b\s*/£/g;
	s/\?\`/¿/g;
	s/\!\`/¡/g;

	# en and em dashes
	# Try to be careful to not change the dashes in HTML comments
	# (<!-- comment -->) to &ndash;s.
	s/\-\-\-/—/g;			# --- -> &#x2014
	s/([^\!])\-\-([^\>])/$1–$2/g;	# -- -> &#x2013

	# Upper case Greek
	s/\\Alpha\b/Α/g;
	s/\\Beta\b/Β/g;
	s/\\Gamma\b/Γ/g;
	s/\\Delta\b/Δ/g;
	s/\\Epsilon\b/Ε/g;
	s/\\Zeta\b/Ζ/g;
	s/\\Eta\b/Η/g;
	s/\\Theta\b/Θ/g;
	s/\\Iota\b/Ι/g;
	s/\\Kappa\b/Κ/g;
	s/\\Lambda\b/Λ/g;
	s/\\Mu\b/Μ/g;
	s/\\Nu\b/Ν/g;
	s/\\Xi\b/Ξ/g;
	s/\\Omicron\b/Ο/g;
	s/\\Pi\b/Π/g;
	s/\\Rho\b/Ρ/g;
	s/\\Sigma\b/Σ/g;
	s/\\Tau\b/Τ/g;
	s/\\Upsilon\b/Υ/g;
	s/\\Phi\b/Φ/g;
	s/\\Chi\b/Χ/g;
	s/\\Psi\b/Ψ/g;
	s/\\Omega\b/Ω/g;

	# Lower case Greek
	s/\\alpha\b/α/g;
	s/\\beta\b/β/g;
	s/\\gamma\b/γ/g;
	s/\\delta\b/δ/g;
	s/\\varepsilon\b/ε/g;
	s/\\epsilon\b/ε/g;
	s/\\zeta\b/ζ/g;
	s/\\eta\b/η/g;
	s/\\theta\b/θ/g;
	s/\\vartheta\b/θ/g;
	s/\\iota\b/ι/g;
	s/\\kappa\b/κ/g;
	s/\\lambda\b/λ/g;
	s/\\mu\b/μ/g;
	s/\\nu\b/ν/g;
	s/\\xi\b/ξ/g;
	s/\\omicron\b/ο/g;
	s/\\pi\b/π/g;
	s/\\varpi\b/π/g;
	s/\\rho\b/ρ/g;
	s/\\varrho\b/ρ/g;
	s/\\sigma\b/σ/g;
	s/\\varsigma\b/ς/g;
	s/\\tau\b/τ/g;
	s/\\upsilon\b/υ/g;
	s/\\phi\b/φ/g;
	s/\\varphi\b/φ/g;
	s/\\chi\b/χ/g;
	s/\\psi\b/ψ/g;
	s/\\omega\b/ω/g;
}

$opt_B = 'bibtex' unless defined($opt_B);

# Prevent "identifier used only once" warnings.
$opt_a = $opt_b = $opt_c = $opt_D = $opt_d = $opt_e = $opt_h = $opt_m =
$opt_n = $opt_r = $opt_R = $opt_i = $opt_k = $opt_s = $opt_t = $opt_v =
$opt_u = undef;

$macrofile = '';

$command_line = &html_encode(join(' ', $0, @ARGV));

getopts("aB:b:cd:D:e:h:ikm:n:rRs:tuv") || &usage;

if (defined($opt_n)) {
    $highlighted_name = $opt_n;
    $highlighted_name =~ s/\s/[\\s~]+/;
}

if (defined($opt_v)) {
	print "$version\n";
	exit 0;
}

&usage if (($#ARGV < 0) || ($#ARGV > 1));

if ($ARGV[0] =~ m/\.bib$/) {
    $bibfile = $ARGV[0];
    $bibfile =~ s/\.bib$//;
    $delimiter = $bibfile;
} elsif ($ARGV[0] =~ m/\.aux$/) {
    if ($opt_i) {
        print STDERR "source file must be a bibliography (.bib) file when run with the -i switch \n";
        &usage;
    }
    $citefile = $ARGV[0];
    $citefile =~ s/\.aux$//;
    $delimiter = $citefile;
} else {
    print STDERR "Unknown file extension on $ARGV[0]\n";
    &usage;
}

$htmlfile = $ARGV[1] if ($#ARGV == 1);

$delimiter = $opt_d if (defined($opt_d));
$title = (defined($opt_h) ? $opt_h : "Bibliography generated from $ARGV[0]");
$macrofile = "$opt_m," if (defined($opt_m));

$opt_s = 'empty' if (! defined $opt_s);
style: {
    ($opt_s eq 'empty') &&
	($bstfile = "html-n",
	 $label_style = $LABEL_PLAIN,
	 last style);
    ($opt_s eq 'plain') &&
	($bstfile = "html-n",
	 $label_style = $LABEL_NUMBERED,
	 last style);
    ($opt_s eq 'alpha') &&
	($bstfile = "html-a",
	 $label_style = $LABEL_DEFAULT,
	 last style);
    ($opt_s eq 'named') &&
	($bstfile = "html-n",
	 $label_style = $LABEL_DEFAULT,
	 last style);
    ($opt_s eq 'paragraph') &&
	($bstfile = "html-n",
	 $label_style = $LABEL_PARAGRAPH,
	 last style);
    ($opt_s eq 'unsort') &&
	($bstfile = "html-u",
	 $label_style = $LABEL_NUMBERED,
	 last style);
    ($opt_s eq 'unsortlist') &&
	($bstfile = "html-u",
	 $label_style = $LABEL_PLAIN,
	 last style);
    ($opt_s =~ s/\.bst$//) &&
	($bstfile = $opt_s,
	 # label-style will be defined in .bst file.
	 last style);
    print STDERR "Unknown style: $_\n";
    &usage;
}

if ($bstfile eq "html-u" && ($opt_r || $opt_c)) {
    print STDERR "Unsorted styles do not support a sort specification\n";
    exit(1);
}

if ($opt_k && !($label_style == $LABEL_NUMBERED || $label_style == $LABEL_DEFAULT)) {
    print STDERR "The specified style does not support the display of BibTeX keys\n";
    exit(1);
}


$bstfile .= "c" if (defined ($opt_c));
$bstfile .= "r" if (defined ($opt_r));
$bstfile .= "a" if (defined ($opt_a));

# Extended information is specified as a sequence of
# (PostScript|PDF|DVI|DOI):icon or
# (notype|nosize|nopages|nocompression|nodoi|nobrackets)
# Set correspondingly the associative array %typeicon and the no* variables
# Example usage:
# perl bib2xhtml -e 'nosize,nopages,PDF:<img src="pdficon_small.gif" alt="PDF" border="0" />' example.bib  >example.html
undef $nopages;
undef $nosize;
undef $nodoi;
undef $notype;
undef $nocompression;
undef $nobrackets;

if (defined($opt_e)) {
	my(@opts) = split(/,/, $opt_e);
	for $opt (@opts) {
		if ($opt =~ m/(PostScript|PDF|DVI|DOI|DJVU):(.*)/) {
			$typeicon{$1} = $2;
		} elsif ($opt =~ m/(notype|nosize|nopages|nocompression|nodoi|nobrackets)/) {
			eval "\$$1 = 1";
		} else {
			print STDERR qq{Invalid extended information specification: $opt
This can be a comma-separated list of the following specifications:
PostScript|PDF|DVI|DOI|DJVU:new-text (e.g. PDF file icon)
notype|nosize|nopages|nocompression|nodoi|nobrackets
};
			exit 1;
		}
	}
}

# PostScript and PDF files are assumed to be in same directory
# as the target HTML file.
if (defined($htmlfile) && ($htmlfile =~ m+(^.*)/+)) {
    push @filedir, $1;
} else {
    push @filedir, "."
}
if (defined $opt_D) {
    local($dir, $url);
    foreach $dir (split(/\,/, $opt_D)) {
	$url = $dir;
	if ($dir =~ s/\@(.*)$//) { $url = $1; }
	push @filedir, $dir;
	$dirmap{$dir} = $url;
    }
}

umask(077);

open(HTMLFILE, (defined($htmlfile) ? ">$htmlfile$$" : ">&STDOUT"));
if (defined($htmlfile) && open(OHTMLFILE, "$htmlfile")) {
    $mode = (stat OHTMLFILE)[2] & 0xfff;
    $updating = 1;
} else {
    $mode = 0644;
    $updating = 0;

    # An existing HTML file does not exist, so output some boilerplate.
    if ($opt_u) {
        $enc = 'UTF-8';
    } else {
        $enc = 'US-ASCII';
    }
    print HTMLFILE
qq{<?xml version="1.0" encoding="$enc"?>
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<title>$title</title>
<meta http-equiv="Content-type" content="text/html; charset=$enc" />} . q{
<meta name="Generator" content="$Id: \\dds\\src\\textproc\\bib2xhtml\\RCS\\bib2xhtml,v 2.38 2011/10/19 15:15:05 dds Exp $" />
</head>
<body>
}
}

$beginstring = "<!-- BEGIN CITATIONS $delimiter -->";
$endstring = "<!-- END CITATIONS $delimiter -->";

@citations = ();

if ($opt_i && $updating) {
 loop:
  while (<OHTMLFILE>) {
    print HTMLFILE;
    last loop if m/^$beginstring$/;
  }
 loop:
  while (<OHTMLFILE>) {
    print HTMLFILE;
    last loop if m/^$endstring$/;
    push(@citations, $2) if m/^([^\\]*)?(.+\})(.*)?$/;
  }
  push(@citations, "\\bibdata{$macrofile$bibfile}");
}

# Create an .aux file for bibtex to read.

$auxfile = "bib$$";
push(@tmpfiles, "$auxfile.aux");

open(AUXFILE, ">$auxfile" . ".aux");

print AUXFILE "\\relax\n\\bibstyle{$bstfile}\n";

if (defined($citefile)) {
    $citefile .= ".aux";
    open(CITEFILE, "<$citefile") || die "error opening $citefile: $!\n";
    while (<CITEFILE>) {
	print AUXFILE $_ if (m/^\\(citation|bibdata){/);
    }
    close(CITEFILE);
} elsif (@citations) {
  foreach $citation (@citations) {
    print AUXFILE "$citation\n";
  }
} else {
    print AUXFILE "\\citation{*}\n\\bibdata{$macrofile$bibfile}\n";
}

close(AUXFILE);


# run bibtex, redirecting bibtex's output from STDOUT to STDERR.

push(@tmpfiles, "$auxfile.blg");
push(@tmpfiles, "$auxfile.bbl");

#Flush HTMLFILE to avoid duplicate buffer writes after the fork
select(HTMLFILE);
$| = 1; $| = 0;
select(STDOUT);

# We attempt to fork in order to redirect bibtex's stdout to stderr.
# This is needed when bib2xhtml is generating its output on the
# standard output.
# The shell redirection syntax used in the system() alternative
# is by no means portable.
eval { fork || (open(STDOUT, ">&STDERR"),
	# Handle leakage in Win32 prevents the final rename()
	close(HTMLFILE),
	close(OHTMLFILE),
	exec($opt_B, (split(/\s+/, ($opt_b ? $opt_b : "")), $auxfile)));
	wait; };
# fork is not implemented on some non-Unix platforms.
if ($@) {
    # The fork failed (perhaps not implemented on this system).
    system("$opt_B $opt_b $auxfile 1>&2");
}

$beginstring = "<!-- BEGIN BIBLIOGRAPHY $delimiter -->";
$endstring = "<!-- END BIBLIOGRAPHY $delimiter -->";

if ($updating) {
loop:
    while (<OHTMLFILE>) {
	last loop if m/^$beginstring$/;
	print HTMLFILE;
    }
loop:
    while (<OHTMLFILE>) {
	last loop if m/^$endstring$/;
    }
}

print HTMLFILE "$beginstring\n";
print HTMLFILE <<EOF;
<!--
    DO NOT MODIFY THIS BIBLIOGRAPHY BY HAND!  IT IS MAINTAINED AUTOMATICALLY!
    YOUR CHANGES WILL BE LOST THE NEXT TIME IT IS UPDATED!
-->
<!-- Generated by: $command_line -->
EOF
# Now we make two passes over the .bbl file.  In the first pass, we
# just collect the {cite, label} pairs, which we will use later for
# crossrefs.

$t = $auxfile . ".bbl";

$/ = "";

# Make a first pass through the .bbl file, collecting citation/label pairs.
$ntotent = 0;
if (defined($opt_R)) {
	open(BBLFILE, "<$t") || die "error opening $t: $!\n";
	while (<BBLFILE>) {
		($bcite, $blabel) = m+name=\"([^\"]*)\">\[([^\]]*)\]</a></dt><dd>+;
		if ($bcite) {
			$ntotent++;
		}
	}
	close(BBLFILE);
}
open(BBLFILE, "<$t") || die "error opening $t: $!\n";
$nentry = 0;
loop:
while (<BBLFILE>) {
    # Check for definitions at start of .bbl file.
    if (($nentry == 0) && (m/^#/)) {
	if ((m/#\s*label-style:\s*(\S+)/) && (! defined $label_style)) {
	    $label_style = $label_styles{$1};
	    if (! defined $label_style) {
		print STDERR "label style unknown: \n";
		next loop;
	    }
	}
	next loop;
    }
    $nentry++;
    ($bcite, $blabel) = m+name=\"([^\"]*)\">\[([^\]]*)\]</a></dt><dd>+;
	if ($label_style == $LABEL_NUMBERED) {
		if (defined ($opt_R)) {
			$blabel = $ntotent - $nentry + 1;
			$blabel = "$blabel";
		} else {
			$blabel = "$nentry";
		}
	}
    $bibcite{$bcite} = $blabel;
}
close(BBLFILE);

$label_style = $LABEL_DEFAULT if (! defined $label_style);
$list_start = $list_start[$label_style];
$list_end = $list_end[$label_style];

if (defined($opt_t)) {
    print HTMLFILE "$nentry references, last updated " . localtime . "<p />\n";
}

print HTMLFILE "<$list_start>\n\n";

#foreach $key (sort (keys(%bibcite))) {
#    print "$key : $bibcite{$key}\n";
#}

open(BBLFILE, "<$t") || die "error opening $t: $!\n";
$nentry = 0;
loop:
while (<BBLFILE>) {
    # Skip definitions at start of .bbl file.
    next loop if (($nentry == 0) && (m/^#/));

    $nentry++;

	if (defined ($opt_R)) {
		$nentryp = $ntotent - $nentry + 1;
	} else {
		$nentryp = $nentry;
	}

    # Protect \{, \}, and \$, and then assign matching {} pairs a unique ID.
    s/\\\{/\002/g;
    s/\\\}/\003/g;
    s/\\\$/\004/g;
    {
	local ($c, $l, $z) = (0, 0, ());
	s/([\{\}])/join("","\001",($1 eq "\{" ? $z[$l++]=$c++ : $z[--$l]),$1)/ge;
    }

    # bibtex sometimes breaks long lines by inserting "%\n".  We remove
    # that because it might accidently break the line in the middle
    # of a URL.  We don't need to deal with TeX comments in general
    # because bibtex seems to munge them up anyway, so there shouldn't
    # be any in the bibliography file.
    s/\%\n//g;

    # bibtex's add.period$ knows how to avoid adding extra periods
    # when a block already ends in a period.  bib2xhtml's modifications
    # of bibtex's style files break that.  We fix it here.
    s/(\.(<\/cite>|<\/a>|\')+)\./$1/g;

    # Adjust beginning of entry based on bibliography style.
    if ($label_style == $LABEL_PLAIN) {
	s+<dt><a+<li><a+;
	s+(name=\"[^\"]*\">)\[[^\]]*\](</a>)</dt><dd>+$1$2+;
	s+</dd>+</li>+;

	# Attempt to fix up empty <a name=...></a> tag, which some browsers
	# don't handle properly (even though it *is* legal HTML).
	# First try to combine a <a name=...></a> with a following <A ".
	s+(name=\"[^\"]*\")></a><a\b+$1+
	# If that doesn't work, try to swallow following word.
	or s:(name=\"[^\"]*\">)</a>([\w]+):$1$2<\/a>:;
    } elsif ($label_style == $LABEL_PARAGRAPH) {
	s+<dt><a+<p><a+;
	s+(name=\"[^\"]*\">)\[[^\]]*\](</a>)</dt><dd>+$1$2+;
	s+</dd>+</p>+;

	# Attempt to fix up empty <a name=...></a> tag, which some browsers
	# don't handle properly (even though it *is* legal HTML).
	# First try to combine a <a name=...></a> with a following <A ".
	s+(name=\"[^\"]*\")></a><a\b+$1+
	# If that doesn't work, try to swallow following word.
	or s:(name=\"[^\"]*\">)</a>([\w]+):$1$2<\/a>:;	
    } elsif ($label_style == $LABEL_NUMBERED) {
	s+(name=\"[^\"]*\">\[)[^\]]*(\]</a></dt><dd>)+$1$nentryp$2+;
    }

    # Append the key name, if asked so
    if ($opt_k && ($label_style == $LABEL_NUMBERED || $label_style == $LABEL_DEFAULT)) {
	# $1       $2      $3     $4      $5
	s+(name=\")([^\"]*)(\">\[)([^\]]*)(\]</a></dt><dd>)+$1$2$3$4 --- $2$5+;
    }

    # Attempt to fix up crossrefs.
    while (m/(\\(cite(label)?)(\001\d+)\{([^\001]+)\4\})/) {
	$old = $1;
	$cmd = $2;
	$doxref = defined($3);
	$bcite = $5;
	if (! defined $bibcite{$bcite}) {
	    $blabel = " [" . $bcite . "]";
	} elsif ($doxref) {
	    $blabel = " <a href=\"#$bcite\">[" . $bibcite{$bcite} . "]<\/a>";
	} else {
	    $blabel = " [" . $bibcite{$bcite} . "]";
	}
	$old =~ s/(\W)/\\$1/g;
	s/\s*$old/$blabel/g;
    }
    # In some styles crossrefs become something like 
    # "In Doe and Roe [Doe and Roe, 1995]."  Change this to
    # "In [Doe and Roe, 1995]." to remove the redundancy.
    s/In (<a href=\"[^\"]*\">)([^\[]+) \[(\2)/In $1\[$2/;

    # Handle the latex2html commands \htmladdnormallink{text}{url}
    # and \htmladdnormallinkfoot{text}{url}.
    s/\\htmladdnormallink(foot)?(\001\d+)\{([^\001]+)\2\}(\001\d+)\{([^\001]+)\4\}/<a href="$5">$3<\/a>/gs;

    s/\&amp;/\005/g;			# Protect original &amp; sequences
    s/\\?&/&amp;/g;			# \& -> &amp; and & -> &amp;
    s/\005/&amp;/g;			# Restore original &amp; sequences

    if ($opt_u) {
        utf_ent();
    } else {
    	html_ent();
    }

    # Handle \char123 -> &123;.
    while (m/\\char([\'\"]?[0-9a-fA-F]+)/) {
	$o = $r = $1;
	if ($r =~ s/^\'//) {
	    $r = oct($r);
	} elsif ($r =~ s/^\"//) {
	    $r = hex($r);
	}
	s/\\char$o\s*/&#$r;/g;
    }

    s/{\\etalchar\001(\d+)\{(.)}\001\1\}/$2/g;	# {\etalchar{x}} -> x

    s/\\par\b/<p \/>/g;

    s/\\url(\001\d+)\{(.*)\1\}/<a href="$2">$2<\/a>/gs; #\url{text} -> <a href"text">text</a>
    s/\\href(\001\d+)\{(.*)\1\}(\001\d+)\{([^\001]*)\3\}/<a href="$2">$4<\/a>/gs; #\href{text} -> <a href"link">text</a>
    s/\\href(\001\d+)\{(.*)\1\}/<a href="$2">$2<\/a>/gs; #\href{text} -> <a href"text">text</a>


    # There's no way to easily handle \rm and \textrm because
    # HTML has no tag to convert back to plain text.  Since it's very
    # difficult to do the right thing, we do the wrong thing, and just
    # remove them.
    s/(\001\d+)\{\\rm\s+(.*)\1\}/$2/gs;		# {\rm text} -> text
    s/\\textrm(\001\d+)\{(.*)\1\}/$2/gs;		# \textrm{text} -> text

    # This doesn't create correct HTML, because HTML doesn't allow nested
    # character style tags.  Oh well.
    s/(\001\d+)\{\\em\s+(.*)\1\}/<em>$2<\/em>/gs; # {\em text} -> <EM>text</EM>
    s/(\001\d+)\{\\it\s+(.*)\1\}/<i>$2<\/i>/gs;   # {\it text} -> <I>text</I>
    s/(\001\d+)\{\\bf\s+(.*)\1\}/<b>$2<\/b>/gs;   # {\bf text} -> <B>text</B>
    s/(\001\d+)\{\\tt\s+(.*)\1\}/<tt>$2<\/tt>/gs; # {\tt text} -> <TT>text</TT>

    s/\\emph(\001\d+)\{(.*)\1\}/<em>$2<\/em>/gs;  # \emph{text} -> <EM>text</EM>
    s/\\textit(\001\d+)\{(.*)\1\}/<i>$2<\/i>/gs;  # \textit{text} -> <I>text</I>
    s/\\textbf(\001\d+)\{(.*)\1\}/<b>$2<\/b>/gs;  # \textbf{text} -> <B>text</B>
    s/\\texttt(\001\d+)\{(.*)\1\}/<tt>$2<\/tt>/gs;# \textit{text} -> <TT>text</TT>

    s/\\mathrm(\001\d+)\{(.*)\1\}/$2/gs;		# \mathrm{text} -> text
    s/\\mathnormal(\001\d+)\{(.*)\1\}/$2/gs;	# \mathnormal{text} -> text
    s/\\mathsf(\001\d+)\{(.*)\1\}/$2/gs;		# \mathsf{text} -> text
    s/\\mathbf(\001\d+)\{(.*)\1\}/<b>$2<\/b>/gs;	# \mathbf{text} -> <B>text</B>
    s/\\mathcal(\001\d+)\{(.*)\1\}/<i>$2<\/i>/gs;# \mathcal{text} -> <I>text</I>
    s/\\mathit(\001\d+)\{(.*)\1\}/<i>$2<\/i>/gs;	# \mathit{text} -> <I>text</I>
    s/\\mathtt(\001\d+)\{(.*)\1\}/<tt>$2<\/tt>/gs;# \mathtt{text} -> <TT>text</TT>

    # Custom highlighting for the -n option.
    s/\\bibxhtmlname(\001\d+)\{(.*)\1\}/&highlight_name($2)/ges;

    # {\boldmath $mathstuff$} -> <B>mathstuff</B>
#    s/(\001\d+)\{\s*\\boldmath ?([^A-Za-z\{\}][^\{\}]*)\}/<b>$1<\/b>/gs;


sub domath {
    local($t) = @_;
    $t =~ s/\^(\001\d+)\{\\circ\1\}/\&\#176;/gs;		# ^{\circ}->degree
    $t =~ s/\^\\circ/\&\#176;/g;				# ^\circ->degree
#   $t =~ s/\^(\001\d+)\{(.*)\1\}/<sup>$2<\/sup>/gs;	# ^{x}
    $t =~ s/\^(\001\d+)\{(.*)\1\}/<sup>$2<\/sup>/gs;	# ^{x}
    $t =~ s/\^(\w)/<sup>$1<\/sup>/g;			# ^x
#   $t =~ s/\_(\001\d+)\{(.*)\1\}/<sub>$2<\/sub>/gs;	# _{x}
    $t =~ s/\_(\001\d+)\{(.*)\1\}/<sub>$2<\/sub>/gs;	# _{x}
    $t =~ s/\_(\w)/<sub>$1<\/sub>/g;			# _x
    $t;
}

    # Handle superscripts and subscripts in inline math mode.
    s/(\$([^\$]+)\$)/&domath($2)/ge;			# $ ... $
    s/(\\\((([^\\]|\\[^\(\)])+)\\\))/&domath($2)/ge;	# \( ... \)

    # Remove \mbox.
    s/\\mbox(\001\d+)\{(.*)\1\}/$2/gs;		# \mbox{x}

    # Escape and protect tildes in URLs
    # For some reason /g doesn't work
    while (s/(\<a href\=\"[^"]*?)\~/$1\005/g) { ; }
    if ($opt_u) {
        s/([^\\])~/$1 /g;			# ~  non-breaking space - &#xa0;
        s/\\\,/ /g;				# \, thin space - &#x2009;
        s/\\ldots\b\s*/…/g;			# Horizontal ellipsis
        s/\\dots\b\s*/…/g;			# Horizontal ellipsis
    } else {
        s/([^\\])~/$1&nbsp;/g;			# ~  non-breaking space
        s/\\\,/&thinsp;/g;			# \, thin space
        s/\\ldots\b/&hellip;/g;			# Horizontal ellipsis
	s/\\dots\b/&hellip;/g;			# Horizontal ellipsis

    }
    s/\005/\~/g;				# Unescape tildes
    s/\\ / /g;					# \  (normal space)
    s/\\textasciitilde\b\s*/~/g;		# \textasciitilde -> ~

    # Non-alphabetic macros that we keep.
    s/\\([\#\&\%\~\_\^\|])/$1/g;

    # Non-alphabetic macros that we remove.
    #   (discretionary hyphen)
    #   (italic correction)
    s/\\\W//g;

    # Clean up things we don't handle.
#    s/\\//g;

    # The format {\Xyz{Abc}} is interpreted by BibTeX as a single letter
    # whose text is given by "Abc".  If we see this pattern, it is
    # likely that discarding the \Xyz will do the right thing.
    s/\001(\d+)\{\\[A-Za-z]+\001(\d+)\{([^\001]*)\001\2\}\001\1\}/$3/g;

    # Macro names may be meaningful, so keep them and don't run them together.
    s/\\([A-Za-z]+)/ $1 /g;

    # Remove an empty <a href=...></a> tag that bad cross-referencing
    # in the BibTeX file may have left us with.
    s+In <a href=\"[^\"]*\"></a>++;

    &doPaperLinks;

    # Get rid of { } ids, and put protected { } back.
    s/\001\d+[\{\}]//gs;
    tr/\002\003\004/{}$/;

    print HTMLFILE $_;
}

close(BBLFILE);

print HTMLFILE "<$list_end>\n\n$endstring\n";

if ($updating) {
    while (<OHTMLFILE>) {
	print HTMLFILE;
    }
    close (OHTMLFILE);
} else {
    print HTMLFILE "</body></html>\n";
}

close(HTMLFILE);

if (defined ($htmlfile)) {
    #$mode &= 0777;
    #print "setting $htmlfile$$ to $mode\n";
    #printf("mode = %lo\n", $mode);

    chmod($mode, "$htmlfile$$");
    rename("$htmlfile$$", $htmlfile);
}

unlink(@tmpfiles);

exit(0);
