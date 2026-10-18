# Design

Why systools is shaped the way it is. What was tried and abandoned is in
`HISTORY.md`.


## POSIX sh, and nothing to install first

The tools run on whatever FreeBSD or Linux host needs them -- a file
server's cron, a laptop, a box with no compiler -- so they are written for
`/bin/sh` and the base utilities, and the only extra a tool needs is the
one its job is about (`zfs`, `curl`, `ssh`). A tool runs from `bin/` in
place; `make install` copies it, and `make install-links` symlinks it for
work on the tree. A script that ever needs shared code would find it at
`bin/../lib/systools/`, a layout `make install` reproduces under the
prefix; none does today.

Ruby was the alternative, and the reason it is not used is in the
history: an interpreter and gems on every host.


## Portability rules the scripts keep

One script, two userlands, and several shells (FreeBSD sh, dash, bash):

- **sbin on PATH.** A script that calls `zfs`, `route`, `ip` or `idprio`
  appends the sbin directories holding them to `PATH`. FreeBSD's cron
  and login `PATH` include sbin, but Debian's cron runs jobs with
  `/usr/bin:/bin` and its `/etc/profile` leaves sbin out for anyone but
  root. Appending, not prepending, keeps a caller's own choice first.
- **Dates by arithmetic, not by `date`.** Date math has no flag common to
  BSD `date` (`-v`) and GNU `date` (`-d`), and awk's `mktime` is gawk's
  alone. `zfs-snapshot` therefore converts between dates and day numbers
  in `$(( ))` (Howard Hinnant's civil-calendar algorithms) and asks
  `date` for nothing but today, `+%Y-%m-%d`.
- **Plain POSIX tools.** `uname -n`, not `hostname`, which minimal Linux
  installs leave out. `[ \t]` in awk regexes, not `[[:space:]]`, which
  mawk before 1.3.4 does not know.
- **No `VAR=value` before a function call.** POSIX leaves unspecified
  whether such an assignment reaches the function's commands, and
  FreeBSD sh does not export it. The assignment goes on the command
  inside the function (`MESSAGE=$1 awk ...`), or is exported.
- **`local`** is the one extension used: every target shell has it.


## low-priority: try a wrapper before using it

Each scheduling tool is first run on `true`; one that is missing or
refused is dropped and the command runs under what remains, down to plain
`nice`. Asking the tool is the only test that covers every reason it may
refuse -- a sysctl, root, a jail, a container's seccomp filter -- where
checking the sysctl and the uid would cover two of them.


## zfs-snapshot: what expires, and when

Run daily, it takes `dataset@YYYY-MM-DD`, then expires the snapshot from
a week ago unless that was a Sunday, and every snapshot six months old.
So weekday snapshots live a week and Sunday ones six months.

"Six months before" clamps the day to the target month (31 August minus
six months is 28 February), so consecutive days do not map to
consecutive days: 2026-02-28 maps to 2025-08-28 and 2026-03-01 to
2025-09-01. Each run therefore expires every date the six-month mark has
passed since the day before, not one date, and nothing falls between two
runs.

The snapshot comes first, and if it fails nothing expires, so an old
snapshot never goes before its replacement exists. A snapshot already
taken today is not an error, so a re-run is harmless. A destroy is tried
only for a snapshot that exists.


## zfs-prune-snapshots: one range per dataset

The snapshots of each dataset are listed newest first, and everything
from the oldest through the (N+1)-th newest goes in one
`zfs destroy dataset@%snapshot`. One call per dataset, rather than one
per snapshot, keeps a prune of hundreds of snapshots to one command and
one failure to report. With `-r`, every descendant is pruned as its own
dataset and keeps its own N.


## pushover: what reaches curl, and how

The tokens are written to curl's stdin as a config (`curl -K -`), so they
never appear in a process listing. Since they are written into quoted
config lines, a token must be letters and digits only; anything else is
refused rather than escaped. The message and title go as
`--data-urlencode name=value`, a form curl never reads as a file name --
unlike `-F`, which would upload `/etc/passwd` for a message starting with
`@/etc/passwd`.

`~/.pushover` is read by a small awk parser for the two-level
`section: / name: value` layout it uses, rather than through a YAML
library, which would bring back the interpreter the tools avoid.


## screen-mirror: one probe, then one xrandr call

Every question -- which outputs are connected, which is primary, what
modes each lists -- is answered from a single `xrandr --query` kept in a
temporary file, so all the answers describe the same instant; and the
whole change is then one `xrandr` call, so the screens never pass
through a half-applied layout. Why the largest common mode rather than
`--auto`, and when it scales instead, is in the script's header, next to
the code that does it.


## term-title: to the terminal, and back again

The sequences are written to `/dev/tty`, not to stdout, so a tool whose
output is redirected -- `term-title -e make > build.log` -- never puts
escape codes into the file; stdout is the fallback when there is no
terminal, and `-o` names a file outright. `-e` restores the previous
title from the terminal's own title stack (`CSI 22 t` to save,
`CSI 23 t` to restore) rather than from a title read back, because
reading a title back is a query most terminals refuse to answer. The
restore runs from the EXIT trap, so Ctrl-C restores too.


## vpn-status: dead is not the same as unknown

A WireGuard tunnel is marked dead when no peer has handshaken for three
minutes: a tunnel carrying traffic re-handshakes every two, and one set
with `PersistentKeepalive` never goes quiet. When
`wg` cannot be asked at all -- Linux answers only root -- the tunnel is
not marked: a status bar run as a user would otherwise show every tunnel
dead. The labels are what an operator already wrote down somewhere: the
interface description (or Linux alias), openconnect's `--authgroup`, the
server on a tun owner's command line, a peer's endpoint; nothing is kept
in a file of the script's own.


