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
LIBDIR     = $(PREFIX)/lib/systools
DESTDIR   ?=
INSTALL   ?= install
# The shell the scripts are run under by `tests` and `check-syntax`.
SH        ?= sh
SHELLCHECK?= shellcheck

.PHONY: help check check-syntax check-lint check-shared tests install uninstall \
	install-links uninstall-links

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
	    DESTDIR    '$(DESTDIR)  (staging prefix for packaging)' \
	    SH         '$(SH)  (the shell tests run the scripts under, e.g. dash)' \
	    SHELLCHECK '$(SHELLCHECK)'
	@echo ''
	@echo 'There is no build target: the scripts run from bin/ as they are.'

check: check-syntax check-lint check-shared	## preflight: every script parses, lints clean, shares one copy
check-syntax:					## every script and test parses under SH
	@for f in bin/* tests/*.sh tests/fake/*; do \
	    $(SH) -n "$$f" || { echo "make: $$f does not parse" >&2; exit 1; }; \
	done
check-lint:					## shellcheck finds nothing in the scripts or the tests
	@command -v $(SHELLCHECK) > /dev/null || \
	    { echo 'make: $(SHELLCHECK) not found (pkg install hs-ShellCheck)' >&2; \
	      exit 1; }
	@$(SHELLCHECK) -x bin/* tests/*.sh tests/fake/*

check-shared:					## transcribe and vocalise still share the same functions
	@sh tests/check-shared.sh

tests:						## run the suite: every script, against stand-ins, under SH
	@SH='$(SH)' sh tests/run.sh

install:					## copy the scripts (and lib/systools, if any) under PREFIX
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL) -m 755 bin/* $(DESTDIR)$(BINDIR)
	if [ -d lib/systools ]; then \
	    $(INSTALL) -d $(DESTDIR)$(LIBDIR) && \
	    $(INSTALL) -m 644 lib/systools/* $(DESTDIR)$(LIBDIR); \
	fi

uninstall:					## remove what install put down
	for f in bin/*; do rm -f "$(DESTDIR)$(BINDIR)/$${f##*/}"; done
	if [ -d lib/systools ]; then \
	    for f in lib/systools/*; do rm -f "$(DESTDIR)$(LIBDIR)/$${f##*/}"; done; \
	    [ ! -d $(DESTDIR)$(LIBDIR) ] || rmdir $(DESTDIR)$(LIBDIR); \
	fi

install-links:					## symlink the scripts under PREFIX instead (development); install does not
	$(INSTALL) -d $(BINDIR)
	for f in "$$(pwd)"/bin/*; do ln -sf "$$f" $(BINDIR)/; done

uninstall-links:				## remove the symlinks install-links made, and nothing else
	for f in "$$(pwd)"/bin/*; do \
	    l="$(BINDIR)/$${f##*/}"; \
	    if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$$f" ]; then rm -f "$$l"; fi; \
	done
