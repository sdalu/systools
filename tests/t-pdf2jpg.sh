#!/bin/sh
# pdf2jpg: what each stage is asked for, the naming, the -s quality
# search, the encoder it picks, and the refusals.  The stand-ins write
# PNM headers, so the sizes read back are the ones the stages produced;
# the cjpeg and magick stand-ins write 100 bytes per point of quality.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export PDFTOPPM_LOG="$tmp/pdftoppm.log" MAGICK_LOG="$tmp/magick.log" \
    CJPEG_LOG="$tmp/cjpeg.log" GS_ARGV="$tmp/gs.argv" TMPDIR="$tmp/scratch"
mkdir -p "$TMPDIR" "$tmp/w"
printf '%%PDF-1.4\n' > "$tmp/w/doc.pdf"
base=$PATH

# p2j PAGES ARG... — run on doc.pdf, its pages "WxH ...", in a clean $tmp/w
p2j() {
    export PDFTOPPM_PAGES="$1"
    shift
    rm -rf -- "$tmp/w/out"
    : > "$PDFTOPPM_LOG"
    : > "$MAGICK_LOG"
    : > "$CJPEG_LOG"
    rm -f -- "$GS_ARGV" "$tmp"/w/*.jpg
    (cd "$tmp/w" && run pdf2jpg "$@" doc.pdf && \
        printf '%s\n%s\n%s\n' "$rc" "$out" "$err" > "$tmp/result")
    rc=$(sed -n 1p "$tmp/result")
    out=$(sed -n '2,/^$/p' "$tmp/result" | sed '$d')
    err=$(cat "$tmp/err")
}
jpgs() {
    (cd "$tmp/w" && find . -name '*.jpg' | sort | tr '\n' ' ')
}
log() {
    cat -- "$1" 2> /dev/null
}

three='596x842 596x842 842x596'

p2j "$three" -w 600
check_rc 0 "three pages: succeeds"
check_eq "$(jpgs)" "./doc-01.jpg ./doc-02.jpg ./doc-03.jpg " \
    "three pages: numbered, two digits at least"
check_in "$out" "./doc-01.jpg  424x600 px  q=92  9200 bytes" \
    "each page reported: path, size, quality, bytes"
check_in "$out" "./doc-03.jpg  600x424 px" "a landscape page keeps its long edge at -w"
check_in "$(log "$PDFTOPPM_LOG")" "-mono -r 72 doc.pdf" "the probe: one 72 dpi bilevel pass"
check_in "$(log "$PDFTOPPM_LOG")" \
    "-f 2 -l 2 -singlefile -scale-to 1200 -aa yes -aaVector yes doc.pdf" \
    "each page rendered at twice the target, anti-aliased"
check_in "$(log "$MAGICK_LOG")" "-filter Lanczos -resize 600x600> -strip" \
    "downsampled with Lanczos to the target box"
check_in "$(log "$CJPEG_LOG")" "-quality 92 -optimize -progressive -sample 1x1 -outfile" \
    "encoded by cjpeg at 92, optimised, progressive, 4:4:4"
check_in "$err" "cjpeg is libjpeg, not mozjpeg" "libjpeg's cjpeg: a note says so"

p2j '596x842' -w 600
check_eq "$(jpgs)" "./doc.jpg " "a one-page document: no number"
p2j '596x842' -w 600 -n always
check_eq "$(jpgs)" "./doc-01.jpg " "-n always: numbered anyway"
p2j "$three" -w 600 -n never -f 2 -l 2
check_eq "$(jpgs)" "./doc.jpg " "-n never, one page selected: no number"
pages=''
n=0
while [ "$n" -lt 120 ]; do pages="$pages 596x842"; n=$((n + 1)); done
p2j "$pages" -w 100 -f 7 -l 7
check_eq "$(jpgs)" "./doc-007.jpg " "120 pages: three digits"

p2j "$three" -w 600 -f 2 -l 3 -o out -p report
check_eq "$(jpgs)" "./out/report-02.jpg ./out/report-03.jpg " \
    "-f, -l, -o (created) and -p"
p2j "$three" -w 600 -f 4
check_rc 1 "a range past the end: exit 1"
check_in "$err" "page range selects nothing" "a range past the end: said so"

p2j '596x842' -w 600 -x 1
check_eq "$(log "$MAGICK_LOG")" "" "-x 1: nothing to downsample, magick not run"
check_in "$(log "$PDFTOPPM_LOG")" "-scale-to 600 " "-x 1: rendered at the target"
p2j '596x842' -w 600 -x 1.5
check_in "$(log "$PDFTOPPM_LOG")" "-scale-to 900 " "-x 1.5: rendered at 900"

p2j '596x842' -w 600 -g
check_in "$(log "$PDFTOPPM_LOG")" "-aaVector yes -gray doc.pdf" "-g: rendered in gray"
check_in "$(log "$MAGICK_LOG")" "raster.pgm " "-g: a PGM raster"
p2j '596x842' -w 600 -L
check_in "$(log "$MAGICK_LOG")" \
    "-colorspace RGB -filter Lanczos -resize 600x600> -colorspace sRGB -strip" \
    "-L: downsampled in linear light, back to sRGB"
p2j '596x842' -w 600 -L -g
check_in "$(log "$MAGICK_LOG")" "-colorspace Gray -strip" "-L -g: back to Gray"
p2j '596x842' -w 600 -c
check_in "$(log "$CJPEG_LOG")" "-sample 2x2" "-c: 4:2:0 chroma"

export GS_OUTPUT='P6
424 600
255
'
p2j '596x842' -w 600 -e gs
check_rc 0 "-e gs: succeeds"
check_in "$(log "$GS_ARGV")" "-dUseCropBox
-dTextAlphaBits=4
-dGraphicsAlphaBits=4
-sDEVICE=ppmraw
-r102.6128
-dFirstPage=1" "-e gs: the crop box, anti-aliasing, and 600*72*2/842 dpi"
p2j '596x842' -w 600 -e gs -g -i my.icc
check_in "$(log "$GS_ARGV")" "-sDEVICE=pgmraw
-sOutputICCProfile=my.icc
-dRenderIntent=1
-dOverrideICC" "-e gs -g -i: gray, and the ICC profile"
unset GS_OUTPUT

p2j '596x842' -w 600 -s 5000
check_rc 0 "-s 5000: succeeds"
check_in "$out" "q=50  5000 bytes" "-s 5000: the highest quality that fits"
p2j '596x842' -w 600 -s 4.9k
check_in "$out" "q=50  5000 bytes" "-s 4.9k: 5018 bytes, the same quality"
p2j '596x842' -w 600 -s 5000 -q 40
check_in "$out" "q=40  4000 bytes" "-q caps the search"
p2j '596x842' -w 600 -s 900 -q 8
check_in "$out" "q=8  800 bytes" "-q below the search floor is still the ceiling"
p2j '596x842' -w 600 -s 5kb
check_in "$out" "q=51  5100 bytes" "-s 5kb: kb is a unit, as 500kb in the Ruby version's help was"
p2j '596x842' -w 600 -x 1.0
check_in "$out" "424x600 px" "-x 1.0: rendered at the target, not resampled"
p2j '596x842' -w 600 -s 1000
check_rc 3 "-s 1000, unreachable: exit 3"
check_in "$out" "q=15  1500 bytes" "-s unreachable: written at the floor"
check_in "$err" "./doc.jpg exceeds cap at lowest quality" "-s unreachable: said so"
check_eq "$(ls -A "$TMPDIR")" "" "no temporary file is left behind"

# mozjpeg beside libjpeg's cjpeg: its own log and its own -version
mkdir -p "$tmp/moz"
printf '#!/bin/sh\nCJPEG_LOG=%s CJPEG_VERSION=%s exec %s "$@"\n' \
    "$tmp/moz.log" "'mozjpeg version 4.1.5'" "$fakes/cjpeg" \
    > "$tmp/moz/mozjpeg-cjpeg"
chmod 755 "$tmp/moz/mozjpeg-cjpeg"
: > "$tmp/moz.log"
PATH=$tmp/moz:$base
p2j '596x842' -w 600
PATH=$base
check_rc 0 "mozjpeg: succeeds"
check_in "$(log "$tmp/moz.log")" "-quality 92" "mozjpeg: preferred to libjpeg's cjpeg"
check_eq "$(log "$CJPEG_LOG")" "" "mozjpeg: libjpeg's cjpeg not used"
check_eq "$err" "" "mozjpeg: no note"

# No cjpeg at all: the stand-ins but that one, and the caller's PATH
# without any directory holding a real one.
mkdir -p "$tmp/nocjpeg"
for f in "$fakes"/*; do
    [ "${f##*/}" = cjpeg ] || ln -sf "$f" "$tmp/nocjpeg/"
