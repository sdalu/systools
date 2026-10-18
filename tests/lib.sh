# tests/lib.sh — sourced by every tests/t-*.sh.
#
# A test runs a script of bin/ under $SH (default sh) with tests/fake/ first
# on PATH, so every external tool the scripts touch is a stand-in that
# records what it was asked and answers what the test set up.  Results
# print one per line, "ok" or "FAIL"; the file exits non-zero on a failure.
# 'local' is not POSIX, but every shell this runs under has it
# shellcheck shell=sh disable=SC3043
set -u

top=$(cd -- "$(dirname -- "$0")/.." && pwd)
fakes=$top/tests/fake
: "${SH:=sh}"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/systools-tests.XXXXXX") || exit 1
trap 'rm -rf -- "$tmp"' EXIT
trap 'exit 1' HUP INT TERM

ORIG_PATH=$PATH
PATH=$fakes:$PATH
export ORIG_PATH PATH

# A missing stand-in would let a test reach the real tool, and the real
# zfs destroys snapshots: refuse to run at all rather than risk it.
for tool in zfs curl ip route ssh uname nice idprio chrt ionice gs \
    sysctl ifconfig xrandr qrencode; do
    if [ "$(command -v "$tool")" != "$fakes/$tool" ]; then
        printf 'Bail out: %s does not resolve to tests/fake/%s\n' \
            "$tool" "$tool"
        exit 1
    fi
done

passed=0
failed=0

# run SCRIPT [ARG...] — run bin/SCRIPT under $SH; sets rc, out and err.
run() {
    local script="$1"
    shift
    rc=0
    # shellcheck disable=SC2086  # SH may carry options: SH='bash --posix'
    $SH "$top/bin/$script" "$@" > "$tmp/out" 2> "$tmp/err" || rc=$?
    out=$(cat "$tmp/out")
    err=$(cat "$tmp/err")
}

pass() {
    passed=$((passed + 1))
    printf 'ok   %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$1"
    shift
    for line in "$@"; do
        printf '       %s\n' "$line"
    done
    printf '       exit status %s\n' "${rc-}"
    printf '%s\n' "${out-}" | sed 's/^/       out| /'
    printf '%s\n' "${err-}" | sed 's/^/       err| /'
}

check_rc() {
    if [ "$rc" = "$1" ]; then pass "$2"; else fail "$2" "wanted exit $1"; fi
}

# check_in TEXT NEEDLE NAME — TEXT contains NEEDLE.
check_in() {
    case $1 in
    *"$2"*) pass "$3" ;;
    *) fail "$3" "wanted: $2" ;;
    esac
}

# check_not_in TEXT NEEDLE NAME — TEXT does not contain NEEDLE.
check_not_in() {
    case $1 in
    *"$2"*) fail "$3" "unwanted: $2" ;;
    *) pass "$3" ;;
    esac
}

check_eq() {
    if [ "$1" = "$2" ]; then
        pass "$3"
    else
        fail "$3" "got:    $1" "wanted: $2"
    fi
}

finish() {
    printf '# %s: %s passed, %s failed\n' "${0##*/}" "$passed" "$failed"
    [ "$failed" -eq 0 ]
}
