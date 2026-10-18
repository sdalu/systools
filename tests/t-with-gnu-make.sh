#!/bin/sh
# with-gnu-make: the make shim, its removal once make is GNU, and the
# refusals.  The gcc half depends on whether the host has a gcc, so it
# is not pinned here.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

mkdir -p "$tmp/bsd" "$tmp/gnu" "$tmp/it's"
for d in bsd gnu "it's"; do
    printf '#!/bin/sh\nexit 1\n' > "$tmp/$d/make"
done
printf '#!/bin/sh\necho "GNU Make 4.4.1"\n' > "$tmp/gnu/gmake"
printf '#!/bin/sh\necho "GNU Make 4.4.1"\n' > "$tmp/it's/gmake"
cp "$tmp/gnu/gmake" "$tmp/gnu/make"
chmod 755 "$tmp"/*/*make

export SHIM_DIR="$tmp/shims" GNU_MAKE="$tmp/gnu/gmake"
base=$PATH

PATH=$tmp/bsd:$base
run with-gnu-make sh -c 'make --version'
check_rc 0 "make is not GNU: runs the command"
check_eq "$out" "GNU Make 4.4.1" "make is not GNU: the command's make is gmake"
check_eq "$(sed -n 2p "$SHIM_DIR/make")" "exec '$tmp/gnu/gmake' \"\$@\"" \
    "make is not GNU: the shim execs gmake by absolute path"

# A shim left by an earlier run must not shadow a make that is now GNU,
# whether or not the gcc half still puts the shim directory on PATH.
printf '#!/bin/sh\necho STALE\n' > "$SHIM_DIR/make"
PATH=$tmp/gnu:$base
run with-gnu-make sh -c 'make --version'
check_rc 0 "make is GNU: runs the command"
check_eq "$out" "GNU Make 4.4.1" "make is GNU: an earlier make shim does not shadow it"

PATH=$tmp/bsd:$base
export GNU_MAKE="$tmp/none"
run with-gnu-make true
check_rc 1 "no GNU make: exit 1"
check_in "$err" "GNU make not found" "no GNU make: said so"
export GNU_MAKE="$tmp/bsd/make"
run with-gnu-make true
check_rc 1 "GNU_MAKE is not GNU: exit 1"
check_in "$err" "is not GNU make" "GNU_MAKE is not GNU: said so"
export GNU_MAKE="$tmp/it's/gmake"
run with-gnu-make true
check_rc 1 "a quote in the gmake path: exit 1"
check_in "$err" "refusing to shim a path containing a quote" \
    "a quote in the gmake path: refused, not written into a shim"
PATH=$base

run with-gnu-make
check_rc 2 "no command: a usage error"
run with-gnu-make -h
check_rc 0 "-h: help"

finish
