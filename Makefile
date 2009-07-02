#
# $Id: \\dds\\src\\textproc\\bib2xhtml\\RCS\\Makefile,v 1.18 2009/07/02 13:28:14 dds Exp $
#

NAME=bib2xhtml
BINDIR=$(HOME)/bin/
BIBTEXDIR=$(HOME)/texmf/bibtex/bst/
CGIDIR=/usr/dcs/www/cgi-bin/
DISTDIR=/cygdrive/c/dds/pubs/web/home/sw/textproc/$(NAME)

BSTFILES=$(wildcard *.bst)
DOCFILES=$(NAME).html $(NAME).txt $(NAME).pdf index.html $(wildcard ex-*.html) example.bib
FILES=README COPYING $(NAME) ${BSTFILES} $(DOCFILES) bibsearch Makefile $(NAME).man ChangeLog html-btxbst.doc gen-bst
VERSION=$(shell ident $(NAME) | awk '/Id:/{print $$3; exit 0} ')

UXHOST=spiti
SSH=plink

default: $(DOCFILES) ${BSTFILES} syntax

dist: default $(NAME)-$(VERSION).tar.gz
	cp $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION).zip $(DISTDIR)
	cp $(DOCFILES) $(DISTDIR)
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
	./gen-bst

syntax: $(NAME) bibsearch
	-perl -w -c $(NAME) >syntax 2>&1
	-perl -T -w -c bibsearch >>syntax 2>&1
	-perl -w -c gen-bst >>syntax 2>&1

install:
	for i in *.bst; do\
	    install -m 644 $$i $(BIBTEXDIR);\
	done

example:
	-rm -f ex-*.html
	for i in empty plain alpha named unsort unsortlist ; \
	do \
		for j in "" -u ; \
		do \
			perl bib2xhtml $$j -s $$i -h "Example: bib2xhtml $$j -s $$i" example.bib ex-$${i}$${j}.html ;\
			case $$i in \
			unsort*) ;; \
			*) \
				perl bib2xhtml $$j -c -s $$i -h "Example: bib2xhtml $$j -c -s $$i" example.bib ex-$${i}-c$${j}.html ;\
				perl bib2xhtml $$j -r -s $$i -h "Example: bib2xhtml $$j -r -s $$i" example.bib ex-$${i}-r$${j}.html ;\
				perl bib2xhtml $$j -c -r -s $$i -h "Example: bib2xhtml $$j -c -r -s $$i" example.bib ex-$${i}-cr$${j}.html ;\
				;; \
			esac ;\
			case $$i in \
			empty) ;; \
			unsortlist) ;; \
			*) \
				perl bib2xhtml $$j -s $$i -k -h "Example: bib2xhtml $$j -s $$i -k" example.bib ex-$${i}$${j}-k.html ;\
				;; \
			esac ;\
		done ; \
	done

# Regression test
test:
	cd testdir ; \
	attrib -r \* ; \
	rm * ; \
	cp ../ex*.html ../*.bst ../example.bib ../bib2xhtml ../v23n5.pdf . ; \
	for i in empty plain alpha named unsort unsortlist ; \
	do \
		for j in "" -u ; \
		do \
			perl bib2xhtml $$j -s $$i -h "Example: bib2xhtml $$j -s $$i" example.bib ex-$${i}$${j}.html ;\
			case $$i in \
			unsort*) ;; \
			*) \
				perl bib2xhtml $$j -c -s $$i -h "Example: bib2xhtml $$j -c -s $$i" example.bib ex-$${i}-c$${j}.html ;\
				perl bib2xhtml $$j -r -s $$i -h "Example: bib2xhtml $$j -r -s $$i" example.bib ex-$${i}-r$${j}.html ;\
				perl bib2xhtml $$j -c -r -s $$i -h "Example: bib2xhtml $$j -c -r -s $$i" example.bib ex-$${i}-cr$${j}.html ;\
				;; \
			esac ;\
			case $$i in \
			empty) ;; \
			unsortlist) ;; \
			*) \
				perl bib2xhtml $$j -s $$i -k -h "Example: bib2xhtml $$j -s $$i -k" example.bib ex-$${i}$${j}-k.html ;\
				;; \
			esac ;\
		done ; \
	done ; \
	for i in *.html ; \
	do \
		xml val -d /pub/schema/xhtml1-transitional.dtd $$i 2>/dev/null ; \
		diff ../$$i $$i ; \
	done
