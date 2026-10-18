# systools

Small system tools, written in POSIX sh, that behave the same on FreeBSD
and on Linux. They run from `bin/` as they are, from a symlink, or
installed under a prefix; there is nothing to build.


## The tools

| Tool | What it does | Needs |
|---|---|---|
| `compositor-picom` | run picom at an effect level -- tear, light or full -- remembered for the next login, refusing a software-rendered X server | `picom`; `glxinfo` to check the renderer |
| `default-gateway` | print the gateway of the default route, IPv4 or IPv6, in a given FIB or table; a route with no gateway prints its interface | `route` (FreeBSD), `ip` (Linux) |
| `do-screenshot` | screenshot the X11 desktop, a mouse-picked area or the active window (now or after a countdown) to a dated PNG, copied to the clipboard and announced; without a mode, a rofi menu asks | `maim`; `xdotool` for a window; `xclip`, `notify-send` and `rofi` when present |
| `is-docked` | tell whether a laptop sits in its dock: on external power, with a USB network interface, and with an external screen | `sysctl` and `ifconfig`, with drm-kmod for the screen (else `xrandr` under X) on FreeBSD; sysfs only on Linux |
| `low-priority` | run a command at the lowest priority the system allows | `nice`; `idprio` (FreeBSD) or `chrt` and `ionice` (Linux), used when present and permitted |
| `openwrt-acl` | manage the MAC accept-list of an OpenWrt SSID over ssh | `ssh` to the router; `uci`, `ubus`, `jsonfilter` and `iw` on it |
| `pdf2jpg` | turn PDF pages into JPEGs at a pixel size, optionally under a byte cap per page, each stage done by the tool best at it | `pdftoppm`; `magick` to downsample; `cjpeg` (mozjpeg best) or `magick` to encode; `gs` for `-e gs` |
| `pushover` | send a [Pushover](https://pushover.net/api) notification, tokens read from `~/.pushover` | `curl` |
| `qr` | encode text as a QR code, drawn in the terminal or written as SVG, PNG, EPS or XPM | `qrencode` (4.1 or later, for its SVG options) |
| `screen-mirror` | mirror one X11 output onto the others, at the largest mode they share, or scaled; `-x` undoes it | `xrandr` |
| `shrinkpdf` | make a PDF smaller by recompressing it with Ghostscript; the original is passed through when the result is not smaller | `gs` |
| `term-title` | set the terminal's window title or icon name (the window name under screen and tmux), or run a command under its own title and restore the old one | a terminal that speaks xterm's title sequences, or screen or tmux |
| `transcribe` | transcribe audio with Whisper on OVHcloud AI Endpoints, announcing the duration and cost first | `curl`; `ffmpeg` and `ffprobe` to resample and measure, when present |
| `vocalise` | speak text: OVHcloud's Riva voices, or piper and espeak-ng locally, to a file or to the speakers | `curl` for Riva; `piper` or `espeak-ng` offline; `ffmpeg` (or `lame`, `oggenc`, `opusenc`, `flac`) for anything but WAV |
| `vorbisedit` | edit the comments of an Ogg Vorbis file in `$VISUAL`, written back only when changed | `vorbiscomment` (vorbis-tools) |
| `vpn-status` | list the VPN tunnels that are up, one word each, marking a WireGuard tunnel that no longer answers; `-p` for polybar | `ifconfig` (FreeBSD) or sysfs (Linux), `wg` for WireGuard |
| `where-am-i` | name the place this machine is at -- home, work, whatever the configuration says -- from the SSID of the Wi-Fi it is associated with; `unknown` otherwise | `ifconfig` (FreeBSD); `iw`, else `wpa_cli` (Linux) |
| `with-gnu-make` | run a command with GNU make exposed as `make`, and `cc` as `gcc` where there is none | `gmake` |
| `zfs-prune-snapshots` | destroy all but the newest N snapshots of datasets | `zfs` |
| `zfs-snapshot` | take today's dated snapshot of a dataset and expire old ones; meant to run once a day | `zfs` |

Each tool prints its usage with `-h`; the header comment at the top of
each script says the rest -- configuration, defaults, platform
differences. Options are short ones only (`-r`, not `--recursive`). Exit
status is 0 on success, 1 on failure and 2 on a usage error, except for
`low-priority`, `with-gnu-make` and `term-title -e`, which run a command
and return its own, `is-docked`, which answers with 0 (docked) or 1
(not), and `pdf2jpg`, which exits 3 when a page stays over its byte
cap.

Where a tool calls one kept in an sbin directory -- `zfs`, `route`,
`ip`, `ifconfig`, `sysctl`, `idprio` -- it adds those directories to the
end of `PATH`, so it also works on Linux from cron, whose `PATH` leaves
them out, and from an unprivileged account.


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

`make check` needs `shellcheck`; it also checks that the functions
`transcribe` and `vocalise` share are still the same in both. `make
tests` runs every tool against stand-ins in `tests/fake/` for `zfs`,
`curl`, `gs`, `ip`, `route`, `ssh`, `sysctl`, `ifconfig`, `xrandr`,
`qrencode`, `wg`, `ps`, `pdftoppm`, `magick`, `cjpeg`, `ffmpeg`,
`ffprobe`, `espeak-ng`, `picom`, `pgrep`, `pkill`, `glxinfo`, `maim`,
`xdotool`, `xclip`, `notify-send`, `rofi`, `vorbiscomment`, `iw`,
`wpa_cli`, `uname` and the priority tools, an editor (`edit-tags`), and
a sysfs tree for Linux, so it touches no pool, no network and no router,
and it takes the FreeBSD and the Linux branch of each tool on either
system. Each `tests/t-*.sh` names what it checks in its header and
prints one line per check.


## Known shortfalls

- `zfs-snapshot` expires only what fell due since the day before. A day
  the job did not run leaves that day's expiries undone;
  `zfs-snapshot -t YYYY-MM-DD dataset` replays it.
- `low-priority` gets the idle class on FreeBSD only for root, unless
  `security.bsd.unprivileged_idprio=1`; otherwise it runs under plain
  `nice`. On Linux, `ionice -c 3` has an effect only with the BFQ or CFQ
  disk scheduler.
- `default-gateway` reports the first nexthop of a multipath route only.
- `is-docked` recognises the dock by what it provides, not by what it
  is: any USB network interface counts, and a dock whose network
  interface is PCIe over Thunderbolt does not.
- `openwrt-acl` defaults to the router `maxwell` and the SSID
  `rezo_zero`; set `OPENWRT_ACL_HOST` and `OPENWRT_ACL_SSID`, or use `-H`
  and `-s`.
- `screen-mirror` works under X11 only; a Wayland session has no
  `xrandr` to drive.
- `do-screenshot` works under X11 only, like `screen-mirror`. Its menu
  is rofi's plain dmenu, styled only by rofi's own configuration.
- `term-title` knows terminals by `TERM`; one outside its list is
  refused unless `-T` names the sequences to send. Restoring a title
  needs the terminal's title stack, which screen and tmux lack.
- `where-am-i` knows a place by its SSID alone, and an SSID is not
  unique: any network named like the one at home is home. The wired
  facts `-v` reports and the outside view of `external_view` are
  gathered for rules not yet written; no answer rests on them.
- `vpn-status` marks an idle WireGuard tunnel dead too: without traffic
  or `PersistentKeepalive`, a peer stops handshaking, and the mark cannot
  tell that silence from a peer that is gone.
- `vpn-status` on Linux needs root for two things: `wg` answers only
  root, so a dead WireGuard tunnel is not marked, and the owner of a tun
  device run by root is not visible, so it is labelled by its name.
- `vocalise`'s Linux audio outputs, pulse and alsa, are new and have
  not been tried on real hardware.
- `transcribe -f srt` and `-f vtt` are refused by the API today, with
  HTTP 400, though it advertises them.
- `pushover` reads only the two-level layout of `~/.pushover` its header
  shows, and accepts only tokens made of letters and digits.
- `vorbisedit` edits Ogg Vorbis only; an Opus file's tags need
  `opustags`.
- The suite covers the local half of `openwrt-acl`, not the script it
  runs on the router, not `with-gnu-make`'s `gcc` shim, not `qr`
  drawing in a terminal, and not `do-screenshot` without `rofi`,
  `xclip` or `notify-send`, nor `where-am-i` without `wpa_cli`, on a
  host that has them in its system directories (this one, and its
  Linux layer, which sees them there too). Nothing
  has been run under BusyBox.
