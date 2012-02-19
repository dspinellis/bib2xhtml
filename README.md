# This is Free Software

The bib2html package is copyright 1996, David Hull.
In 2002, due to the lack of visible updates on the web, the program
was adopted for maintenance, distribution, and further evolution by
Diomidis Spinellis. Changes made by him include support for XHTML
1.0 and documentation bug fixes. The first public release of the
maintenance effort was in 2004 (version 2.1). On March 2004 the program
was renamed into bib2xhtml to avoid confusion with projects using the
name bib2html .

Changes Copyright 2002-2012, Diomidis Spinellis.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU GenerERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Softwre
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


# Important news for people who already use bib2html

The way that the bibsearch CGI script is called from HTML has changed
in bib2html-1.25.  Read the comments at the beginning of bibsearch
for the new calling conventions.


# Installation

* Update the first line of bib2xhtml and bibsearch to point to the
location of perl on your local machine.

* Install html-*.bst somewhere that bibtex can find them.  If you have
installed an earlier version of bib2xhtml, remove html.bst and
html-abs.bst.

* If you plan to use the bibsearch CGI script, edit the configuration
section at the beginning of it and install it in your http server's
cgi-bin directory.  The script has comments with instructions on how
to call it from another HTML page.

* If you want to modify the bst (bibtex style) files, edit
html-btxbst.doc and then run gen-bst to generate the new versions.
You probably won't need to, though.


# GNU emacs

For use with bibtex mode (available at
http://www.ida.ing.tu-bs.de/people/dirk/bibtex/),
I add the following to my ~/.emacs file:

    (setq bibtex-user-optional-fields
    '(("url" "URL link (for bib2xhtml)")
    ("postscript" "PostScript file (for bib2xhtml)")
    ("pdf" "PDF file (for bib2xhtml)"))
    ("dvi" "DVI file (for bib2xhtml))


# Thanks to these people, who have contributed to bib2html

Peter J Knaggs, Juergen Vollmer, Chris Torrence, Michael Sanders,
Vispi Bulsara, Nick Cropper, Joe Wells, Luis Mandel, Ricardo E. Gonzalez,
Daniel Kapitan, Tammy Kolda, Walter M. Lioen, Panos Louridas, Aki Vehtari,
Martin P. J. Zinser, Eric Vinck, Mark Jelasity, Vasek Smidl, Bruno Salvy,
Wilfried Elmenreich, Rogan Carr, Frank Loeffler, Todd Gamblin, Klaus Brunner.
