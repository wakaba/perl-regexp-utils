P2H = ../../../local/p2h

all: build

build: Perl58.html JavaScript.html

Perl58.html JavaScript.html: %.html: %.pod $(P2H)
	$(P2H) "perl-regexp-utils" $< > $@

## License: Public Domain.
