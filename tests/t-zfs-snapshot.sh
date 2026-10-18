#!/bin/sh
# zfs-snapshot: today's snapshot, the weekly and 6-month expiries, the
# month-end window, failure handling, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export ZFS_STATE="$tmp/pool" ZFS_LOG="$tmp/zfs.log"
pool() {
    printf 'tank/fs\n' > "$ZFS_STATE"
    for d; do
        printf 'tank/fs@%s\n' "$d" >> "$ZFS_STATE"
    done
    : > "$ZFS_LOG"
}
state() {
    sed -n 's/^tank\/fs@//p' "$ZFS_STATE" | sort | tr '\n' ' '
}

# 2026-10-19 is a Monday: 10-12 (a weekday, a week old) and 04-19 (six
# months old) expire.  10-11 is a Sunday and stays; 04-12 reached six
# months a week ago, so expiring it was that run's job, not this one's.
pool 2026-04-12 2026-04-19 2026-10-11 2026-10-12
run zfs-snapshot -t 2026-10-19 tank/fs
check_rc 0 "weekday: succeeds"
check_eq "$(state)" "2026-04-12 2026-10-11 2026-10-19 " \
    "weekday: snapshot taken, last week's weekday and 6-month one gone"

pool 2026-10-11
run zfs-snapshot -t 2026-10-18 tank/fs
check_eq "$(state)" "2026-10-11 2026-10-18 " "Sunday: last Sunday's snapshot is kept"

# Six months before 2026-02-28 is 2025-08-28; before 2026-03-01 it is
# 2025-09-01.  Nothing maps to 08-29..08-31, which must still expire.
pool 2025-08-27 2025-08-28 2025-08-29 2025-08-30 2025-08-31 2025-09-01 \
    2025-09-02
run zfs-snapshot -t 2026-02-28 tank/fs
check_eq "$(state)" "2025-08-27 2025-08-29 2025-08-30 2025-08-31 2025-09-01 2025-09-02 2026-02-28 " \
    "2026-02-28: only 2025-08-28 expires"
run zfs-snapshot -t 2026-03-01 tank/fs
check_eq "$(state)" "2025-08-27 2025-09-02 2026-02-28 2026-03-01 " \
    "2026-03-01: 08-29 through 09-01 expire, none left behind"

pool 2026-10-12 2026-10-19
run zfs-snapshot -v -t 2026-10-19 tank/fs
check_rc 0 "already taken today: not an error"
check_in "$err" "tank/fs@2026-10-19 already exists" "already taken today: said so"
check_not_in "$(cat "$ZFS_LOG")" "snapshot" "already taken today: not retaken"
check_eq "$(state)" "2026-10-19 " "already taken today: expiry still runs"

pool 2026-04-19 2026-10-12
export ZFS_FAIL='snapshot*'
run zfs-snapshot -t 2026-10-19 tank/fs
unset ZFS_FAIL
check_rc 1 "snapshot fails: exit 1"
check_eq "$(state)" "2026-04-19 2026-10-12 " \
    "snapshot fails: nothing expires without its replacement"

pool 2026-04-19 2026-10-12
export ZFS_FAIL='destroy*2026-10-12'
run zfs-snapshot -t 2026-10-19 tank/fs
unset ZFS_FAIL
check_rc 1 "one destroy fails: exit 1"
check_eq "$(state)" "2026-10-12 2026-10-19 " "one destroy fails: the other still runs"

pool 2026-04-19 2026-10-12
run zfs-snapshot -r -t 2026-10-19 tank/fs
check_in "$(cat "$ZFS_LOG")" "snapshot -r -- tank/fs@2026-10-19" "-r: recursive snapshot"
check_in "$(cat "$ZFS_LOG")" "destroy -r -- tank/fs@2026-10-12" "-r: recursive destroy"

pool 2026-04-19 2026-10-12
run zfs-snapshot -n -t 2026-10-19 tank/fs
check_rc 0 "dry run: succeeds"
check_eq "$(state)" "2026-04-19 2026-10-12 " "dry run: the pool is untouched"
check_in "$err" "would run: zfs snapshot -- tank/fs@2026-10-19" "dry run: shows the snapshot"
check_in "$err" "would run: zfs destroy -- tank/fs@2026-04-19" "dry run: shows the expiry"

pool
run zfs-snapshot tank/fs
check_eq "$(state)" "$(date +%Y-%m-%d) " "no -t: today's date"

for args in '-t 2026-02-30 tank/fs' '-t 2026-13-01 tank/fs' \
    '-t 26-1-1 tank/fs' '-p hourly tank/fs' '' 'tank/fs tank/fs' \
    '--recursive tank/fs' '-z tank/fs'; do
    pool 2026-10-12
    # shellcheck disable=SC2086  # each case is a word list
    run zfs-snapshot $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(cat "$ZFS_LOG")" "" "refuses [$args]: touches nothing"
done

pool
run zfs-snapshot -t 2026-10-19 tank/nosuch
check_rc 1 "a missing dataset: exit 1"
check_in "$err" "dataset doesn't exist: tank/nosuch" "a missing dataset: said so"

finish
