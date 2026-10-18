#!/bin/sh
# screen-mirror: the mode it picks and the xrandr call it makes, on a real
# docked probe (tests/data/xrandr-docked.txt: eDP-1 1920x1200, DP-1
# 2560x1440 primary) and on made-up ones, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export XRANDR_LOG="$tmp/xrandr.log" TMPDIR="$tmp/scratch"
mkdir -p "$TMPDIR"
docked=$(cat "$top/tests/data/xrandr-docked.txt")

# probe TEXT — what xrandr --query will answer
probe() {
    XRANDR_OUTPUT=$1
    export XRANDR_OUTPUT
    : > "$XRANDR_LOG"
}
called() {
    cat -- "$XRANDR_LOG"
}

probe "$docked"
run screen-mirror -n
check_rc 0 "dry run: succeeds"
check_eq "$out" "xrandr --output DP-1 --mode 1920x1200 --pos 0x0 --scale 1x1 --primary --output eDP-1 --mode 1920x1200 --scale 1x1 --same-as DP-1" \
    "default: the primary is the source, both at the largest common mode"
check_eq "$(called)" "" "dry run: xrandr is only asked, never told"

run screen-mirror
check_rc 0 "for real: succeeds"
check_eq "$(called)" "--output DP-1 --mode 1920x1200 --pos 0x0 --scale 1x1 --primary --output eDP-1 --mode 1920x1200 --scale 1x1 --same-as DP-1" \
    "for real: xrandr is told the same thing"
check_eq "$(ls -A "$TMPDIR")" "" "no temporary probe is left behind"

probe "$docked"
run screen-mirror -n -k
check_eq "$out" "xrandr --output DP-1 --mode 2560x1440 --pos 0x0 --scale 1x1 --primary --output eDP-1 --mode 1920x1200 --scale-from 2560x1440 --same-as DP-1" \
    "-k: the source keeps its mode, the target is scaled from it"

run screen-mirror -n -s eDP-1
check_in "$out" "--output eDP-1 --mode 1920x1200 --pos 0x0 --scale 1x1 --primary --output DP-1 --mode 1920x1200" \
    "-s: the named output is the source"

run screen-mirror -n -m 1280x720
check_in "$out" "--output DP-1 --mode 1280x720" "-m: the source at the forced mode"
check_in "$out" "--output eDP-1 --mode 1280x720" "-m: the target at the forced mode"
run screen-mirror -n -m 2560x1440
check_rc 1 "-m with a mode a target lacks: exit 1"
check_in "$err" "eDP-1: does not support 2560x1440" "-m with a mode a target lacks: said so"
run screen-mirror -n -m 1400x1050
check_rc 1 "-m with a mode the source lacks: exit 1"
check_in "$err" "DP-1: does not support 1400x1050" "-m with a mode the source lacks: said so"
run screen-mirror -n -k -m 1400x1050
check_rc 1 "-k -m with a mode the source lacks: exit 1"

run screen-mirror -n -x
check_eq "$out" "xrandr --output DP-1 --mode 2560x1440 --scale 1x1 --pos 0x0 --primary --output eDP-1 --off" \
    "-x: the source back to its preferred mode, the targets off"

run screen-mirror -l
check_rc 0 "-l: succeeds"
check_in "$out" "DP-1       2560x1440  2560x1440  17" "-l: an output's preferred, current and mode count"
check_in "$out" "common: 1920x1200 1920x1080 " "-l: the shared modes, widest first"

# A projector that prefers 1024x768: --auto would pick that.
probe 'Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal) 300mm x 190mm
   1920x1080     60.00*+
   1280x720      60.00
   1024x768      60.00
HDMI-1 connected (normal)
   1280x720      60.00
   1024x768      60.00 +
   800x600       60.00'
run screen-mirror -n
check_in "$out" "--output HDMI-1 --mode 1280x720" \
    "a projector preferring 1024x768 is mirrored at the largest common mode"

probe 'eDP-1 connected primary 1920x1200+0+0 (normal) 300mm x 190mm
   1920x1200     60.00*+
DP-1 connected (normal)
   1024x768      60.00 +'
run screen-mirror -n
check_rc 0 "no common mode: still mirrors"
check_in "$err" "no mode common to every output, scaling instead" "no common mode: said so"
check_in "$out" "--output DP-1 --mode 1024x768 --scale-from 1920x1200 --same-as eDP-1" \
    "no common mode: the target is scaled from the source"

probe 'eDP-1 connected primary 1920x1200+0+0 (normal)
   1920x1200     60.00*+
DP-1 disconnected (normal)'
run screen-mirror -n
check_rc 1 "a single output: exit 1"
check_in "$err" "nothing to mirror to" "a single output: said so"

probe "$docked"
run screen-mirror -n HDMI-1
check_rc 1 "a named target that is not connected: exit 1"
run screen-mirror -n DP-1
check_rc 1 "the source named as a target: exit 1"
check_in "$err" "DP-1: is the source" "the source named as a target: said so"
run screen-mirror -n -s HDMI-1
check_rc 1 "a source that is not connected: exit 1"

export XRANDR_EXIT=1
run screen-mirror -n
unset XRANDR_EXIT
check_rc 1 "xrandr --query fails: exit 1"

for args in '-m a1x1b' '-m 1920x' '-m x1080' '-m 1920x1080x2' '-m 1920' \
    '-l -x' '-l DP-1' '-x eDP-1' '-z'; do
    probe "$docked"
    # shellcheck disable=SC2086  # each case is a word list
    run screen-mirror $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(called)" "" "refuses [$args]: xrandr is not told anything"
done
run screen-mirror -h
check_rc 0 "-h: help"

finish
