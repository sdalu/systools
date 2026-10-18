#!/bin/sh
# zfs-prune-snapshots: keeps the newest N snapshots of each dataset,
# carries on past a failing one, and refuses what it cannot parse.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export ZFS_STATE="$tmp/pool" ZFS_LOG="$tmp/zfs.log"
pool() {
    printf '%s\n' "$@" > "$ZFS_STATE"
    : > "$ZFS_LOG"
}
state() {
    tr '\n' ' ' < "$ZFS_STATE"
}
five='tank/a tank/a@s1 tank/a@s2 tank/a@s3 tank/a@s4 tank/a@s5'

# shellcheck disable=SC2086  # $five is a word list on purpose
pool $five
run zfs-prune-snapshots tank/a
check_rc 0 "keep 1: succeeds"
check_eq "$(state)" "tank/a tank/a@s5 " "keep 1: only the newest survives"
check_eq "$(cat "$ZFS_LOG")" "destroy -- tank/a@%s4" \
    "keep 1: one range destroy, oldest through the second newest"

# shellcheck disable=SC2086
pool $five
run zfs-prune-snapshots -k 2 tank/a
check_eq "$(state)" "tank/a tank/a@s4 tank/a@s5 " "keep 2: the two newest survive"

# shellcheck disable=SC2086
pool $five
run zfs-prune-snapshots -k 0 tank/a
check_eq "$(state)" "tank/a " "keep 0: every snapshot goes"

# shellcheck disable=SC2086
pool $five
run zfs-prune-snapshots -k 5 tank/a
check_rc 0 "keep 5 of 5: succeeds"
check_eq "$(cat "$ZFS_LOG")" "" "keep 5 of 5: nothing destroyed"

pool tank/a 'tank/a/b c' tank/a@s1 'tank/a/b c@x1' tank/a@s2 \
    'tank/a/b c@x2' tank/a@s3
run zfs-prune-snapshots -r tank/a
check_rc 0 "recursive: succeeds"
check_eq "$(state)" "tank/a tank/a/b c tank/a/b c@x2 tank/a@s3 " \
    "recursive: each dataset keeps its own newest, spaces in names too"

# shellcheck disable=SC2086
pool $five
run zfs-prune-snapshots -d tank/a
check_in "$(cat "$ZFS_LOG")" "destroy -d -- tank/a@%s4" "-d asks for deferred destruction"

# shellcheck disable=SC2086
pool $five
run zfs-prune-snapshots -n -v tank/a
check_rc 0 "dry run: succeeds"
check_eq "$(state)" "$five " "dry run: nothing destroyed"
check_in "$out" "would destroy tank/a@%s4" "dry run: shows the range"
check_in "$err" "would destroy 4, up to s4" "dry run: -v says would, not did"

pool tank/a tank/b tank/a@s1 tank/a@s2 tank/b@t1 tank/b@t2
export ZFS_FAIL='destroy*tank/a@*'
run zfs-prune-snapshots tank/a tank/b
unset ZFS_FAIL
check_rc 1 "a failing dataset: exit 1"
check_in "$err" "failed to destroy snapshots (tank/a)" "a failing dataset: named"
check_eq "$(state)" "tank/a tank/b tank/a@s1 tank/a@s2 tank/b@t2 " \
    "a failing dataset: the next one is still pruned"

pool tank/b tank/b@t1 tank/b@t2
run zfs-prune-snapshots tank/nosuch tank/b
check_rc 1 "a missing dataset: exit 1"
check_in "$err" "failed to retrieve snapshots (tank/nosuch)" "a missing dataset: named"
check_eq "$(state)" "tank/b tank/b@t2 " "a missing dataset: the next one is still pruned"

for args in '-k x tank/a' '-k -1 tank/a' '-k 1x tank/a' '' '--keep=2 tank/a' \
    '-z tank/a'; do
    # shellcheck disable=SC2086
    pool $five
    # shellcheck disable=SC2086  # each case is a word list
    run zfs-prune-snapshots $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(state)" "$five " "refuses [$args]: nothing destroyed"
done

finish
