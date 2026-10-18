# Closing a round on systools

What has to be true before a unit of work here is done. Every line is a
command or a question with a yes or a no at the end of it.


## Gates

Run in order. A red gate is answered before anything else, and the
answer is sometimes that the checker is wrong rather than the file.

- [ ] `make check` -- preflight: every script and test parses (the
      Ruby ones, `caldav` and `carddav`, under `ruby -wc`, where a
      warning fails), shellcheck finds nothing in the sh ones, and every
      tool has a man page that lints clean and offers exactly the
      options it takes (its `getopts`, or its OptionParser).
- [ ] `make tests` -- the suite, the scripts under `sh`.
- [ ] `make tests SH=dash` -- **if this round touched a script and dash
      is at hand.** Debian's `/bin/sh` refuses what FreeBSD sh lets pass.
- [ ] `make check && make tests` under **both** makes -- **if this
      round touched the Makefile.** GNU make and BSD make.
- [ ] A new call to an external tool: does `tests/fake/` have its
      stand-in, and does the list in `tests/lib.sh` name it?
- [ ] A new refusal: is there a test feeding it the bad input, which
      also checks that nothing was touched?


## Documents

Re-read each against what this round changed: a document that was true
this morning is a claim, not a fact.

- [ ] The header comment of each script touched, its `usage()` and its
      page in `man/` -- do they still name exactly the options its
      `getopts` takes? `make check` holds the page's option letters to
      it, not what the page says they do: an option changes in three
      places or none. A new tool gets its page in the same commit.
- [ ] `README.md` -- does the table still list every tool in `bin/`,
      with what it needs? Is each known shortfall still short, and is a
      new one there?
- [ ] `DESIGN.md` -- did this round take a decision? Write it down,
      with the alternative it rejected and why, in the same commit.
- [ ] `HISTORY.md` -- did this round abandon an approach (add it, with
      what settled it), or remove what an entry explains (delete it)?
- [ ] `CLAUDE.md` -- only where things are, and a trap that cost this
      round time. Would the README or the code have answered it? Then it
      does not go there.


## Release

systools names no release of its own: there is no tag and no project
version.

- [ ] Does a script's own number move? `pushover`, `zfs-snapshot` and
      `zfs-prune-snapshots` print one with `-V`, held in their
      `readonly version=` line and nowhere else. A behaviour change to
      one of them bumps it there.
