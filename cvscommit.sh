#!/bin/sh
find -name ChangeLog | xargs cvs diff | grep "^\+" | sed -e "s/^\+//; s/^\+\+ .\//++ swe\//" > .cvslog.tmp
mkcommitfeed \
    --file-name doc/regexp-commit.en.atom.u8 \
    --feed-url http://suika.fam.cx/regexp/doc/regexp-commit \
    --feed-title "<http://suika.fam.cx/regexp/> ChangeLog diffs" \
    --feed-lang en \
    --feed-related-url "http://suika.fam.cx/regexp/doc/readme" \
    --feed-license-url "http://suika.fam.cx/regexp/doc/readme#license" \
    --feed-rights "This feed is free software; you can redistribute it and/or modify it under the same terms as Perl itself." \
    < .cvslog.tmp
cvs commit -F .cvslog.tmp $1 $2 $3 $4 $5 $6 $7 $8 $9 
rm .cvslog.tmp

## $Date: 2008/12/07 09:48:35 $
## License: Public Domain
