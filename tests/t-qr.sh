#!/bin/sh
# qr: the type it picks, the text it hands qrencode and how, and the
# refusals.  The terminal case (stdout a tty) is not covered: the suite
# captures stdout.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export QRENCODE_ARGV="$tmp/argv"
qr() {
    rm -f -- "$QRENCODE_ARGV"
    run qr "$@"
}
qr_stdin() {
    rm -f -- "$QRENCODE_ARGV"
    rc=0
    # shellcheck disable=SC2086  # SH may carry options
    printf '%s' "$1" | $SH "$top/bin/qr" > "$tmp/out" 2> "$tmp/err" || rc=$?
    err=$(cat "$tmp/err")
}
asked() {
    cat -- "$QRENCODE_ARGV" 2> /dev/null | tr '\n' ' '
}

qr 'https://example.org/?a=1&b=*'
check_rc 0 "piped: succeeds"
check_eq "$(asked)" \
    "-t SVG -l Q -s 5 -o - --rle --svg-path --inline -- https://example.org/?a=1&b=* " \
    "piped: compact SVG to stdout, Q and 5 by default, the text after --"

qr hello  big   world
check_in "$(asked)" "-- hello big world " "the arguments are joined by single spaces"

qr -o code.png hi
check_eq "$(asked)" "-t PNG -l Q -s 5 -o code.png -- hi " "-o .png: a PNG, without the SVG options"
qr -o CODE.SVG hi
check_in "$(asked)" "-t SVG" "-o .SVG: the extension in any case"
qr -o code.eps hi
check_in "$(asked)" "-t EPS" "-o .eps: EPS"
qr -o code.xpm hi
check_in "$(asked)" "-t XPM" "-o .xpm: XPM"
qr -o code.img -t PNG32 hi
check_in "$(asked)" "-t PNG32" "-t overrides what the extension cannot say"
qr -t ASCII -l h -s 3 hi
check_eq "$(asked)" "-t ASCII -l h -s 3 -o - -- hi " "-t, -l and -s reach qrencode"

qr -- -dash
check_in "$(asked)" "-- -dash " "text starting with - is passed after --"

qr_stdin "from stdin
"
check_rc 0 "stdin: succeeds"
check_in "$(asked)" "-- from stdin " "stdin: the text, its trailing newline dropped"
qr_stdin "two
lines
"
check_eq "$(sed -n '$p' "$QRENCODE_ARGV")" "lines" "stdin: inner newlines are kept"

qr_stdin ''
check_rc 1 "empty stdin: exit 1"
check_in "$err" "nothing to encode" "empty stdin: said so"

for args in '-o code.jpg hi' '-t BMP hi' '-l X hi' '-l QQ hi' '-s 0 hi' \
    '-s x hi' '-z hi'; do
    # shellcheck disable=SC2086  # each case is a word list
    qr $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(asked)" "" "refuses [$args]: qrencode not run"
done

finish