done
nocjpeg=$tmp/nocjpeg
saved_ifs=$IFS
IFS=:
for d in $ORIG_PATH; do
    [ -x "$d/cjpeg" ] || [ -x "$d/mozjpeg-cjpeg" ] || [ -x "$d/mozcjpeg" ] ||
        nocjpeg=$nocjpeg:$d
done
IFS=$saved_ifs
usable=1
for t in awk dd mktemp sed tr; do
    PATH=$nocjpeg command -v "$t" > /dev/null || usable=0
done
if [ "$usable" -eq 0 ]; then
    pass "no cjpeg: skipped, cjpeg shares a directory with base tools here"
else
    PATH=$nocjpeg
    p2j '596x842' -w 600 -x 1
    PATH=$base
    check_rc 0 "no cjpeg: succeeds"
    check_in "$(log "$MAGICK_LOG")" \
        "-quality 92 -sampling-factor 1x1 -interlace JPEG" \
        "no cjpeg: magick encodes"
    check_in "$err" "no cjpeg found, encoding with magick" "no cjpeg: a note says so"
fi

export PDFTOPPM_FAIL=1
p2j '596x842'
unset PDFTOPPM_FAIL
check_rc 1 "pdftoppm fails: exit 1"
check_in "$err" "probe failed" "pdftoppm fails: said so"

for args in '-w 0' '-w x' '-q 0' '-q 101' '-x 0' '-x abc' '-x 0.5' \
    '-s abc' '-s 500kg' '-s 1.5mx' '-n sometimes' '-e cairo' '-i my.icc' \
    '-f 0' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    p2j "$three" $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(log "$PDFTOPPM_LOG")" "" "refuses [$args]: nothing rendered"
done
p2j "$three" -n never
check_rc 2 "-n never across three pages: a usage error"
check_eq "$(jpgs)" "" "-n never across three pages: nothing written"
run pdf2jpg
check_rc 2 "no PDF: a usage error"
run pdf2jpg "$tmp/none.pdf"
check_rc 1 "a missing PDF: exit 1"
run pdf2jpg -h
check_rc 0 "-h: help"

finish
