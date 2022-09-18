P2H = ../../../local/p2h

all: build

build: Simple.html

Simple.html: Simple.pod $(P2H)
	$(P2H) "perl-regexp-utils" $< > $@

## License: Public Domain.
