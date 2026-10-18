#!/bin/sh
# check-port.sh — the FreeBSD port installs every tool and page, no more
# usage: sh tests/check-port.sh
#
# The PLIST_FILES and DAV_PLIST_FILES of ports/sysutils/systools/Makefile
# must name bin/X and share/man/man1/X.1.gz for exactly the tools of bin/
# and the pages of man/: a tool added here and not to the port, or the
# other way round, fails make check, rather than the port's check-plist,
# which only a port build runs.
set -u

cd -- "$(dirname -- "$0")/.." || exit 1
port=ports/sysutils/systools/Makefile

# The plist's bin/ and share/man/man1/ entries, then a "--" line, then
# what bin/ and man/ hold, named as the plist names them.
{
    awk '/^(DAV_)?PLIST_FILES=/ { on = 1 }
        on {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^(bin|share\/man\/man1)\//) print $i
            if ($NF != "\\") on = 0
        }' "$port"
    printf -- '--\n'
    for f in bin/*; do printf 'bin/%s\n' "${f#bin/}"; done
    for f in man/*.1; do printf 'share/man/man1/%s.gz\n' "${f#man/}"; done
} | awk -v port="$port" '
    $0 == "--" { tree = 1; next }
    !tree { listed[$0] = 1; next }
    { shipped[$0] = 1 }
    END {
        for (f in shipped)
            if (!(f in listed)) { print "check-port: " port " lacks " f; bad = 1 }
        for (f in listed)
            if (!(f in shipped)) { print "check-port: " port " lists " f \
                                   ", which the tree does not have"; bad = 1 }
        if (!bad) print "check-port: the port installs every tool and page"
        exit bad
    }' >&2
