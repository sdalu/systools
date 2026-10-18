# FreeBSD port of systools

`sysutils/systools` installs every tool of `bin/` under `/usr/local/bin`
and its page under `/usr/local/share/man/man1`. It is kept in this tree
so that its plist follows the tools: `make check` fails as soon as a tool
or page is missing from it, or listed without existing
(`tests/check-port.sh`).

systools has no releases, so the port is a snapshot: it fetches the
GitHub tarball of one commit of `main` (`GH_TAGNAME`), and is versioned
by that commit's date (`DISTVERSION=gYYYYMMDD`, the ports' convention
for a snapshot). The commit pinned is never the one that changes the
port itself, which cannot name its own hash; it is the last one before
it, which holds every tool the port installs.


## Using it

Build and install straight from the checkout, against the system's
ports tree:

```sh
make -C ports/sysutils/systools install clean
```

or expose `ports/` as an overlay, so the checkout stays authoritative:

```sh
poudriere ports -c -m null -M /path/to/systools/ports -p systools-overlay
poudriere bulk -j <jail> -p default -O systools-overlay sysutils/systools
```


## The DAV option

On by default, it installs `caldav` and `carddav`, the two Ruby tools,
with `lang/ruby` (the tree's default, which must be 3.4 or later) and
`textproc/rubygem-nokogiri` as run dependencies; their shebang is
pointed at that Ruby by `USES=shebangfix`. Off, the package holds the sh
tools only, and depends on nothing.

The sh tools declare no dependency: each needs only what its own job is
about -- `zfs`, `xrandr`, `curl`, `qrencode` -- says so in its page and
in the README's table, and fails with a message when it is missing,
rather than the package pulling in X11 or Ghostscript for every user.


## Following the tree

Once the commits the port should carry are pushed to GitHub:

1. Set `GH_TAGNAME` to the newest pushed commit (`git rev-parse --short
   origin/main`), and `DISTVERSION` to `g` and that commit's date
   (`git log -1 --format=%cd --date=format:%Y%m%d origin/main`).
2. Regenerate `distinfo`, which fetches the tarball:

   ```sh
   make -C ports/sysutils/systools makesum
   ```
3. Check the result:

   ```sh
   cd ports/sysutils/systools
   make BATCH=1 NO_DEPENDS=1 stage check-plist stage-qa
   make BATCH=1 NO_DEPENDS=1 WITHOUT=DAV clean stage check-plist
   make BATCH=1 test          # make check and make tests, in the port
   portlint -AC
   ```

`BATCH=1` keeps a dependency's OPTIONS dialog from opening and hanging a
scripted build; `NO_DEPENDS=1` uses the Ruby already installed.
`portlint` warns that `LICENSE` is not defined: no licence is stated
upstream yet.
