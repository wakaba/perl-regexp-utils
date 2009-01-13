POD2HTML = pod2html --css "http://suika.fam.cx/www/style/html/pod.css" \
  --htmlroot "../.."

all: Simple.html

Simple.html: Simple.pod
	$(POD2HTML) $< > $@

## License: Public Domain.
## $Date: 2009/01/13 14:15:44 $
