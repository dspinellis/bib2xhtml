#!/usr/bin/perl -p
#
# Add a URL field to books, based on their ISBN
#
#

BEGIN {
	do '/dds/pubs/web/bib/aws.pl' || die;
}

s/\-//g if (/ISBN\s*=\s*/i);
s@ISBN\s*=\s*["{](.*)["}]@'URL="http://www.amazon.com/dp/' . get_asin($1) . qq{/?tag=dds-20",\n\tISBN="$1"}@ie;
s/NewURL/URL/;
