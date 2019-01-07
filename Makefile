#
# Makefile for generating the distribution
# This is written to run under Cygwin. YMMV

export NAME=bib2xhtml
BINDIR=$(HOME)/bin/
BIBTEXDIR=$(HOME)/texmf/bibtex/bst/
CGIDIR=/usr/dcs/www/cgi-bin/
DISTDIR=/cygdrive/c/dds/pubs/web/home/sw/textproc/$(NAME)

BSTFILES=\
	html-a.bst html-aa.bst html-ac.bst html-aca.bst html-acr.bst\
	html-acra.bst html-ar.bst html-ara.bst html-n.bst html-na.bst\
	html-nc.bst html-nca.bst html-ncr.bst html-ncra.bst html-nr.bst\
	html-nra.bst html-u.bst html-ua.bst

DOCFILES=$(NAME).html $(NAME).txt $(NAME).pdf index.html static.html showeg.js example.bib logo.jpeg
ROOTFILES=README.md COPYING ${BSTFILES} $(DOCFILES) bibsearch.pl Makefile $(NAME).man ChangeLog html-btxbst.doc gen-bst.pl $(NAME).pl
VERSION=$(shell git describe --tags --abbrev=4 HEAD)

default: $(DOCFILES) eg ${BSTFILES} syntax

dist: default $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION).zip
	-mkdir -p $(DISTDIR)/eg 2>/dev/null
	rm -f $(DISTDIR)/bib2xhtml-v*
	cp -f $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION).zip $(DISTDIR)
	cp -f $(DOCFILES) $(DISTDIR)
	cp -f eg/* $(DISTDIR)/eg
	cp -f ChangeLog $(DISTDIR)/ChangeLog.txt
	rm -f ${DISTDIR}/index.html
	sed -e "s/VERSION/${VERSION}/" index.html >${DISTDIR}/index.html

$(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION).zip: $(ROOTFILES) eg
	rm -rf $(NAME)-$(VERSION)
	mkdir -p $(NAME)-$(VERSION)/eg
	cp -f ${ROOTFILES} $(NAME)-$(VERSION)
	rm -f $(NAME)-$(VERSION)/index.html
	sed -e "s/VERSION/${VERSION}/" index.html >$(NAME)-$(VERSION)/index.html
	sed -e "s/@VERSION@/${VERSION}/" $(NAME).pl >$(NAME)-$(VERSION)/$(NAME)
	cp -f eg/* $(NAME)-$(VERSION)/eg
	tar czf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)
	zip -r  $(NAME)-$(VERSION).zip $(NAME)-$(VERSION)
	rm -rf $(NAME)-$(VERSION)

$(NAME).ps: $(NAME).man
	groff -man -Tps <$? > $@

$(NAME).txt: $(NAME).man
	groff -man -Tascii -P-c <$? | sed 's/.//g' >$@

$(NAME).pdf: $(NAME).ps
	ps2pdf $? $@

$(NAME).html: $(NAME).man
	groff -mhtml -Thtml -man <$? | sed -e 's/&minus;/-/g;s/&bull;/\&#8226;/g' >$@

${BSTFILES}: html-btxbst.doc
	perl gen-bst.pl

syntax: $(NAME).pl bibsearch.pl
	-perl -w -c $(NAME).pl >syntax 2>&1
	-perl -T -w -c bibsearch.pl >>syntax 2>&1
	-perl -w -c gen-bst.pl >>syntax 2>&1
	cat syntax

install:
	for i in *.bst; do\
	    install -m 644 $$i $(BIBTEXDIR);\
	done

# Create example files
# Some nonsensical option combinations cause bib2xhtml to exit with an error
# Hence the || true part
eg example: bib2xhtml.pl example.sh ${BSTFILES}
	mkdir -p eg
	-rm -f eg/*.html
	cp v23n5.pdf eg
	sh ./example.sh
	touch example

xhtml1-transitional.dtd:
	wget https://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd

# Regression test
test: example static.html xhtml1-transitional.dtd
	xmlstarlet val -d xhtml1-transitional.dtd index.html ;\
	xmlstarlet val -d xhtml1-transitional.dtd static.html ;\
	cd eg ; \
	for i in *.html ; \
	do \
		xmlstarlet val -d ../xhtml1-transitional.dtd $$i 2>/dev/null ; \
		../fold.sed $$i | diff -w ../test.ok/$$i - || exit 1 ; \
	done

# Seed regression test files
seed: example
	mkdir -p test.ok
	cd eg && for i in *.html ; do ../fold.sed $$i >../test.ok/$$i ; done

# Static HTML file version with links to the eg files
static.html: index.html Makefile example
	(sed -n '1,/<meta/p' index.html ; \
	echo '</head><body><ul>' ; \
	grep '<title>' eg/* | sed 's/\([^:]*\):<title>Example: \(.*\)<\/title>/<li><a href="\1">\2<\/a><\/li>/' ; \
	echo '</ul></body></html>' ; \
	) >static.html
