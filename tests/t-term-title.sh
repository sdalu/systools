#!/bin/sh
# term-title: the exact bytes each sequence family gets, the text kept
# whole and stripped of control characters, -e's save, title and
# restore around the command, and the refusals.  Every call that writes
# a sequence names -o: the default is the terminal, which the suite must
# not write to when it is run from one.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

seq=$tmp/seq
# tt ARG... — run term-title with -o into a fresh $seq
tt() {
    : > "$seq"
    run term-title -o "$seq" "$@"
}
# bytes — what the last run wrote, as od shows it, for a readable failure
bytes() {
    od -An -c < "$seq" | tr -s ' \n' ' '
}
# want FORMAT ARG... — the bytes printf makes of it, the same way
want() {
    # shellcheck disable=SC2059  # the format is the expected sequence
    printf "$@" | od -An -c | tr -s ' \n' ' '
}

export TERM=xterm-256color
tt make -j4 'world *'
check_rc 0 "xterm: succeeds"
check_eq "$(bytes)" "$(want '\033]0;%s\007' 'make -j4 world *')" \
    "xterm: OSC 0, every argument, spaces and * kept"
check_eq "$out" "" "-o: nothing on stdout"
tt -w '50% done'
check_eq "$(bytes)" "$(want '\033]2;%s\007' '50% done')" "-w: OSC 2, and % is not a format"
tt -i tab
check_eq "$(bytes)" "$(want '\033]1;%s\007' tab)" "-i: OSC 1"
tt -b both
check_eq "$(bytes)" "$(want '\033]0;%s\007' both)" "-b: OSC 0"
tt
check_eq "$(bytes)" "$(want '\033]0;\007')" "no text: the title is cleared"
tt "$(printf 'evil\033]2;pwned\007 tab\there')"
check_eq "$(bytes)" "$(want '\033]0;%s\007' 'evil]2;pwned tabhere')" \
    "control characters in the text are removed, not sent"

tt -s
check_eq "$(bytes)" "$(want '\033[22;0t')" "-s: both saved on the title stack"
tt -w -r
check_eq "$(bytes)" "$(want '\033[23;2t')" "-w -r: the window title restored"

tt -w -e sh -c 'printf ran; exit 3'
check_rc 3 "-e: the command's exit status"
check_eq "$out" "ran" "-e: the command runs, its output untouched"
check_eq "$(bytes)" "$(want '\033[22;2t\033]2;%s\007\033[23;2t' "sh -c printf ran; exit 3")" \
    "-e: save, the command line as title, restore"
# shellcheck disable=SC2016  # $PPID is the inner shell's
tt -e sh -c 'kill -INT $PPID; sleep 1'
check_rc 130 "-e interrupted: exit 130"
# shellcheck disable=SC2016
check_eq "$(bytes)" "$(want '\033[22;0t\033]0;%s\007\033[23;0t' 'sh -c kill -INT $PPID; sleep 1')" \
    "-e interrupted: the title is still restored"

for t in rxvt-unicode alacritty foot kitty st-256color wezterm konsole; do
    export TERM=$t
    tt -w x
    check_eq "$(bytes)" "$(want '\033]2;x\007')" "$t: OSC 2"
done

for t in screen screen.xterm-256color tmux-256color; do
    export TERM=$t
    tt -w build
    check_eq "$(bytes)" "$(want '\033kbuild\033\134')" "$t: the window name"
done
tt -e true
check_rc 0 "screen -e: runs the command"
check_eq "$(bytes)" "$(want '\033ktrue\033\134')" "screen -e: names the window, nothing to restore"
tt -s
check_rc 1 "screen -s: exit 1, no stack"
check_eq "$(bytes)" "" "screen -s: nothing written"

export TERM=linux
tt x
check_rc 1 "linux: exit 1"
check_eq "$(bytes)" "" "linux: nothing written"
check_in "$err" "cannot set the title of a linux terminal" "linux: said so"
tt -q x
check_eq "$err" "" "-q: nothing said"
tt -e sh -c 'exit 4'
check_rc 4 "an unknown terminal with -e: the command still runs"
check_eq "$(bytes)" "" "an unknown terminal with -e: nothing written"
tt -T xterm -w x
check_eq "$(bytes)" "$(want '\033]2;x\007')" "-T xterm: OSC whatever TERM says"
tt -T screen x
check_eq "$(bytes)" "$(want '\033kx\033\134')" "-T screen: the window name whatever TERM says"
unset TERM
tt x
check_rc 1 "no TERM: exit 1"

export TERM=xterm
for args in '-b -w x' '-i -w x' '-s -r' '-s x' '-r x' '-e' '-e -s true' \
    '-T vt100 x' '-z x'; do
    # shellcheck disable=SC2086  # each case is a word list
    tt $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(bytes)" "" "refuses [$args]: nothing written"
done
tt -w -w x
check_rc 0 "the same option twice is not a conflict"
run term-title -h
check_rc 0 "-h: help"

finish
