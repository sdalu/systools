# systools

Small system tools, written in POSIX sh, that behave the same on FreeBSD
and on Linux. They run from `bin/` as they are, from a symlink, or
installed under a prefix; there is nothing to build.


## The tools

| Tool | What it does | Needs |
|---|---|---|
| `default-gateway` | print the gateway of the default route, IPv4 or IPv6, in a given FIB or table; a route with no gateway prints its interface | `route` (FreeBSD), `ip` (Linux) |
| `low-priority` | run a command at the lowest priority the system allows | `nice`; `idprio` (FreeBSD) or `chrt` and `ionice` (Linux), used when present and permitted |
| `openwrt-acl` | manage the MAC accept-list of an OpenWrt SSID over ssh | `ssh` to the router; `uci`, `ubus`, `jsonfilter` and `iw` on it |
| `pushover` | send a [Pushover](https://pushover.net/api) notification, tokens read from `~/.pushover` | `curl` |
| `shrinkpdf` | make a PDF smaller by recompressing it with Ghostscript; the original is passed through when the result is not smaller | `gs` |
| `with-gnu-make` | run a command with GNU make exposed as `make`, and `cc` as `gcc` where there is none | `gmake` |
| `zfs-prune-snapshots` | destroy all but the newest N snapshots of datasets | `zfs` |
| `zfs-snapshot` | take today's dated snapshot of a dataset and expire old ones; meant to run once a day | `zfs` |

Each tool prints its usage with `-h`; the header comment at the top of
each script says the rest -- configuration, defaults, platform
differences. Options are short ones only (`-r`, not `--recursive`). Exit
status is 0 on success, 1 on failure and 2 on a usage error, except for
`low-priority` and `with-gnu-make`, which run a command and return its
own.

Where a tool calls `zfs`, `route`, `ip` or `idprio`, it adds the sbin
directories they live in to the end of `PATH`, so it also works on Linux
from cron, whose `PATH` leaves them out, and from an unprivileged
account.


## Installing

```sh
make install                    # copies bin/* to /usr/local/bin
make install PREFIX=/opt DESTDIR=/tmp/stage
make install-links PREFIX=$HOME # symlinks into ~/bin, for working on them
make uninstall                  # or uninstall-links
```

Beyond `sh`, `awk`, `sed` and the usual utilities -- any POSIX awk will
do: FreeBSD's, gawk, mawk -- a tool needs only what its row above names.


## Testing

```sh
make check                      # preflight: every script parses and lints clean
make tests                      # the suite
make tests SH=dash              # the suite, with the scripts run under dash
```

`make check` needs `shellcheck`. `make tests` runs every tool against
stand-ins in `tests/fake/` for `zfs`, `curl`, `gs`, `ip`, `route`,
`ssh`, `uname` and the priority tools, so it touches no pool, no network
and no router, and it takes the FreeBSD and the Linux branch of each
tool on either system. Each `tests/t-*.sh` names what it checks in its
header and prints one line per check.


## Known shortfalls

- `zfs-snapshot` expires only what fell due since the day before. A day
  the job did not run leaves that day's expiries undone;
  `zfs-snapshot -t YYYY-MM-DD dataset` replays it.
- `low-priority` gets the idle class on FreeBSD only for root, unless
  `security.bsd.unprivileged_idprio=1`; otherwise it runs under plain
  `nice`. On Linux, `ionice -c 3` has an effect only with the BFQ or CFQ
  disk scheduler.
- `default-gateway` reports the first nexthop of a multipath route only.
- `openwrt-acl` defaults to the router `maxwell` and the SSID
  `rezo_zero`; set `OPENWRT_ACL_HOST` and `OPENWRT_ACL_SSID`, or use `-H`
  and `-s`.
- `pushover` reads only the two-level layout of `~/.pushover` its header
  shows, and accepts only tokens made of letters and digits.
- The suite covers the local half of `openwrt-acl`, not the script it
  runs on the router, and not `with-gnu-make`'s `gcc` shim. Nothing has
  been run under BusyBox.
