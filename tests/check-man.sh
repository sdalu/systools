#!/bin/sh
# check-man.sh — every tool has a man page, and each page offers exactly
# the options its tool takes
# usage: sh tests/check-man.sh
#
# A tool's options are the letters of its getopts string; for one that
# parses its arguments itself (with-gnu-make), the "-x)" and "-x|--long)"
# patterns of its case statements; and for a Ruby tool (caldav, carddav),
# the "-x" and "--long" of its OptionParser "op.on" lines.  An option's
# canonical name is its short one, or its long one when it has no short.
# A page's options are read twice: every .Fl in SYNOPSIS must be the
# tool's canonical names, no more and no fewer, and the .Fl of the .It
# lines of OPTIONS every name the tool takes, short and long; so an
# option added to the script and not to its page -- or the other way
# round -- fails here.
# The page's .Dt and .Nm must name the tool, the page must be ASCII, and
# mandoc -Tlint must find nothing down to its style suggestions, except
# what depends on the pages this host has installed -- a page referred
# to that is not there, an index that is out of date: whether curl(1)
# is installed is not a fact about the page.
# 'local' is not POSIX, but every shell this runs under has it
# shellcheck disable=SC3043
set -u

cd -- "$(dirname -- "$0")/.." || exit 1
: "${MANDOC:=mandoc}"

bad=0
complain() {
    printf 'check-man: %s\n' "$*" >&2
    bad=1
}

# tokens: the option words on stdin ("-abc", a getopts cluster, or
# "--long"), one option each, sorted, on one line: "--long -a -b -c".
tokens() {
    awk '/^--/ { print; next }
        /^-/ { for (i = 2; i <= length($0); i++) print "-" substr($0, i, 1) }' |
        sort -u | tr '\n' ' ' | sed 's/ $//'
}

# differ PAGE TOOL: what PAGE's options lack and add, against TOOL's.
differ() {
    printf '%s\n' "$1" "$2" | awk '
        NR == 1 { for (i = 1; i <= NF; i++) page[$i] = 1 }
        NR == 2 { for (i = 1; i <= NF; i++) { tool[$i] = 1
                      if (!($i in page)) lacks = lacks " " $i } }
        END { for (o in page) if (!(o in tool)) adds = adds " " o
              if (lacks != "") printf "lacks%s", lacks
              if (lacks != "" && adds != "") printf "; "
              if (adds != "") printf "has%s, which the tool does not take", adds }'
}

# script_options TOOL all|canonical: the options TOOL takes, every name
# or one name each.
script_options() {
    local spec
    case $(sed -n 1p "$1") in
    *ruby*)
        grep '^ *op\.on ' "$1" | while IFS= read -r line; do
            words=$(printf '%s\n' "$line" |
                grep -o '"--*[A-Za-z][-A-Za-z0-9]*' | tr -d '"')
            name_options "$2" "$words"
        done | tokens
        return
        ;;
    esac
    spec=$(sed -n 's/.*while getopts \([^ ]*\) .*/\1/p' "$1" | head -n 1)
    if [ -n "$spec" ]; then
        printf -- '-%s\n' "$spec" | tr -d "':\"" | tokens
        return
    fi
    sed -n 's/^ *\(--*[A-Za-z0-9][-|A-Za-z0-9]*\)).*/\1/p' "$1" |
        while IFS= read -r line; do
            name_options "$2" "$(printf '%s\n' "$line" | tr '|' '\n')"
        done | tokens
}

# name_options all|canonical WORDS: the names of one option, given one a
# line: all of them, or the short one, else the first.
name_options() {
    if [ "$1" = all ]; then
        printf '%s\n' "$2"
    else
        printf '%s\n' "$2" | awk '!/^--/ { print; found = 1; exit }
            NR == 1 { first = $0 }
            END { if (!found) print first }'
    fi
}

# page_options PAGE SECTION: the options SECTION names: in SYNOPSIS
# every .Fl, in OPTIONS every .Fl of an .It line.
page_options() {
    awk -v want="$2" '
        /^\.Sh / { sub(/^\.Sh /, ""); section = $0; next }
        section != want { next }
        want == "OPTIONS" && $1 != ".It" { next }
        {
            for (i = 1; i < NF; i++)
                if (($i == "Fl" || $i == ".Fl") &&
                    $(i + 1) ~ /^-?[A-Za-z0-9][-A-Za-z0-9]*$/)
                    print "-" $(i + 1)
        }' "$1" | tokens
}

for tool in bin/*; do
    name=${tool#bin/}
    page=man/$name.1
    if [ ! -f "$page" ]; then
        complain "$name: no page $page"
        continue
    fi
    canonical=$(script_options "$tool" canonical)
    every=$(script_options "$tool" all)
    synopsis=$(page_options "$page" SYNOPSIS)
    options=$(page_options "$page" OPTIONS)
    [ "$synopsis" = "$canonical" ] ||
        complain "$page: SYNOPSIS $(differ "$synopsis" "$canonical")"
    [ "$options" = "$every" ] ||
        complain "$page: OPTIONS $(differ "$options" "$every")"
    upper=$(printf '%s\n' "$name" | tr '[:lower:]' '[:upper:]')
    grep -q "^\.Dt $upper 1\$" "$page" ||
        complain "$page: no .Dt $upper 1"
    grep -q "^\.Nm $name\$" "$page" || complain "$page: no .Nm $name"
    # groff, which renders man pages on most Linux systems, reads a raw
    # UTF-8 byte as an invalid character: an accent is an escape, \(:o.
    LC_ALL=C grep -n '[^ -~	]' "$page" > /dev/null &&
        complain "$page: a byte outside ASCII; write it as a groff escape"
    lint=$("$MANDOC" -Tlint -Wstyle "$page" 2>&1 |
        grep -v -e 'referenced manual not found' -e 'outdated mandoc.db')
    [ -z "$lint" ] || complain "$page: mandoc -Tlint:
$lint"
done
for page in man/*.1; do
    [ -e "$page" ] || continue
    name=${page#man/}
    name=${name%.1}
    [ -f "bin/$name" ] || complain "$page: no tool bin/$name"
done

[ "$bad" -eq 0 ] && printf 'check-man: every tool has a page offering its options\n'
exit "$bad"
