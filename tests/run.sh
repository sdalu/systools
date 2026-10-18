#!/bin/sh
# run.sh — run the suite: every tests/t-*.sh, the scripts under $SH
# usage: [SH=shell] sh tests/run.sh [test...]
#   e.g. SH=dash sh tests/run.sh t-pushover.sh
set -u

cd -- "$(dirname -- "$0")" || exit 1
[ "$#" -gt 0 ] || set -- ./t-*.sh

bad=0
for t in "$@"; do
    sh "$t" || bad=$((bad + 1))
done

if [ "$bad" -eq 0 ]; then
    printf '# all %s test files passed (SH=%s)\n' "$#" "${SH:-sh}"
else
    printf '# %s of %s test files FAILED (SH=%s)\n' "$bad" "$#" "${SH:-sh}"
    exit 1
fi
