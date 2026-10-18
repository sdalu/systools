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
    sysctl ifconfig xrandr qrencode wg ps pdftoppm magick cjpeg ffmpeg \
    ffprobe espeak-ng picom pgrep pkill glxinfo maim xdotool xclip \
    notify-send rofi vorbiscomment iw wpa_cli uci ubus jsonfilter wifi \
    piper fetch; do
    if [ "$(command -v "$tool")" != "$fakes/$tool" ]; then
        printf 'Bail out: %s does not resolve to tests/fake/%s\n' \
            "$tool" "$tool"
        exit 1
    fi
done

passed=0
failed=0

# run SCRIPT [ARG...] — run bin/SCRIPT under $SH, or under ruby when its
# shebang names it; sets rc, out and err.
run() {
    local script="$1" interpreter
    shift
    rc=0
    interpreter=$SH
    case $(sed -n 1p "$top/bin/$script") in
    *ruby*) interpreter=ruby ;;
    esac
    # shellcheck disable=SC2086  # SH may carry options: SH='bash --posix'
    $interpreter "$top/bin/$script" "$@" > "$tmp/out" 2> "$tmp/err" || rc=$?
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

# ruby_ready — this host has the Ruby (3.4 or later, with nokogiri) that
# caldav and carddav need; their tests skip themselves without it.
ruby_ready() {
    ruby -rnokogiri -e 'exit(RUBY_VERSION >= "3.4" ? 0 : 1)' \
        > /dev/null 2>&1
}

# dav_server ROOT — serve ROOT with tests/dav-server.rb on 127.0.0.1;
# sets dav_port, and dav_log to the file of the requests it answers.
# The server is stopped when the test exits.
dav_server() {
    local n=0
    dav_log=$tmp/dav.log
    : > "$dav_log"
    ruby "$top/tests/dav-server.rb" "$1" "$tmp/dav.port" "$dav_log" \
        2> "$tmp/dav.err" &
    dav_pid=$!
    trap 'kill "$dav_pid" 2> /dev/null; rm -rf -- "$tmp"' EXIT
    while [ ! -s "$tmp/dav.port" ]; do
        n=$((n + 1))
        if [ "$n" -gt 100 ] || ! kill -0 "$dav_pid" 2> /dev/null; then
            printf 'Bail out: the DAV server did not start\n'
            cat -- "$tmp/dav.err"
            exit 1
        fi
        sleep 0.1
    done
    # shellcheck disable=SC2034  # read by the test that sourced this
    dav_port=$(cat -- "$tmp/dav.port")
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
