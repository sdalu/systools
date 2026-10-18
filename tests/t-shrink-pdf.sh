#!/bin/sh
# shrink-pdf: the smaller of input and result wins, a failure leaves the
# output as it was, and the refusals -- the output being the input above
# all.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export GS_ARGV="$tmp/gs.argv" TMPDIR="$tmp/scratch"
mkdir -p "$TMPDIR" "$tmp/d"
infile=$tmp/d/in.pdf
outfile=$tmp/d/out.pdf
printf '%%PDF-1.4 a fairly long original document\n' > "$infile"

shrink() {
    rm -f -- "$GS_ARGV" "$outfile"
    run shrink-pdf "$@"
}
asked() {
    cat -- "$GS_ARGV" 2> /dev/null
}

export GS_OUTPUT='%PDF-1.3 small'
shrink "$infile" "$outfile"
check_rc 0 "smaller: succeeds"
check_eq "$(cat "$outfile")" "%PDF-1.3 small" "smaller: the result is written"
check_in "$(asked)" "-dColorImageResolution=72" "the default resolution is 72 dpi"
check_in "$(asked)" "-sDEVICE=pdfwrite" "Ghostscript is asked for a PDF"
check_eq "$(sed -n '$p' "$GS_ARGV")" "$infile" "the input is gs's last argument"

shrink "$infile" "$outfile" 150
check_in "$(asked)" "-dGrayImageResolution=150" "a resolution given reaches gs"

shrink "$infile"
check_eq "$out" "%PDF-1.3 small" "no outfile: the result goes to stdout"
shrink "$infile" -
check_eq "$out" "%PDF-1.3 small" "outfile -: the result goes to stdout"

shrink -v "$infile" "$outfile"
check_in "$err" "bytes -> 14 bytes" "-v reports the sizes"

export GS_OUTPUT='%PDF-1.3 a result much longer than the original document was'
shrink -v "$infile" "$outfile"
check_rc 0 "larger: succeeds"
check_eq "$(cat "$outfile")" "$(cat "$infile")" "larger: the input is passed through"
check_in "$err" "the input is kept" "larger: said so with -v"
export GS_OUTPUT='%PDF-1.3 small'

umask 022
shrink "$infile" "$outfile"
# shellcheck disable=SC2012  # ls -l is the portable way to read a mode
check_eq "$(ls -l "$outfile" | cut -c1-10)" "-rw-r--r--" \
    "a new outfile gets the umask's mode, not the temporary file's"

printf 'keep me\n' > "$outfile"
export GS_EXIT=1
run shrink-pdf "$infile" "$outfile"
unset GS_EXIT
check_rc 1 "gs fails: exit 1"
check_eq "$(cat "$outfile")" "keep me" "gs fails: an existing outfile is untouched"
check_in "$err" "Ghostscript failed" "gs fails: said so"
check_eq "$(ls -A "$TMPDIR")" "" "no temporary file is left behind"

printf '%%PDF-1.4 dash\n' > "$tmp/d/-x.pdf"
shrink -- "$tmp/d/-x.pdf" "$outfile"
check_rc 0 "an input named -x.pdf is accepted after --"
(cd "$tmp/d" && rm -f -- "$GS_ARGV" &&
    $SH "$top/bin/shrink-pdf" -- -x.pdf out.pdf 2> /dev/null)
check_eq "$(sed -n '$p' "$GS_ARGV")" "./-x.pdf" \
    "a relative input starting with - reaches gs as ./-x.pdf, not an option"

ln -s in.pdf "$tmp/d/link.pdf"
for target in "$infile" "$tmp/d/link.pdf"; do
    shrink "$infile" "$target"
    check_rc 2 "refuses to write over the input (${target##*/})"
    check_eq "$(asked)" "" "refuses to write over the input (${target##*/}): gs not run"
done
check_eq "$(cat "$infile")" "%PDF-1.4 a fairly long original document" \
    "the input is intact"

shrink "$tmp/d/none.pdf" "$outfile"
check_rc 1 "a missing input: exit 1"
check_eq "$(asked)" "" "a missing input: gs not run"

for args in '' "$infile $outfile 72 extra" "$infile $outfile x" \
    "$infile $outfile 0" "$infile $outfile 072" "-z $infile"; do
    # shellcheck disable=SC2086  # each case is a word list
    shrink $args
    check_rc 2 "refuses [${args##*/}] as a usage error"
    check_eq "$(asked)" "" "refuses [${args##*/}]: gs not run"
done

finish
