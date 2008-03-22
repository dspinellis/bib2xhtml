#!/usr/bin/perl -p
#
# Add a URL field to books, based on their ISBN
#
# $Id: \\dds\\src\\textproc\\bib2xhtml\\RCS\\addurl.pl,v 1.1 2008/03/22 18:09:10 dds Exp $
#

BEGIN {
	do '/dds/pubs/web/bib/aws.pl' || die;
}

s/\-//g if (/ISBN\s*=\s*/i);
s@ISBN\s*=\s*["{](.*)["}]@'URL="http://www.amazon.com/dp/' . get_asin($1) . qq{/?tag=dds-20",\n\tISBN="$1"}@ie;
s/NewURL/URL/;
