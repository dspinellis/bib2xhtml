#
# $Id: \\dds\\src\\textproc\\bib2xhtml\\RCS\\Makefile,v 1.4 2004/04/07 13:54:16 dds Exp $
#

NAME=bib2xhtml
BINDIR=$(HOME)/bin/
BIBTEXDIR=$(HOME)/texmf/bibtex/bst/
CGIDIR=/usr/dcs/www/cgi-bin/
DISTDIR=/dds/pubs/web/home/sw/textproc/$(NAME)

BSTFILES=html-a.bst html-aa.bst html-n.bst html-na.bst html-u.bst html-ua.bst html-nr.bst
DOCFILES=$(NAME).html $(NAME).txt $(NAME).pdf index.html $(wildcard ex-*.html)
FILES=README COPYING $(NAME) ${BSTFILES} $(DOCFILES) bibsearch Makefile $(NAME).man ChangeLog html-btxbst.doc gen-bst
VERSION=$(shell ident $(NAME) | awk '/Id:/{print $$3} ')

UXHOST=spiti
SSH=plink

default: $(DOCFILES) ${BSTFILES} syntax

dist: default $(NAME)-$(VERSION).tar.gz
	cp $(NAME)-$(VERSION).tar.gz $(DISTDIR)
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
	tar cf - ${FILES:%=$(NAME)-$(VERSION)/%} | gzip -c >$(NAME)-$(VERSION).tar.gz
	cmd /c "rd /s/q $(NAME)-$(VERSION)"

$(NAME).ps: $(NAME).man
	$(SSH) $(UXHOST) groff -man -Tps <$? > $@

$(NAME).txt: $(NAME).man
	$(SSH) $(UXHOST) groff -man -Tascii <$? | $(SSH) $(UXHOST) col -b > $@

$(NAME).pdf: $(NAME).ps
	ps2pdf $? $@

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
	for i in empty plain alpha named unsort unsortlist ; \
	do \
		perl bib2xhtml -s $$i -h "Example: bib2xhtml -s $$i" example.bib ex-$$i.html ;\
		case $$i in ; \
		unsort*) ;; \
		*) \
			perl bib2xhtml -c -s $$i -h "Example: bib2xhtml -c -s $$i" example.bib ex-$${i}-c.html ;\
			perl bib2xhtml -r -s $$i -h "Example: bib2xhtml -r -s $$i" example.bib ex-$${i}-r.html ;\
			perl bib2xhtml -c -r -s $$i -h "Example: bib2xhtml -c -r -s $$i" example.bib ex-$${i}-cr.html ;\
			;; \
		esac ;\
	done
