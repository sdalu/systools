# Install the scripts of bin/ and their support files of lib/systools/
# under PREFIX, keeping the bin/../lib/systools layout they rely on.
# Works with both BSD make and GNU make.

PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
LIBDIR  = $(PREFIX)/lib/systools

.PHONY: all install uninstall link unlink check

all: check

install:
	install -d $(DESTDIR)$(BINDIR)
	[ ! -d lib/systools ] || install -d $(DESTDIR)$(LIBDIR)
	install -m 755 bin/* $(DESTDIR)$(BINDIR)
	if [ -d lib/systools ]; then \
	    install -m 644 lib/systools/* $(DESTDIR)$(LIBDIR); \
	fi

uninstall:
	for f in bin/*; do rm -f $(DESTDIR)$(BINDIR)/$${f##*/}; done
	rm -rf $(DESTDIR)$(LIBDIR)

# Development: symlink the scripts in place, e.g. make link PREFIX=$HOME
link:
	install -d $(BINDIR)
	for f in "$$(pwd)"/bin/*; do ln -sf "$$f" $(BINDIR)/; done

unlink:
	for f in bin/*; do [ -L $(BINDIR)/$${f##*/} ] && rm -f $(BINDIR)/$${f##*/}; done; true

check:
	@for f in bin/*; do \
	    case "$$(head -n 1 $$f)" in \
	    *ruby*) ruby -wc $$f > /dev/null ;; \
	    *sh*)   sh -n $$f ;; \
	    *)      echo "$$f: unknown interpreter" >&2; false ;; \
	    esac || exit 1; \
	done
