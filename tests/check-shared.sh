#!/bin/sh
# check-shared.sh — the functions transcribe and vocalise share are the
# same in both.  Each tool stays a single file that runs on its own, so
# they keep a copy each; this is what stops the copies drifting apart.
# Run by `make check`.
set -u

top=$(cd -- "$(dirname -- "$0")/.." && pwd)
shared='bad aichat_token authinfo_token read_token stage_credentials safe_path
    char_count'

body() {
    sed -n "/^$1() {/,/^}/p" "$top/bin/$2"
}

status=0
for fn in $shared; do
    a=$(body "$fn" transcribe)
    b=$(body "$fn" vocalise)
    if [ -z "$a" ] || [ -z "$b" ]; then
        printf 'check-shared: %s is missing from transcribe or vocalise\n' \
            "$fn" >&2
        status=1
    elif [ "$a" != "$b" ]; then
        printf 'check-shared: %s differs between transcribe and vocalise\n' \
            "$fn" >&2
        status=1
    fi
done
exit "$status"
