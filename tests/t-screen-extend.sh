#!/bin/sh
# screen-extend: the layout each placement gives, from probes derived
# from a real docked one (tests/data/xrandr-docked.txt: eDP-1 1920x1200
# below DP-1 2560x1440, primary), undocking, the read-back and retry, and
# the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export XRANDR_LOG="$tmp/xrandr.log" XRANDR_PROBES_SEEN="$tmp/seen" \
    TMPDIR="$tmp/scratch" SCREEN_EXTEND_SETTLE=0
mkdir -p "$TMPDIR" "$tmp/p"
docked=$top/tests/data/xrandr-docked.txt

# probe NAME EXT INT — the docked probe with DP-1 at EXT and eDP-1 at INT
# (WxH+X+Y, or "off"), written to $tmp/p/NAME
probe() {
    sed -e "s/^DP-1 connected primary [0-9x+]* /DP-1 connected primary $2 /" \
        -e "s/^eDP-1 connected [0-9x+]* /eDP-1 connected $3 /" \
        -e 's/ off (/ (/' "$docked" > "$tmp/p/$1"
}
# probes FILE... — what successive --query calls answer
probes() {
    XRANDR_PROBES=$*
    export XRANDR_PROBES
    rm -f -- "$XRANDR_PROBES_SEEN"
}
se() {
    : > "$XRANDR_LOG"
    run screen-extend "$@"
}
called() {
    cat -- "$XRANDR_LOG"
}

probes "$docked"
se -n
check_rc 0 "docked, dry run: succeeds"
check_eq "$out" "xrandr --output DP-1 --mode 2560x1440 --pos 0x0 --primary --output eDP-1 --mode 1920x1200 --pos 0x1440" \
    "default: the external primary at its preferred mode, the panel below"
check_eq "$(called)" "" "dry run: xrandr is only asked, never told"
probes "$docked"
se
check_rc 0 "docked, for real: succeeds"
check_eq "$(called)" "--output DP-1 --mode 2560x1440 --pos 0x0 --primary --output eDP-1 --mode 1920x1200 --pos 0x1440" \
    "for real: the same call, once, since the read-back matches"
check_eq "$(cat "$XRANDR_PROBES_SEEN")" 3 "probed, probed again after settling, then read back"
check_eq "$(ls -A "$TMPDIR")" "" "no temporary probe is left behind"

probe above 2560x1440+0+1200 1920x1200+0+0
probes "$docked" "$docked" "$tmp/p/above"
se -p above
check_rc 0 "-p above: succeeds"
check_eq "$(called)" "--output DP-1 --mode 2560x1440 --pos 0x1200 --primary --output eDP-1 --mode 1920x1200 --pos 0x0" \
    "-p above: the external pushed down by the panel's height"
probes "$docked"
se -n -p left
check_in "$out" "--output DP-1 --mode 2560x1440 --pos 1920x0 --primary --output eDP-1 --mode 1920x1200 --pos 0x0" \
    "-p left: the external pushed right by the panel's width"
se -n -p right
check_in "$out" "--output eDP-1 --mode 1920x1200 --pos 2560x0" "-p right: the panel right of the external"
se -n -p off
check_eq "$out" "xrandr --output DP-1 --mode 2560x1440 --pos 0x0 --primary --output eDP-1 --off" \
    "-p off: the panel off"
se -n -m 1920x1080
check_eq "$out" "xrandr --output DP-1 --mode 1920x1080 --pos 0x0 --primary --output eDP-1 --mode 1920x1200 --pos 0x1080" \
    "-m: the external at that mode, the panel below its height"
se -n -m 1366x768
check_rc 1 "-m a mode the external lacks: exit 1"
check_in "$err" "DP-1: does not list 1366x768" "-m a mode the external lacks: said so"
se -n -o DP-1 -i eDP-1
check_in "$out" "--output DP-1 --mode 2560x1440 --pos 0x0 --primary" "-o and -i name the outputs"

# a request the dock dropped once, then one it never takes
probes "$docked" "$docked" "$docked" "$tmp/p/above"
se -v -p above
check_rc 0 "dropped once: succeeds on the second attempt"
check_in "$err" "layout not applied (attempt 1)" "dropped once: said so with -v"
check_eq "$(grep -c . "$XRANDR_LOG")" 2 "dropped once: applied twice"
probes "$docked"
se -p above
check_rc 1 "never taken: exit 1"
check_in "$err" "the layout would not stick after 3 attempts" "never taken: said so"
check_eq "$(grep -c . "$XRANDR_LOG")" 3 "never taken: three attempts"

# undocked: DP-1 gone but still holding its geometry
sed 's/^DP-1 connected primary /DP-1 disconnected /' "$docked" > "$tmp/p/undocked"
probes "$tmp/p/undocked"
se -n
check_rc 0 "undocked: succeeds"
check_eq "$out" "xrandr --output eDP-1 --mode 1920x1200 --pos 0x0 --primary --output DP-1 --off" \
    "undocked: the panel alone and primary, the stale output off"
se -n -m 2560x1440
check_rc 1 "undocked with -m: exit 1, nothing to set to it"

sed 's/^HDMI-1 disconnected /HDMI-1 connected /' "$docked" > "$tmp/p/extra"
probes "$tmp/p/extra"
se -n
check_in "$out" "--output HDMI-1 --off" "a third connected output is turned off"
check_in "$out" "--output DP-1 --mode 2560x1440 --pos 0x0 --primary" \
    "a connected output listing no mode is passed over for the external"
awk '{ print } /^HDMI-1 connected/ { print "   1920x1080     60.00 +" }' \
    "$tmp/p/extra" > "$tmp/p/extra-modes"
probes "$tmp/p/extra-modes"
se -n
check_in "$out" "--output HDMI-1 --mode 1920x1080 --pos 0x0 --primary" \
    "one that lists modes: the first other connected output is the external"
check_in "$out" "--output DP-1 --off" "and the one after it is turned off"

awk '/^eDP-1 / { skip = 1; next } /^[^ ]/ { skip = 0 } !skip' "$docked" \
    > "$tmp/p/desktop"
probes "$tmp/p/desktop"
se -n
check_eq "$out" "xrandr --output DP-1 --mode 2560x1440 --pos 0x0 --primary" \
    "no internal panel: the external alone"

probes "$docked"
se -n -o HDMI-1
check_rc 1 "-o not connected: exit 1"
se -n -i LVDS-1
check_rc 1 "-i not connected: exit 1"
se -n -o eDP-1
check_rc 1 "-o naming the internal panel: exit 1"
check_in "$err" "is the internal panel" "-o naming the internal panel: said so"
export XRANDR_EXIT=1
se -n
unset XRANDR_EXIT
check_rc 1 "xrandr --query fails: exit 1"

for args in '-m a1x1b' '-m 1920x' '-p sideways' 'extra' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    se $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(called)" "" "refuses [$args]: xrandr not told anything"
done
for settle in soon . 1.2.3; do
    export SCREEN_EXTEND_SETTLE=$settle
    se
    check_rc 2 "SCREEN_EXTEND_SETTLE=$settle: a usage error"
done
export SCREEN_EXTEND_SETTLE=0
run screen-extend -h
check_rc 0 "-h: help"

finish
