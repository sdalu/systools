#!/bin/sh
# compositor-picom: each level started with its own config and
# remembered only once it runs, start restoring it, this user's picom
# alone, the renderer check, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export XDG_CONFIG_HOME="$tmp/config" PICOM_LOG="$tmp/picom.log" \
    PICOM_STATE="$tmp/picom.running" PGREP_LOG="$tmp/pgrep.log" \
    GLXINFO_RENDERER='Mesa Intel(R) Graphics (MTL)'
conf=$XDG_CONFIG_HOME/picom
mkdir -p "$conf"
for level in tear light full; do
    printf '# %s\n' "$level" > "$conf/$level.conf"
done

cp_() {
    : > "$PICOM_LOG"
    : > "$PGREP_LOG"
    run compositor-picom "$@"
}
level() {
    cat -- "$conf/level" 2> /dev/null
}

cp_ full
check_rc 0 "full: succeeds"
check_eq "$(cat "$PICOM_LOG")" "-b --config $conf/full.conf" "full: picom in the background with full.conf"
check_eq "$(level)" full "full: remembered"
cp_ status
check_rc 0 "status, running: exit 0"
check_eq "$out" "running (level: full)" "status, running: the level"
check_in "$(cat "$PGREP_LOG")" "-x -u $(id -u) picom" "only this user's picom is looked for"

cp_ light
check_in "$(cat "$PGREP_LOG")" "-x -u $(id -u) picom" "a running picom is stopped first, this user's only"
check_eq "$(cat "$PICOM_LOG")" "-b --config $conf/light.conf" "light: restarted with light.conf"

cp_ off
check_rc 0 "off: succeeds"
if [ -e "$PICOM_STATE" ]; then
    fail "off: picom stopped"
else
    pass "off: picom stopped"
fi
check_eq "$(level)" off "off: remembered"
cp_ start
check_eq "$(cat "$PICOM_LOG")" "" "start after off: nothing started"
cp_ status
check_rc 1 "status, stopped: exit 1"
check_eq "$out" "not running (saved level: off)" "status, stopped: the saved level"

printf 'tear\n' > "$conf/level"
cp_ start
check_eq "$(cat "$PICOM_LOG")" "-b --config $conf/tear.conf" "start: the remembered level"
rm -f -- "$conf/level" "$PICOM_STATE"
cp_ start
check_eq "$(cat "$PICOM_LOG")" "-b --config $conf/light.conf" "start, nothing remembered: light"
printf 'garbage\n' > "$conf/level"
rm -f -- "$PICOM_STATE"
cp_ start
check_in "$(cat "$PICOM_LOG")" "light.conf" "start, a level file it cannot read: light"

printf 'tear\n' > "$conf/level"
rm -f -- "$conf/full.conf"
cp_ full
check_rc 1 "a missing profile: exit 1"
check_in "$err" "missing profile: $conf/full.conf" "a missing profile: said so"
check_eq "$(level)" tear "a missing profile: the remembered level is kept"
printf '# full\n' > "$conf/full.conf"
export PICOM_FAIL=1
cp_ full
unset PICOM_FAIL
check_rc 1 "picom will not start: exit 1"
check_eq "$(level)" tear "picom will not start: the remembered level is kept"

rm -f -- "$PICOM_STATE"
export GLXINFO_RENDERER='llvmpipe (LLVM 19.1.7, 256 bits)'
cp_ full
check_rc 1 "a software renderer: refused"
check_in "$err" "software-rendered (llvmpipe" "a software renderer: said so"
check_eq "$(cat "$PICOM_LOG")" "" "a software renderer: picom not started"
cp_ -f full
check_rc 0 "-f: composites anyway"
export GLXINFO_RENDERER=''
rm -f -- "$PICOM_STATE"
cp_ full
check_rc 1 "glxinfo cannot reach X: refused"
check_in "$err" "cannot reach the X server" "glxinfo cannot reach X: said so"
export GLXINFO_RENDERER='Mesa Intel(R) Graphics (MTL)'

mkdir -p "$tmp/noglx"
for f in "$fakes"/*; do
    [ "${f##*/}" = glxinfo ] || ln -sf "$f" "$tmp/noglx/"
done
rm -f -- "$PICOM_STATE"
# The tool appends /usr/local/bin to PATH, so a glxinfo there cannot be
# hidden from it.
PATH=$tmp/noglx:/bin:/usr/bin
if PATH=$PATH:/usr/local/bin command -v glxinfo > /dev/null; then
    PATH=$fakes:$ORIG_PATH
    pass "no glxinfo: skipped, this host has one in /bin, /usr/bin or /usr/local/bin"
else
    cp_ full
    PATH=$fakes:$ORIG_PATH
    check_rc 0 "no glxinfo: not refused"
    check_in "$err" "no glxinfo, so the renderer is not checked" "no glxinfo: said so"
fi

: > "$PICOM_STATE"
export PICOM_STUCK=1
cp_ off
unset PICOM_STUCK
check_rc 1 "a picom that will not stop: exit 1"
check_in "$err" "picom refuses to die" "a picom that will not stop: said so"
rm -f -- "$PICOM_STATE"

for args in '' 'bogus' 'full extra' '-z full'; do
    # shellcheck disable=SC2086  # each case is a word list
    cp_ $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(cat "$PICOM_LOG")" "" "refuses [$args]: picom not started"
done
run compositor-picom -h
check_rc 0 "-h: help"

finish
