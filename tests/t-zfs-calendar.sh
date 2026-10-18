#!/bin/sh
# zfs-snapshot's calendar arithmetic, run under $SH, against date(1) for
# a day every few weeks from 1970 to 2100, and against month-end cases
# worked out by hand.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

# The functions, lifted out of the script, with the driver from stdin
# after them.
calendar() {
    {
        sed -n '/^day_of()/,/^}/p;/^date_of()/,/^}/p
                /^weekday_of()/,/^}/p;/^months_before()/,/^}/p' \
            "$top/bin/zfs-snapshot"
        cat
    } > "$tmp/calendar.sh"
    # shellcheck disable=SC2086  # SH may carry options
    $SH "$tmp/calendar.sh"
}

# GNU date takes -d @seconds, BSD date -r seconds.
ref() {
    date -u -d "@$(($1 * 86400))" "$2" 2> /dev/null ||
        date -u -r "$(($1 * 86400))" "$2"
}

step=37
calendar > "$tmp/got" <<DRIVER
n=0
while [ \$n -le 47847 ]; do
    d=\$(date_of \$n)
    printf '%s %s %s %s\n' \$n "\$d" "\$(weekday_of \$n)" "\$(day_of "\$d")"
    n=\$((n + $step))
done
DRIVER
n=0
while [ "$n" -le 47847 ]; do
    printf '%s %s %s %s\n' "$n" "$(ref "$n" +%Y-%m-%d)" "$(ref "$n" +%w)" "$n"
    n=$((n + step))
done > "$tmp/want"
if cmp -s "$tmp/got" "$tmp/want"; then
    pass "date, weekday and round trip agree with date(1), 1970-2100"
else
    fail "date, weekday and round trip agree with date(1), 1970-2100" \
        "$(diff "$tmp/want" "$tmp/got" | head -n 5)"
fi

# date and months back, then the expected answer: the day of month is
# clamped to the length of the target month.
got=$(calendar <<'DRIVER'
while read -r d m; do
    date_of "$(months_before "$(day_of "$d")" "$m")"
done <<CASES
2026-08-31 6
2024-08-31 6
2026-03-01 6
2026-02-28 6
2026-10-18 6
2026-01-15 1
2000-03-31 1
2100-03-31 1
2026-12-31 13
2026-05-31 3
CASES
DRIVER
)
check_eq "$(printf '%s\n' "$got" | tr '\n' ' ')" \
    "2026-02-28 2024-02-29 2025-09-01 2025-08-28 2026-04-18 2025-12-15 2000-02-29 2100-02-28 2025-11-30 2026-02-28 " \
    "months_before clamps to shorter months and knows leap years"

finish
