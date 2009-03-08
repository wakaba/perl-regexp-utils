POD2HTML = pod2html --css "http://suika.fam.cx/www/style/html/pod.css" \
  --htmlroot "../.."

all: Perl58.html JavaScript.html

Perl58.html JavaScript.html: %.html: %.pod
	$(POD2HTML) $< > $@

## License: Public Domain.
## $Date: 2009/03/08 14:30:51 $
