#!/usr/bin/env perl
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

use utf8;
use warnings;
use Getopt::Std;

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
                [-m macro file] [-n name] [-r] [-R] [-s style] [-t] [-u] [-U] [-v]
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
    -U  Treat input file as Unicode-coded document.
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

# Convert $_ into a UTF-8 character
sub utf_ent {
	# Use \006 to avoid characters coming together before TeX escapes
	# are recognized.
	# For example \omicron\mu would become \omicronμ, which will then
	# fail to match the RE \\omicron\b

	# Accents.
	s/\\i\b/\006ı\006/gs;					# dotless i.

	# acute accent \'{x}
	s/\\\'(\001\d+)\{A\1\}/\006Á\006/gs;
	s/\\\'(\001\d+)\{C\1\}/\006Ć\006/gs;
	s/\\\'(\001\d+)\{E\1\}/\006É\006/gs;
	s/\\\'(\001\d+)\{I\1\}/\006Í\006/gs;
	s/\\\'(\001\d+)\{L\1\}/\006Ĺ\006/gs;
	s/\\\'(\001\d+)\{N\1\}/\006Ń\006/gs;
	s/\\\'(\001\d+)\{O\1\}/\006Ó\006/gs;
	s/\\\'(\001\d+)\{R\1\}/\006Ŕ\006/gs;
	s/\\\'(\001\d+)\{S\1\}/\006Ś\006/gs;
	s/\\\'(\001\d+)\{U\1\}/\006Ú\006/gs;
	s/\\\'(\001\d+)\{Y\1\}/\006Ý\006/gs;
	s/\\\'(\001\d+)\{Z\1\}/\006Ź\006/gs;
	s/\\\'(\001\d+)\{a\1\}/\006á\006/gs;
	s/\\\'(\001\d+)\{c\1\}/\006ć\006/gs;
	s/\\\'(\001\d+)\{e\1\}/\006é\006/gs;
	s/\\\'(\001\d+)\{ı\1\}/\006í\006/gs;
	s/\\\'(\001\d+)\{i\1\}/\006í\006/gs;
	s/\\\'(\001\d+)\{l\1\}/\006ĺ\006/gs;
	s/\\\'(\001\d+)\{n\1\}/\006ń\006/gs;
	s/\\\'(\001\d+)\{o\1\}/\006ó\006/gs;
	s/\\\'(\001\d+)\{r\1\}/\006ŕ\006/gs;
	s/\\\'(\001\d+)\{s\1\}/\006ś\006/gs;
	s/\\\'(\001\d+)\{u\1\}/\006ú\006/gs;
	s/\\\'(\001\d+)\{y\1\}/\006ý\006/gs;
	s/\\\'(\001\d+)\{z\1\}/\006ź\006/gs;

	# acute accent \'x
	s/\\\'A/\006Á\006/gs;
	s/\\\'C/\006Ć\006/gs;
	s/\\\'E/\006É\006/gs;
	s/\\\'I/\006Í\006/gs;
	s/\\\'L/\006Ĺ\006/gs;
	s/\\\'N/\006Ń\006/gs;
	s/\\\'O/\006Ó\006/gs;
	s/\\\'R/\006Ŕ\006/gs;
	s/\\\'S/\006Ś\006/gs;
	s/\\\'U/\006Ú\006/gs;
	s/\\\'Y/\006Ý\006/gs;
	s/\\\'Z/\006Ź\006/gs;
	s/\\\'a/\006á\006/gs;
	s/\\\'c/\006ć\006/gs;
	s/\\\'e/\006é\006/gs;
	s/\\\'i/\006í\006/gs;
	s/\\\'ı/\006í\006/gs;
	s/\\\'l/\006ĺ\006/gs;
	s/\\\'n/\006ń\006/gs;
	s/\\\'o/\006ó\006/gs;
	s/\\\'r/\006ŕ\006/gs;
	s/\\\'s/\006ś\006/gs;
	s/\\\'u/\006ú\006/gs;
	s/\\\'y/\006ý\006/gs;
	s/\\\'z/\006ź\006/gs;

	# grave accent \`{x}
	s/\\\`(\001\d+)\{A\1\}/\006À\006/gs;
	s/\\\`(\001\d+)\{E\1\}/\006È\006/gs;
	s/\\\`(\001\d+)\{I\1\}/\006Ì\006/gs;
	s/\\\`(\001\d+)\{O\1\}/\006Ò\006/gs;
	s/\\\`(\001\d+)\{U\1\}/\006Ù\006/gs;
	s/\\\`(\001\d+)\{a\1\}/\006à\006/gs;
	s/\\\`(\001\d+)\{e\1\}/\006è\006/gs;
	s/\\\`(\001\d+)\{i\1\}/\006ì\006/gs;
	s/\\\`(\001\d+)\{o\1\}/\006ò\006/gs;
	s/\\\`(\001\d+)\{u\1\}/\006ù\006/gs;

	# grave accent \`x
	s/\\\`A/\006À\006/gs;
	s/\\\`E/\006È\006/gs;
	s/\\\`I/\006Ì\006/gs;
	s/\\\`O/\006Ò\006/gs;
	s/\\\`U/\006Ù\006/gs;
	s/\\\`a/\006à\006/gs;
	s/\\\`e/\006è\006/gs;
	s/\\\`i/\006ì\006/gs;
	s/\\\`o/\006ò\006/gs;
	s/\\\`u/\006ù\006/gs;

	# umlaut \"{x}
	s/\\\"(\001\d+)\{A\1\}/\006Ä\006/gs;
	s/\\\"(\001\d+)\{E\1\}/\006Ë\006/gs;
	s/\\\"(\001\d+)\{I\1\}/\006Ï\006/gs;
	s/\\\"(\001\d+)\{O\1\}/\006Ö\006/gs;
	s/\\\"(\001\d+)\{U\1\}/\006Ü\006/gs;
	s/\\\"(\001\d+)\{Y\1\}/\006Ÿ\006/gs;
	s/\\\"(\001\d+)\{a\1\}/\006ä\006/gs;
	s/\\\"(\001\d+)\{e\1\}/\006ë\006/gs;
	s/\\\"(\001\d+)\{i\1\}/\006ï\006/gs;
	s/\\\"(\001\d+)\{o\1\}/\006ö\006/gs;
	s/\\\"(\001\d+)\{u\1\}/\006ü\006/gs;
	s/\\\"(\001\d+)\{y\1\}/\006ÿ\006/gs;

	# umlaut \"x
	s/\\\"A/\006Ä\006/gs;
	s/\\\"E/\006Ë\006/gs;
	s/\\\"I/\006Ï\006/gs;
	s/\\\"O/\006Ö\006/gs;
	s/\\\"U/\006Ü\006/gs;
	s/\\\"Y/\006Ÿ\006/gs;
	s/\\\"a/\006ä\006/gs;
	s/\\\"e/\006ë\006/gs;
	s/\\\"i/\006ï\006/gs;
	s/\\\"o/\006ö\006/gs;
	s/\\\"u/\006ü\006/gs;
	s/\\\"y/\006ÿ\006/gs;

	# tilde \~{x}
	s/\\\~(\001\d+)\{A\1\}/\006Ã\006/gs;
	s/\\\~(\001\d+)\{N\1\}/\006Ñ\006/gs;
	s/\\\~(\001\d+)\{O\1\}/\006Õ\006/gs;
	s/\\\~(\001\d+)\{a\1\}/\006ã\006/gs;
	s/\\\~(\001\d+)\{n\1\}/\006ñ\006/gs;
	s/\\\~(\001\d+)\{o\1\}/\006õ\006/gs;

	# tilde \~x
	s/\\\~A/\006Ã\006/gs;
	s/\\\~N/\006Ñ\006/gs;
	s/\\\~O/\006Õ\006/gs;
	s/\\\~a/\006ã\006/gs;
	s/\\\~n/\006ñ\006/gs;
	s/\\\~O/\006õ\006/gs;

	# circumflex \^{x}
	s/\\\^(\001\d+)\{A\1\}/\006Â\006/gs;
	s/\\\^(\001\d+)\{E\1\}/\006Ê\006/gs;
	s/\\\^(\001\d+)\{G\1\}/\006Ĝ\006/gs;
	s/\\\^(\001\d+)\{H\1\}/\006Ĥ\006/gs;
	s/\\\^(\001\d+)\{I\1\}/\006Î\006/gs;
	s/\\\^(\001\d+)\{J\1\}/\006Ĵ\006/gs;
	s/\\\^(\001\d+)\{O\1\}/\006Ô\006/gs;
	s/\\\^(\001\d+)\{U\1\}/\006Û\006/gs;
	s/\\\^(\001\d+)\{W\1\}/\006Ŵ\006/gs;
	s/\\\^(\001\d+)\{Y\1\}/\006Ŷ\006/gs;
	s/\\\^(\001\d+)\{a\1\}/\006â\006/gs;
	s/\\\^(\001\d+)\{e\1\}/\006ê\006/gs;
	s/\\\^(\001\d+)\{g\1\}/\006ĝ\006/gs;
	s/\\\^(\001\d+)\{h\1\}/\006ĥ\006/gs;
	s/\\\^(\001\d+)\{i\1\}/\006î\006/gs;
	s/\\\^(\001\d+)\{j\1\}/\006ĵ\006/gs;
	s/\\\^(\001\d+)\{o\1\}/\006ô\006/gs;
	s/\\\^(\001\d+)\{u\1\}/\006û\006/gs;
	s/\\\^(\001\d+)\{w\1\}/\006ŵ\006/gs;
	s/\\\^(\001\d+)\{y\1\}/\006ŷ\006/gs;

	# circumflex \^x
	s/\\\^A/\006Â\006/gs;
	s/\\\^E/\006Ê\006/gs;
	s/\\\^G/\006Ĝ\006/gs;
	s/\\\^H/\006Ĥ\006/gs;
	s/\\\^I/\006Î\006/gs;
	s/\\\^J/\006Ĵ\006/gs;
	s/\\\^O/\006Ô\006/gs;
	s/\\\^U/\006Û\006/gs;
	s/\\\^W/\006Ŵ\006/gs;
	s/\\\^Y/\006Ŷ\006/gs;
	s/\\\^a/\006â\006/gs;
	s/\\\^e/\006ê\006/gs;
	s/\\\^g/\006ĝ\006/gs;
	s/\\\^h/\006ĥ\006/gs;
	s/\\\^i/\006î\006/gs;
	s/\\\^J/\006ĵ\006/gs;
	s/\\\^o/\006ô\006/gs;
	s/\\\^u/\006û\006/gs;
	s/\\\^w/\006ŵ\006/gs;
	s/\\\^y/\006ŷ\006/gs;

	# cedilla \c{x}
	s/\\c(\001\d+)\{C\1\}/\006Ç\006/gs;
	s/\\c(\001\d+)\{c\1\}/\006ç\006/gs;
	s/\\c(\001\d+)\{K\1\}/\006Ķ\006/gs;
	s/\\c(\001\d+)\{k\1\}/\006ķ\006/gs;
	s/\\c(\001\d+)\{L\1\}/\006Ļ\006/gs;
	s/\\c(\001\d+)\{l\1\}/\006ļ\006/gs;
	s/\\c(\001\d+)\{N\1\}/\006Ņ\006/gs;
	s/\\c(\001\d+)\{n\1\}/\006ņ\006/gs;
	s/\\c(\001\d+)\{N\1\}/\006Ŗ\006/gs;
	s/\\c(\001\d+)\{n\1\}/\006ŗ\006/gs;

	# Bar under letter; no canonical Unicode set, so remove it
	s/\\b(\001\d+)\{(.)\1\}/\006$2\006/gs;#

	# Dot under the letter
	s/\\d(\001\d+)\{A\1\}/\006Ạ\006/gs;
	s/\\d(\001\d+)\{a\1\}/\006ạ\006/gs;
	s/\\d(\001\d+)\{B\1\}/\006Ḅ\006/gs;
	s/\\d(\001\d+)\{b\1\}/\006ḅ\006/gs;
	s/\\d(\001\d+)\{C\1\}/\006C̣\006/gs;
	s/\\d(\001\d+)\{c\1\}/\006c̣\006/gs;
	s/\\d(\001\d+)\{D\1\}/\006Ḍ\006/gs;
	s/\\d(\001\d+)\{d\1\}/\006ḍ\006/gs;
	s/\\d(\001\d+)\{E\1\}/\006Ẹ\006/gs;
	s/\\d(\001\d+)\{e\1\}/\006ẹ\006/gs;
	s/\\d(\001\d+)\{F\1\}/\006F̣\006/gs;
	s/\\d(\001\d+)\{f\1\}/\006f̣\006/gs;
	s/\\d(\001\d+)\{G\1\}/\006G̣\006/gs;
	s/\\d(\001\d+)\{g\1\}/\006g̣\006/gs;
	s/\\d(\001\d+)\{H\1\}/\006Ḥ\006/gs;
	s/\\d(\001\d+)\{h\1\}/\006ḥ\006/gs;
	s/\\d(\001\d+)\{I\1\}/\006Ị\006/gs;
	s/\\d(\001\d+)\{i\1\}/\006ị\006/gs;
	s/\\d(\001\d+)\{J\1\}/\006J̣\006/gs;
	s/\\d(\001\d+)\{j\1\}/\006j̣\006/gs;
	s/\\d(\001\d+)\{K\1\}/\006Ḳ\006/gs;
	s/\\d(\001\d+)\{k\1\}/\006ḳ\006/gs;
	s/\\d(\001\d+)\{L\1\}/\006Ḷ\006/gs;
	s/\\d(\001\d+)\{l\1\}/\006ḷ\006/gs;
	s/\\d(\001\d+)\{M\1\}/\006Ṃ\006/gs;
	s/\\d(\001\d+)\{m\1\}/\006ṃ\006/gs;
	s/\\d(\001\d+)\{N\1\}/\006Ṇ\006/gs;
	s/\\d(\001\d+)\{n\1\}/\006ṇ\006/gs;
	s/\\d(\001\d+)\{O\1\}/\006Ọ\006/gs;
	s/\\d(\001\d+)\{o\1\}/\006ọ\006/gs;
	s/\\d(\001\d+)\{P\1\}/\006P̣\006/gs;
	s/\\d(\001\d+)\{p\1\}/\006p̣\006/gs;
	s/\\d(\001\d+)\{Q\1\}/\006Q̣\006/gs;
	s/\\d(\001\d+)\{q\1\}/\006q̣\006/gs;
	s/\\d(\001\d+)\{R\1\}/\006Ṛ\006/gs;
	s/\\d(\001\d+)\{r\1\}/\006ṛ\006/gs;
	s/\\d(\001\d+)\{S\1\}/\006Ṣ\006/gs;
	s/\\d(\001\d+)\{s\1\}/\006ṣ\006/gs;
	s/\\d(\001\d+)\{T\1\}/\006Ṭ\006/gs;
	s/\\d(\001\d+)\{t\1\}/\006ṭ\006/gs;
	s/\\d(\001\d+)\{U\1\}/\006Ụ\006/gs;
	s/\\d(\001\d+)\{u\1\}/\006ụ\006/gs;
	s/\\d(\001\d+)\{V\1\}/\006Ṿ\006/gs;
	s/\\d(\001\d+)\{v\1\}/\006ṿ\006/gs;
	s/\\d(\001\d+)\{W\1\}/\006Ẉ\006/gs;
	s/\\d(\001\d+)\{w\1\}/\006ẉ\006/gs;
	s/\\d(\001\d+)\{X\1\}/\006X̣\006/gs;
	s/\\d(\001\d+)\{x\1\}/\006x̣\006/gs;
	s/\\d(\001\d+)\{Y\1\}/\006Ỵ\006/gs;
	s/\\d(\001\d+)\{y\1\}/\006ỵ\006/gs;
	s/\\d(\001\d+)\{Z\1\}/\006Ẓ\006/gs;
	s/\\d(\001\d+)\{z\1\}/\006ẓ\006/gs;

	# double acute accent \H{x}
	s/\\H(\001\d+)\{O\1\}/\006Ő\006/gs;
	s/\\H(\001\d+)\{U\1\}/\006Ű\006/gs;
	s/\\H(\001\d+)\{o\1\}/\006ő\006/gs;
	s/\\H(\001\d+)\{u\1\}/\006ű\006/gs;

	# ring accent \r{x}
	s/\\r(\001\d+)\{A\1\}/\006Å\006/gs;
	s/\\r(\001\d+)\{D\1\}/\006D̊\006/gs;
	s/\\r(\001\d+)\{E\1\}/\006E̊\006/gs;
	s/\\r(\001\d+)\{G\1\}/\006G̊\006/gs;
	s/\\r(\001\d+)\{I\1\}/\006I̊\006/gs;
	s/\\r(\001\d+)\{J\1\}/\006J̊\006/gs;
	s/\\r(\001\d+)\{O\1\}/\006O̊\006/gs;
	s/\\r(\001\d+)\{Q\1\}/\006Q̊\006/gs;
	s/\\r(\001\d+)\{S\1\}/\006S̊\006/gs;
	s/\\r(\001\d+)\{U\1\}/\006Ů\006/gs;
	s/\\r(\001\d+)\{V\1\}/\006V̊\006/gs;
	s/\\r(\001\d+)\{W\1\}/\006W̊\006/gs;
	s/\\r(\001\d+)\{X\1\}/\006X̊\006/gs;
	s/\\r(\001\d+)\{Y\1\}/\006Y̊\006/gs;
	s/\\r(\001\d+)\{a\1\}/\006å\006/gs;
	s/\\r(\001\d+)\{d\1\}/\006d̊\006/gs;
	s/\\r(\001\d+)\{e\1\}/\006e̊\006/gs;
	s/\\r(\001\d+)\{g\1\}/\006g̊\006/gs;
	s/\\r(\001\d+)\{i\1\}/\006i̊\006/gs;
	s/\\r(\001\d+)\{j\1\}/\006j̊\006/gs;
	s/\\r(\001\d+)\{o\1\}/\006o̊\006/gs;
	s/\\r(\001\d+)\{q\1\}/\006q̊\006/gs;
	s/\\r(\001\d+)\{s\1\}/\006s̊\006/gs;
	s/\\r(\001\d+)\{u\1\}/\006ů\006/gs;
	s/\\r(\001\d+)\{v\1\}/\006v̊\006/gs;
	s/\\r(\001\d+)\{w\1\}/\006ẘ\006/gs;
	s/\\r(\001\d+)\{x\1\}/\006x̊\006/gs;
	s/\\r(\001\d+)\{y\1\}/\006ẙ\006/gs;

	# breve accent \u{x}
	s/\\u(\001\d+)\{A\1\}/\006Ă\006/gs;
	s/\\u(\001\d+)\{E\1\}/\006Ĕ\006/gs;
	s/\\u(\001\d+)\{G\1\}/\006Ğ\006/gs;
	s/\\u(\001\d+)\{I\1\}/\006Ĭ\006/gs;
	s/\\u(\001\d+)\{O\1\}/\006Ŏ\006/gs;
	s/\\u(\001\d+)\{U\1\}/\006Ŭ\006/gs;
	s/\\u(\001\d+)\{a\1\}/\006ă\006/gs;
	s/\\u(\001\d+)\{e\1\}/\006ĕ\006/gs;
	s/\\u(\001\d+)\{g\1\}/\006ğ\006/gs;
	s/\\u(\001\d+)\{i\1\}/\006ĭ\006/gs;
	s/\\u(\001\d+)\{o\1\}/\006ŏ\006/gs;
	s/\\u(\001\d+)\{u\1\}/\006ŭ\006/gs;

	# hacek/caron? accent \v{x}
	s/\\v(\001\d+)\{C\1\}/\006Č\006/gs;
	s/\\v(\001\d+)\{D\1\}/\006Ď\006/gs;
	s/\\v(\001\d+)\{E\1\}/\006Ě\006/gs;
	s/\\v(\001\d+)\{L\1\}/\006Ľ\006/gs;
	s/\\v(\001\d+)\{N\1\}/\006Ň\006/gs;
	s/\\v(\001\d+)\{R\1\}/\006Ř\006/gs;
	s/\\v(\001\d+)\{S\1\}/\006Š\006/gs;
	s/\\v(\001\d+)\{T\1\}/\006Ť\006/gs;
	s/\\v(\001\d+)\{Z\1\}/\006Ž\006/gs;
	s/\\v(\001\d+)\{c\1\}/\006č\006/gs;
	s/\\v(\001\d+)\{d\1\}/\006ď\006/gs;
	s/\\v(\001\d+)\{e\1\}/\006ě\006/gs;
	s/\\v(\001\d+)\{l\1\}/\006ľ\006/gs;
	s/\\v(\001\d+)\{n\1\}/\006ň\006/gs;
	s/\\v(\001\d+)\{r\1\}/\006ř\006/gs;
	s/\\v(\001\d+)\{s\1\}/\006š\006/gs;
	s/\\v(\001\d+)\{t\1\}/\006ť\006/gs;
	s/\\v(\001\d+)\{z\1\}/\006ž\006/gs;

	# macron \={x}
	s/\\\=(\001\d+)\{A\1\}/\006Ā\006/gs;
	s/\\\=(\001\d+)\{E\1\}/\006Ē\006/gs;
	s/\\\=(\001\d+)\{O\1\}/\006Ō\006/gs;
	s/\\\=(\001\d+)\{U\1\}/\006Ū\006/gs;
	s/\\\=(\001\d+)\{a\1\}/\006ā\006/gs;
	s/\\\=(\001\d+)\{e\1\}/\006ē\006/gs;
	s/\\\=(\001\d+)\{o\1\}/\006ō\006/gs;
	s/\\\=(\001\d+)\{u\1\}/\006ū\006/gs;

	# macron \=x
	s/\\\=A/\006Ā\006/gs;
	s/\\\=E/\006Ē\006/gs;
	s/\\\=O/\006Ō\006/gs;
	s/\\\=U/\006Ū\006/gs;
	s/\\\=a/\006ā\006/gs;
	s/\\\=e/\006ē\006/gs;
	s/\\\=o/\006ō\006/gs;
	s/\\\=u/\006ū\006/gs;

	# dot \.{x}
	s/\\\.(\001\d+)\{G\1\}/\006Ġ\006/gs;
	s/\\\.(\001\d+)\{L\1\}/\006Ŀ\006/gs;
	s/\\\.(\001\d+)\{Z\1\}/\006Ż\006/gs;
	s/\\\.(\001\d+)\{g\1\}/\006ġ\006/gs;
	s/\\\.(\001\d+)\{l\1\}/\006ŀ\006/gs;
	s/\\\.(\001\d+)\{z\1\}/\006ż\006/gs;

	# dot \.x
	s/\\\.G/\006Ġ\006/gs;
	s/\\\.L/\006Ŀ\006/gs;
	s/\\\.Z/\006Ż\006/gs;
	s/\\\.g/\006ġ\006/gs;
	s/\\\.l/\006ŀ\006/gs;
	s/\\\.z/\006ż\006/gs;

	# slashed l
	s/\\l\b/\006ł\006/gs;
	s/\\L\b/\006Ł\006/gs;

	# krouzek \accent23x or \accent'27
	s/\{\\accent2[37]\s*u\}/\006ů\006/gs;
	s/\\accent2[37]\s*u/\006ů\006/gs;

	# Other special characters.
	s/\\O\b\s*/\006Ø\006/gs;
	s/\\o\b\s*/\006ø\006/gs;
	s/\\AA\b\s*/\006Å\006/gs;
	s/\\aa\b\s*/\006å\006/gs;
	s/\\AE\b\s*/\006Æ\006/gs;
	s/\\ae\b\s*/\006æ\006/gs;
	s/\\OE\b\s*/\006Œ\006/gs;
	s/\\oe\b\s*/\006œ\006/gs;
	s/\\ss\b\s*/\006ß\006/gs;
	s/\\S\b\s*/\006§\006/gs;
	s/\\P\b\s*/\006¶\006/gs;
	s/\\pm\b\s*/\006±\006/gs;
	s/\\pounds\b\s*/\006£\006/gs;
	s/\?\`/\006¿\006/gs;
	s/\!\`/\006¡\006/gs;

	# en and em dashes
	# Try to be careful to not change the dashes in HTML comments
	# (<!-- comment -->) to &ndash;s.
	s/\-\-\-/\006—\006/gs;			# --- -> &#x2014
	s/([^\!])\-\-([^\>])/$1–$2/gs;	# -- -> &#x2013

	# Upper case Greek
	s/\\Alpha\b/\006Α\006/gs;
	s/\\Beta\b/\006Β\006/gs;
	s/\\Gamma\b/\006Γ\006/gs;
	s/\\Delta\b/\006Δ\006/gs;
	s/\\Epsilon\b/\006Ε\006/gs;
	s/\\Zeta\b/\006Ζ\006/gs;
	s/\\Eta\b/\006Η\006/gs;
	s/\\Theta\b/\006Θ\006/gs;
	s/\\Iota\b/\006Ι\006/gs;
	s/\\Kappa\b/\006Κ\006/gs;
	s/\\Lambda\b/\006Λ\006/gs;
	s/\\Mu\b/\006Μ\006/gs;
	s/\\Nu\b/\006Ν\006/gs;
	s/\\Xi\b/\006Ξ\006/gs;
	s/\\Omicron\b/\006Ο\006/gs;
	s/\\Pi\b/\006Π\006/gs;
	s/\\Rho\b/\006Ρ\006/gs;
	s/\\Sigma\b/\006Σ\006/gs;
	s/\\Tau\b/\006Τ\006/gs;
	s/\\Upsilon\b/\006Υ\006/gs;
	s/\\Phi\b/\006Φ\006/gs;
	s/\\Chi\b/\006Χ\006/gs;
	s/\\Psi\b/\006Ψ\006/gs;
	s/\\Omega\b/\006Ω\006/gs;

	# Lower case Greek
	s/\\alpha\b/\006α\006/gs;
	s/\\beta\b/\006β\006/gs;
	s/\\gamma\b/\006γ\006/gs;
	s/\\delta\b/\006δ\006/gs;
	s/\\varepsilon\b/\006ε\006/gs;
	s/\\epsilon\b/\006ε\006/gs;
	s/\\zeta\b/\006ζ\006/gs;
	s/\\eta\b/\006η\006/gs;
	s/\\theta\b/\006θ\006/gs;
	s/\\vartheta\b/\006θ\006/gs;
	s/\\iota\b/\006ι\006/gs;
	s/\\kappa\b/\006κ\006/gs;
	s/\\lambda\b/\006λ\006/gs;
	s/\\mu\b/\006μ\006/gs;
	s/\\nu\b/\006ν\006/gs;
	s/\\xi\b/\006ξ\006/gs;
	s/\\omicron\b/\006ο\006/gs;
	s/\\pi\b/\006π\006/gs;
	s/\\varpi\b/\006π\006/gs;
	s/\\rho\b/\006ρ\006/gs;
	s/\\varrho\b/\006ρ\006/gs;
	s/\\sigma\b/\006σ\006/gs;
	s/\\varsigma\b/\006ς\006/gs;
	s/\\tau\b/\006τ\006/gs;
	s/\\upsilon\b/\006υ\006/gs;
	s/\\phi\b/\006φ\006/gs;
	s/\\varphi\b/\006φ\006/gs;
	s/\\chi\b/\006χ\006/gs;
	s/\\psi\b/\006ψ\006/gs;
	s/\\omega\b/\006ω\006/gs;

	# Now allow characters to come together
	s/\006//gs;
}

$opt_B = 'bibtex' unless defined($opt_B);

# Prevent "identifier used only once" warnings.
$opt_a = $opt_b = $opt_c = $opt_D = $opt_d = $opt_e = $opt_h = $opt_m =
$opt_n = $opt_r = $opt_R = $opt_i = $opt_k = $opt_s = $opt_t = $opt_v =
$opt_u = $opt_U = undef;

$macrofile = '';

$command_line = &html_encode(join(' ', $0, @ARGV));

getopts("aB:b:cd:D:e:h:ikm:n:rRs:tuUv") || &usage;

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
binmode(HTMLFILE, ":encoding(UTF-8)") if ($opt_u);
if (defined($htmlfile) && open(OHTMLFILE, "$htmlfile")) {
    binmode(OHTMLFILE, ":encoding(UTF-8)") if ($opt_u);
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
<meta name="Generator" content="http://www.spinellis.gr/sw/textproc/bib2xhtml/" />
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
    last loop if m/^$beginstring\s*$/;
  }
 loop:
  while (<OHTMLFILE>) {
    print HTMLFILE;
    last loop if m/^$endstring\s*$/;
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
	print AUXFILE $_ if (m/^\\(citation|bibdata)\{/);
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

# We redirect bibtex's stdout to stderr.
# This is needed when bib2xhtml is generating its output on the
# standard output.
$opt_b = '' unless defined($opt_b);
system("$opt_B $opt_b $auxfile 1>&2");

$beginstring = "<!-- BEGIN BIBLIOGRAPHY $delimiter -->";
$endstring = "<!-- END BIBLIOGRAPHY $delimiter -->";

if ($updating) {
loop:
    while (<OHTMLFILE>) {
	last loop if m/^$beginstring\s*$/;
	print HTMLFILE;
    }
loop:
    while (<OHTMLFILE>) {
	last loop if m/^$endstring\s*$/;
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
	open(BBLFILE, "<:crlf", $t) || die "error opening $t: $!\n";
	while (<BBLFILE>) {
		($bcite, $blabel) = m+name=\"([^\"]*)\">\[([^\]]*)\]</a></dt><dd>+;
		if ($bcite) {
			$ntotent++;
		}
	}
	close(BBLFILE);
}
open(BBLFILE, "<:crlf", $t) || die "error opening $t: $!\n";
binmode(BBLFILE, ":encoding(UTF-8)") if ($opt_U);
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
    print HTMLFILE "$nentry references, last updated " . localtime() . "<p />\n";
}

print HTMLFILE "<$list_start>\n\n";

#foreach $key (sort (keys(%bibcite))) {
#    print "$key : $bibcite{$key}\n";
#}

open(BBLFILE, "<:crlf", $t) || die "error opening $t: $!\n";
binmode(BBLFILE, ":encoding(UTF-8)") if ($opt_U);
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
	s/([\{\}])/join("","\001",($1 eq "\{" ? $z[$l++]=$c++ : $l > 0 ? $z[--$l] : $1),$1)/ge;
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

    utf_ent();
    if (!$opt_u) {
	# Convert non-ASCII characters into numbered HTML entities
	s/([[:^ascii:]])/sprintf('&#x%x;', ord($1))/gse;
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

    s/\\textsuperscript(\001\d+)\{(.*)\1\}/<sup>$2<\/sup>/gs; # \textsuperscript{text} -> <sup>text<\/sup>

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
    s/(\001\d+)\{\\sf\s+(.*)\1\}/<font face="serif">$2<\/font>/gs; # {\sf text} -> <font face="serif">text</font>

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
