BINDIR=$(HOME)/bin/
BIBTEXDIR=$(HOME)/texmf/bibtex/bst/
CGIDIR=/usr/dcs/www/cgi-bin/
FTPDIR=dist

FILES=README COPYING bib2html html*.bst bibsearch Makefile bib2html.man ChangeLog html-btxbst.doc gen-bst
VERSION=1.33

default: bib2html.man.html html-a.bst html-aa.bst html-n.bst html-na.bst html-u.bst html-ua.bst syntax

dist: default bib2html-$(VERSION).tar.gz bib2html-$(VERSION).shar
	install -m 644 bib2html-$(VERSION).tar.gz $(FTPDIR)
	install -m 644 bib2html-$(VERSION).shar $(FTPDIR)
dist: default $(NAME)-$(VERSION).tar.gz
bib2html-$(VERSION).shar: $(FILES)
	cp $(DOCFILES) $(DISTDIR)
	cp ChangeLog $(DISTDIR)/ChangeLog.txt
	sed -e "s/VERSION/${VERSION}/" index.html >${DISTDIR}/index.html
bib2html-$(VERSION).tar.gz: $(FILES)
	rm -f bib2html-$(VERSION).tar.gz
	ln -s . bib2html-$(VERSION)
	tar cf bib2html-$(VERSION).tar ${FILES:%=bib2html-$(VERSION)/%}
	rm bib2html-$(VERSION)
	gzip -9 bib2html-$(VERSION).tar
	chmod 644 bib2html-$(VERSION).tar.gz

bib2html.man.html: bib2html.man
	nroff -man bib2html.man | man2html -sun -title bib2html> bib2html.man.html
	chmod 644 bib2html.man.html
$(NAME).pdf: $(NAME).ps
html-a.bst html-aa.bst html-n.bst html-na.bst html-u.bst html-ua.bst html-nr.bst : html-btxbst.doc

$(NAME).html: $(NAME).man
syntax: bib2html bibsearch
	-perl -w -c bib2html >syntax 2>&1
${BSTFILES} : html-btxbst.doc
	./gen-bst

syntax: $(NAME) bibsearch
	-perl -w -c $(NAME) >syntax 2>&1
	-perl -T -w -c bibsearch >>syntax 2>&1
	-perl -w -c gen-bst >>syntax 2>&1
	install -m 755 bib2html $(BINDIR)
install:
	for i in *.bst; do\
	    install -m 644 $$i $(BIBTEXDIR);\
	done
	install -m 755 $(NAME) $