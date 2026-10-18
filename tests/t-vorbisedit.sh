#!/bin/sh
# vorbisedit: the comments opened in the editor and written back only
# when changed, the editor chosen from $VISUAL, $EDITOR and vi, nothing
# written when the editor fails, the edit kept when the write fails, no
# temporary file left behind, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export VORBISCOMMENT_LOG="$tmp/vc.log" EDIT_LOG="$tmp/edit.log" \
    TMPDIR="$tmp/scratch" EDITOR=edit-tags
unset VISUAL EDIT_SED EDIT_RC
mkdir -p "$TMPDIR"
ogg=$tmp/song.ogg
original=$(printf 'TITLE=Song\nARTIST=Someone')

ve_() {
    printf '%s\n' "$original" > "$ogg"
    : > "$VORBISCOMMENT_LOG"
    : > "$EDIT_LOG"
    run vorbisedit "$@"
}
log() {
    cat -- "$1"
}
leftovers() {
    find "$TMPDIR" -type f | wc -l | tr -d ' '
}

export EDIT_SED='s/^TITLE=.*/TITLE=Other Song/'
ve_ "$ogg"
check_rc 0 "an edit: succeeds"
check_eq "$(cat -- "$ogg")" "$(printf 'TITLE=Other Song\nARTIST=Someone')" \
    "an edit: the comments written back"
check_in "$(log "$VORBISCOMMENT_LOG")" "-l -R -e -- $ogg" "an edit: listed as UTF-8, with escapes"
check_in "$(log "$VORBISCOMMENT_LOG")" "-w -R -e -c $TMPDIR/vorbisedit." \
    "an edit: written from a temporary file, replacing them all"
check_in "$(log "$EDIT_LOG")" "$TMPDIR/vorbisedit." "an edit: \$EDITOR opens a temporary file"
check_eq "$(leftovers)" 0 "an edit: no temporary file left"

unset EDIT_SED
ve_ "$ogg"
check_rc 0 "no change: exit 0"
check_in "$err" "no change" "no change: said so"
check_not_in "$(log "$VORBISCOMMENT_LOG")" "-w" "no change: nothing written"
check_eq "$(leftovers)" 0 "no change: no temporary file left"

export EDIT_SED='s/^TITLE=.*/TITLE=Lost/' EDIT_RC=1
ve_ "$ogg"
unset EDIT_RC
check_rc 1 "the editor fails: exit 1"
check_in "$err" "the editor failed" "the editor fails: said so"
check_eq "$(cat -- "$ogg")" "$original" "the editor fails: the file left as it was"
check_not_in "$(log "$VORBISCOMMENT_LOG")" "-w" "the editor fails: nothing written"
check_eq "$(leftovers)" 0 "the editor fails: no temporary file left"

export VORBISCOMMENT_FAIL=1 EDIT_SED='s/^TITLE=.*/TITLE=Kept/'
ve_ "$ogg"
unset VORBISCOMMENT_FAIL
check_rc 1 "the write fails: exit 1"
check_in "$err" "the edited ones are in $TMPDIR/vorbisedit." "the write fails: the edit named"
kept=$(find "$TMPDIR" -type f)
check_eq "$(cat -- "$kept" 2> /dev/null)" "$(printf 'TITLE=Kept\nARTIST=Someone')" \
    "the write fails: the edit kept, alone"
rm -f -- "$kept"

export VISUAL='edit-tags --visual'
ve_ "$ogg"
unset VISUAL
check_in "$(log "$EDIT_LOG")" "--visual $TMPDIR/vorbisedit." "\$VISUAL before \$EDITOR, a command line"

# No $VISUAL, no $EDITOR: vi, here a stand-in on PATH for this case only.
mkdir -p "$tmp/vi"
ln -sf "$fakes/edit-tags" "$tmp/vi/vi"
unset EDITOR
PATH=$tmp/vi:$PATH
ve_ "$ogg"
PATH=$fakes:$ORIG_PATH
export EDITOR=edit-tags
check_rc 0 "neither set: succeeds"
check_in "$(log "$EDIT_LOG")" "$TMPDIR/vorbisedit." "neither set: vi"

ve_ "$tmp/missing.ogg"
check_rc 1 "a missing file: exit 1"
check_in "$err" "no such file" "a missing file: said so"
check_eq "$(log "$EDIT_LOG")" "" "a missing file: no editor"
if [ "$(id -u)" -eq 0 ]; then
    pass "a read-only file: skipped, root writes anyway"
else
    printf '%s\n' "$original" > "$ogg"
    chmod a-w "$ogg"
    : > "$EDIT_LOG"
    run vorbisedit "$ogg"
    chmod u+w "$ogg"
    check_rc 1 "a read-only file: exit 1"
    check_in "$err" "cannot be both read and written" "a read-only file: said so"
    check_eq "$(log "$EDIT_LOG")" "" "a read-only file: refused before the editor"
fi

for args in '' 'a.ogg b.ogg' '-z a.ogg'; do
    # shellcheck disable=SC2086  # each case is a word list
    ve_ $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(log "$EDIT_LOG")" "" "refuses [$args]: no editor"
done
run vorbisedit -h
check_rc 0 "-h: help"

finish
