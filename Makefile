# systools -- small system tools in POSIX sh, for FreeBSD and Linux.
#
# Portable between GNU make and BSD make: no conditionals, no pattern
# rules, no GNU-only functions. Run `make help` for the targets and the
# variables you can override.
#
# The scripts of bin/ run where they are; install copies them under
# PREFIX, and anything a script ever loads from lib/systools/ goes to
# PREFIX/lib/systools, keeping the bin/../lib/systools layout they rely on.

NAME       = systools

PREFIX    ?= /usr/local
BINDIR     = $(PREFIX)/bin
MANDIR    ?= $(PREFIX)/share/man
LIBDIR     = $(PREFIX)/lib/systools
DESTDIR   ?=
INSTALL   ?= install
# The shell the scripts are run under by `tests` and `check-syntax`.
SH        ?= sh
SHELLCHECK?= shellcheck
MANDOC    ?= mandoc
RUBY      ?= ruby

.PHONY: help check check-syntax check-lint check-shared check-man tests \
	install uninstall install-links uninstall-links

# First target, so a bare `make` runs it. .DEFAULT_GOAL and .MAIN would
# each say so in one make only; being first says it in both.
help:						## show this help (the default)
	@echo '$(NAME) -- small system tools in POSIX sh, for FreeBSD and Linux'
	@echo ''
	@echo 'Targets:'
	@awk -F':.*## ' '/^[a-z][a-z0-9-]*:.*## /{ \
	    pre = sprintf("  %-16s ", $$1); n = split($$2, w, / /); line = ""; \
	    for (i = 1; i <= n; i++) { \
	        cand = (line == "" ? w[i] : line " " w[i]); \
	        if (length(pre) + length(cand) > 80 && line != "") { \
	            print pre line; pre = "                   "; line = w[i]; \
	        } else line = cand; \
	    } \
	    if (line != "") print pre line; \
	}' Makefile
	@echo ''
	@echo 'Variables (current value):'
	@printf '  %-16s %s\n' \
	    PREFIX     '$(PREFIX)' \
	    MANDIR     '$(MANDIR)  (the pages go in man1 under it)' \
	    DESTDIR    '$(DESTDIR)  (staging prefix for packaging)' \
	    SH         '$(SH)  (the shell tests run the scripts under, e.g. dash)' \
	    SHELLCHECK '$(SHELLCHECK)' \
	    MANDOC     '$(MANDOC)' \
	    RUBY       '$(RUBY)  (caldav and carddav: 3.4 or later, with nokogiri)'
	@echo ''
	@echo 'There is no build target: the scripts run from bin/ as they are.'

check: check-syntax check-lint check-shared check-man	## preflight: every script parses, lints clean, shares one copy, has its page
# The Ruby tools (caldav, carddav) are told apart by their shebang: they
# are parsed by $(RUBY) -wc, a warning counting as a failure, and left
# out of shellcheck.  Without ruby they are skipped, and make says so.
check-syntax:					## every script and test parses: sh ones under SH, Ruby ones under ruby -w
	@for f in bin/* tests/*.sh tests/fake/* tests/*.rb; do \
	    case $$f in *.rb) first=ruby ;; *) first=$$(sed -n 1p "$$f") ;; esac; \
	    case $$first in \
	    *ruby*) \
	        if ! command -v $(RUBY) > /dev/null; then \
	            echo "make: $(RUBY) not found; $$f not checked" >&2; \
	            continue; \
	        fi; \
	        warnings=$$($(RUBY) -wc "$$f" 2>&1 > /dev/null) && \
	            [ -z "$$warnings" ] || \
	            { echo "make: $$f: $$warnings" >&2; exit 1; } ;; \
	    *) $(SH) -n "$$f" || { echo "make: $$f does not parse" >&2; exit 1; } ;; \
	    esac; \
	done
check-lint:					## shellcheck finds nothing in the sh scripts or the tests
	@command -v $(SHELLCHECK) > /dev/null || \
	    { echo 'make: $(SHELLCHECK) not found (pkg install hs-ShellCheck)' >&2; \
	      exit 1; }
	@$(SHELLCHECK) -x $$(for f in bin/*; do \
	    case $$(sed -n 1p "$$f") in *ruby*) ;; *) echo "$$f" ;; esac; \
	done) tests/*.sh tests/fake/*

check-shared:					## transcribe and vocalise still share the same functions
	@sh tests/check-shared.sh

check-man:					## every tool has a man page, well-formed mdoc offering exactly its options
	@command -v $(MANDOC) > /dev/null || \
	    { echo 'make: $(MANDOC) not found (in FreeBSD base; apt install mandoc)' >&2; \
	      exit 1; }
	@MANDOC='$(MANDOC)' sh tests/check-man.sh

tests:						## run the suite: every script, against stand-ins, under SH
	@SH='$(SH)' sh tests/run.sh

install:					## copy the scripts, their man pages (and lib/systools, if any) under PREFIX
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)/man1
	$(INSTALL) -m 755 bin/* $(DESTDIR)$(BINDIR)
	$(INSTALL) -m 644 man/*.1 $(DESTDIR)$(MANDIR)/man1
	if [ -d lib/systools ]; then \
	    $(INSTALL) -d $(DESTDIR)$(LIBDIR) && \
	    $(INSTALL) -m 644 lib/systools/* $(DESTDIR)$(LIBDIR); \
	fi

uninstall:					## remove what install put down
	for f in bin/*; do rm -f "$(DESTDIR)$(BINDIR)/$${f##*/}"; done
	for f in man/*.1; do rm -f "$(DESTDIR)$(MANDIR)/man1/$${f##*/}"; done
	if [ -d lib/systools ]; then \
	    for f in lib/systools/*; do rm -f "$(DESTDIR)$(LIBDIR)/$${f##*/}"; done; \
	    [ ! -d $(DESTDIR)$(LIBDIR) ] || rmdir $(DESTDIR)$(LIBDIR); \
	fi

install-links:					## symlink the scripts and pages under PREFIX instead (development); install does not
	$(INSTALL) -d $(BINDIR) $(MANDIR)/man1
	for f in "$$(pwd)"/bin/*; do ln -sf "$$f" $(BINDIR)/; done
	for f in "$$(pwd)"/man/*.1; do ln -sf "$$f" $(MANDIR)/man1/; done

uninstall-links:				## remove the symlinks install-links made, and nothing else
	for f in "$$(pwd)"/bin/* "$$(pwd)"/man/*.1; do \
	    case $$f in \
	    *.1) l="$(MANDIR)/man1/$${f##*/}" ;; \
	    *) l="$(BINDIR)/$${f##*/}" ;; \
	    esac; \
	    if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$$f" ]; then rm -f "$$l"; fi; \
	done
