#!/bin/sh
# low-priority: the wrappers each platform gets, the fallbacks when one is
# refused, what -v shows, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export FAKE_UNAME=FreeBSD
run low-priority -v true
check_rc 0 "FreeBSD: runs"
check_in "$err" "running: nice -n 20 idprio 30 true" "FreeBSD: nice 20 and idprio 30"

export DENY_IDPRIO=1
run low-priority -v true
unset DENY_IDPRIO
check_rc 0 "FreeBSD, idprio refused: still runs"
check_in "$err" "skipping idprio" "FreeBSD, idprio refused: said so with -v"
check_in "$err" "running: nice -n 20 true" "FreeBSD, idprio refused: plain nice"

export FAKE_UNAME=Linux
run low-priority -v true
check_in "$err" "running: nice -n 19 chrt -i 0 ionice -c 3 true" \
    "Linux: nice 19, SCHED_IDLE and the idle I/O class"
export DENY_CHRT=1
run low-priority -v true
unset DENY_CHRT
check_in "$err" "skipping chrt" "Linux, chrt refused: said so"
check_in "$err" "running: nice -n 19 ionice -c 3 true" "Linux, chrt refused: the rest stays"
export DENY_IONICE=1 DENY_CHRT=1
run low-priority -v true
unset DENY_IONICE DENY_CHRT
check_in "$err" "running: nice -n 19 true" "Linux, both refused: plain nice"

export FAKE_UNAME=NetBSD
run low-priority -v true
check_in "$err" "running: nice -n 19 true" "elsewhere: plain nice"

export FAKE_UNAME=FreeBSD
run low-priority sh -c 'exit 3'
check_rc 3 "the command's exit status comes back"
run low-priority true
check_eq "$err" "" "without -v: nothing on stderr"

run low-priority -v printf '%s|' 'a b' "it's" ''
check_eq "$out" "a b|it's||" "arguments reach the command intact"
check_in "$err" "printf '%s|' 'a b' 'it'\\''s' ''" "-v quotes the command so it can be pasted"

# shellcheck disable=SC2016  # $1 is for the inner shell
run low-priority sh -c 'printf "%s" "$1"' x -v
check_eq "$out" "-v" "options after the command are the command's"

for args in '' '-v' '-z true'; do
    # shellcheck disable=SC2086  # each case is a word list
    run low-priority $args
    check_rc 2 "refuses [$args] as a usage error"
done

finish
