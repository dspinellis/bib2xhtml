#
# $Id: \\dds\\src\\textproc\\bib2xhtml\\RCS\\Makefile,v 1.20 2010/12/08 10:47:38 dds Exp $
#

NAME=bib2xhtml
BINDIR=$(HOME)/bin/
BIBTEXDIR=$(HOME)/texmf/bibtex/bst/
CGIDIR=/usr/dcs/www/cgi-bin/
DISTDIR=/cygdrive/c/dds/pubs/web/home/sw/textproc/$(NAME)

BSTFILES=$(wildcard *.bst)
DOCFILES=$(NAME).html $(NAME).txt $(NAME).pdf index.html static.html showeg.js $(wildcard eg/*.html) example.bib
EGFILES=$(wildcard eg/*.html)
FILES=README COPYING $(NAME) ${BSTFILES} $(DOCFILES) $(EGFILES) bibsearch Makefile $(NAME).man ChangeLog html-btxbst.doc gen-bst
VERSION=$(shell ident $(NAME) | awk '/Id:/{print $$3; exit 0} ')

UXHOST=spiti
SSH=plink

default: $(DOCFILES) $(EGFILES) ${BSTFILES} syntax

dist: default $(NAME)-$(VERSION).tar.gz
	-mkdir -p $(DISTDIR)/eg 2>/dev/null
	cp $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION).zip $(DISTDIR)
	cp $(DOCFILES) $(DISTDIR)
	cp $(EGFILES) $(DISTDIR)/eg
	cp ChangeLog $(DISTDIR)/ChangeLog.txt
	sed -e "s/VERSION/${VERSION}/" index.html >${DISTDIR}/index.html

$(NAME)-$(VERSION).shar: $(FILES)
	gshar -s hull@cs.uiuc.edu $(FILES) > $@
	chmod 644 $@

$(NAME)-$(VERSION).tar.gz: $(FILES)
	-cmd /c "rd /s/q $(NAME)-$(VERSION)"
	mkdir $(NAME)-$(VERSION)
	cp ${FILES} $(NAME)-$(VERSION)
	tar czf $(NAME)-$(VERSION).tar.gz ${FILES:%=$(NAME)-$(VERSION)/%}
	zip -r  $(NAME)-$(VERSION).zip $(NAME)-$(VERSION)
	cmd /c "rd /s/q $(NAME)-$(VERSION)"

$(NAME).ps: $(NAME).man
	$(SSH) $(UXHOST) groff -man -Tps <$? > $@

$(NAME).txt: $(NAME).man
	$(SSH) $(UXHOST) groff -man -Tascii <$? | $(SSH) $(UXHOST) col -b > $@

$(NAME).pdf: $(NAME).ps
	cmd /c ps2pdf $? $@

$(NAME).html: $(NAME).man
	$(SSH) $(UXHOST) groff -mhtml -Thtml -man <$? | sed -e 's/&minus;/-/g;s/&bull;/\&#8226;/g' >$@

${BSTFILES} : html-btxbst.doc
	perl gen-bst

syntax: $(NAME) bibsearch
	-perl -w -c $(NAME) >syntax 2>&1
	-perl -T -w -c bibsearch >>syntax 2>&1
	-perl -w -c gen-bst >>syntax 2>&1

install:
	for i in *.bst; do\
	    install -m 644 $$i $(BIBTEXDIR);\
	done

example: Makefile bib2xhtml
	-rm -f eg/*.html
	cp v23n5.pdf eg
	for style in empty plain alpha named unsort unsortlist paragraph ; \
	do \
		for n in '' '-n Spinellis' ; \
		do \
			nopt=`expr "$$n" : '\(..\)'` ;\
			for u in '' -u  ; \
			do \
				for c in '' -c  ; \
				do \
					for r in '' -r  ; \
					do \
						for k in '' -k  ; \
						do \
							perl bib2xhtml -s $$style $$n $$u $$c $$r $$k -h "Example: bib2xhtml -s $$style $$n $$u $$c $$r $$k" example.bib eg/$${style}$${nopt}$${u}$${c}$${r}$${k}.html ;\
						done ; \
					done ; \
				done ; \
			done ; \
		done ; \
	done
	touch example

# Regression test
test: example static.html
	cd eg ; \
	xml val -d /pub/schema/xhtml1-transitional.dtd index.html ;\
	xml val -d /pub/schema/xhtml1-transitional.dtd static.html ;\
	for i in *.html ; \
	do \
		xml val -d /pub/schema/xhtml1-transitional.dtd $$i 2>/dev/null ; \
		diff ../test.ok/$$i $$i ; \
	done

# Seed regression test files
seed: example
	-mkdir test.ok 2>/dev/null
	cp eg/* test.ok

static.html: index.html Makefile example
	(sed -n '1,/<meta/p' index.html ; \
	echo '</head><body><ul>' ; \
	grep '<title>' eg/* | sed 's/\([^:]*\):<title>Example: \(.*\)<\/title>/<li><a href="\1">\2<\/a><\/li>/' ; \
	echo '</ul></body></html>' ; \
	) >static.html
