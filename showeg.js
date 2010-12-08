/*
 * Show the example file specified.
 *
 * $Id: \\dds\\src\\textproc\\bib2xhtml\\RCS\\showeg.js,v 1.1 2010/12/08 18:47:48 dds Exp $
 */

function showBib(form) {
	for(i = 0; i < form.style.length; i++)
		if( form.style[i].checked)
			style = form.style[i].value;
	if ((style == 'empty' ||
	     style == 'paragraph' ||
	     style == 'unsortlist') &&
	     form.append.checked) {
		alert ('The specified style does not support the display of BibTeX keys');
		return;
	}
	if ((style == 'unsort' || style == 'unsortlist') &&
	    (form.chrono.checked || form.reverse.checked)) {
		alert ('Unsorted styles do not support a sort specification');
		return;
	}
	open('eg/' +
		style +
		(form.name.checked ? form.name.value : '') +
		(form.unicode.checked ? form.unicode.value : '') +
		(form.chrono.checked ? form.chrono.value : '') +
		(form.reverse.checked ? form.reverse.value : '') +
		(form.append.checked ? form.append.value : '') +
		'.html'
	);
}