## transcribe and vocalise: one copy each, kept identical

Both talk to OVHcloud AI Endpoints and share their credential code: the
token lookup (environment, token file, `~/.authinfo`, aichat's config),
its hand-off to curl, and a few helpers. Every tool here is a single file
that runs on its own -- it can be copied to a server alone -- so rather
than a shared library each keeps a copy, and `make check-shared` fails as
soon as the copies differ. The token is written into a curl config line
between double quotes, where a quote or a backslash would end the value
early and leave the rest to be read as curl options, so a token outside a
bearer token's alphabet (RFC 6750) is refused rather than escaped.


## screen-extend: probe again, then check it took

`screen-mirror` asks once and changes everything in one call, so the
screens never pass through a half-applied layout. `screen-extend` keeps
the one call but not the one probe, because it runs at the moment a dock
is plugged in or wakes up, when its outputs are still appearing: it asks
twice, a settling second apart, and lays out from the second answer.
After the call it reads the layout back and compares every output's
geometry, and applies it again, up to three times, because a waking dock
can drop the request while xrandr still reports success.

The external output is the first other connected one that lists a mode,
not merely the first connected: a port that says connected but has no
EDID has nothing to drive, and choosing it would leave the real screen
dark. Positions are worked out and given explicitly rather than with
`--below` and the like, so the result does not depend on the mode an
output was left in.


## shrinkpdf: never worse than the input

Ghostscript writes to a temporary file, and only then is the smaller of
that and the input copied to the output, so a failed run leaves an
existing output as it was, and a "shrunk" file larger than the original
is never kept. The copy is `cat`, not `mv`: a new file gets the umask's
mode rather than the temporary file's 0600, and an existing one keeps its
own. Writing the output over the input is refused outright, symlinks
included, because Ghostscript would read the file it is truncating.
Ghostscript has no `--`, so an input named `-x.pdf` is passed as
`./-x.pdf`.


## is-docked: three signals, read where each system keeps them

A USB-C dock does not announce itself: nothing in the USB tree says
"dock", only the hubs and the network adapter it carries. So docked is
inferred from three things a dock provides at once -- external power, a
USB network interface, an external screen -- and each is read where the
system keeps it. FreeBSD has `hw.acpi.acline`, the `ue` interfaces every
USB ethernet driver attaches as, and the connector status drm-kmod
publishes as `sys.class.drm.card<N>-<connector>.status` sysctls, under
the names Linux uses. `drm_info` reads the same driver, so it adds a
dependency and nothing else -- and its outputs are a box-drawn tree, or
JSON that wants `jq`. `xrandr` remains for an X server whose driver is
not drm-kmod. Linux keeps all three in sysfs and needs no tool at all; a
USB power supply counts there, because a USB-C dock powers the laptop
over USB rather than through a Mains adapter. `acpi_dock(4)` was not
used: it covers only ACPI docking stations (`_DCK`), not USB-C docks.
Internal panels -- eDP, LVDS and DSI -- never count as the external
screen.


## do-screenshot: the mode is an argument, the menu a fallback

The `~/bin` script it replaces always went through a rofi menu wrapper
of the user's own (`~/.config/rofi/rofi-menu.sh`) and refused to start
without it. The mode is now an argument, so a key binding can name it
outright, and the menu is plain `rofi -dmenu`, asked only when no mode
is given. Only `maim` is required: the clipboard and the notification
are what follow a screenshot, not the screenshot itself, so without
`xclip` or `notify-send` it says what it skipped and still succeeds. A
capture that fails -- an area selection cancelled -- removes the file
maim may have left, so a failure never leaves an empty PNG behind.


## vorbisedit: write back only an edit that was made

The comments are written back only when the editor exits 0 and the file
differs from what was listed: `vorbiscomment -w` rewrites the whole Ogg
file, so an edit abandoned or a file opened and closed costs nothing.
Should that write fail, the temporary file holding the edit is kept and
named, rather than removed with the edit in it.


## where-am-i: places from the configuration, hooks kept for rules

The `~/bin` script it replaces named its places in a `case` and read
`wlan0` and `net0` by name. The places are now configuration, one
`place ssid` line each, because they are the user's facts and not the
tool's; the SSID is the rest of the line, as an SSID may hold spaces.
The wireless interfaces are found rather than named -- the wlan group
on FreeBSD, `/sys/class/net/*/wireless` on Linux -- and the first one
associated decides. `wired_facts` (the default route's interface, its
address, a lagg or bond's active port) and `external_view` (Mullvad's
view of the exit address) are kept although no rule reads them yet:
they are where a rule on the wired network or the exit point starts,
by the user's decision, and are not dead code to prune. `-v` reports
the wired facts so they are exercised; the outside view is not fetched
until a rule needs it, since it is a request to a third party.


## default-gateway: the route in use

It asks the routing table the way each system answers best --
`route -n get default` on FreeBSD, `ip route show default` on Linux --
and takes the first route listed, which is the one in use. A route
without a gateway (a tunnel) prints its interface in the gateway's
place, so the output always has the same columns. Linux omits the
`%interface` of a link-local gateway and FreeBSD includes it; it is
added, so the output is usable as is on both.


## The suite: stand-ins on PATH

`make tests` runs each tool unchanged, with `tests/fake/` first on
`PATH`. A stand-in records what it was asked and answers what the test
set up: `zfs` keeps a pool in a file, `uname` answers whichever platform
a test names, so both branches of a tool are tested on either system.
`tests/lib.sh` refuses to run if any stand-in does not resolve, because
the tool behind the missing one is the real `zfs`, which destroys
snapshots. Every refusal a tool makes is tested with the check that
nothing was touched beside it.
