#!/bin/sh
# do-screenshot: what maim is asked for each mode, the file it names and
# the clipboard and notification after, the rofi menu, the countdown,
# the failures that leave no file behind, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export MAIM_LOG="$tmp/maim.log" XCLIP_LOG="$tmp/xclip.log" \
    NOTIFY_LOG="$tmp/notify.log" XDOTOOL_LOG="$tmp/xdotool.log" \
    ROFI_LOG="$tmp/rofi.log" ROFI_ENTRIES="$tmp/rofi.entries"
pics=$tmp/pics

ds_() {
    : > "$MAIM_LOG"
    : > "$XCLIP_LOG"
    : > "$NOTIFY_LOG"
    : > "$XDOTOOL_LOG"
    : > "$ROFI_LOG"
    run do-screenshot "$@"
}
log() {
    cat -- "$1"
}
count_png() {
    find "$1" -name '*.png' 2> /dev/null | wc -l | tr -d ' '
}

ds_ -d "$pics" desktop
check_rc 0 "desktop: succeeds"
shot=$out
case $shot in
"$pics"/Screenshot_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9].png)
    pass "desktop: the path printed is a dated name under -d" ;;
*) fail "desktop: the path printed is a dated name under -d" ;;
esac
check_eq "$(cat -- "$shot" 2> /dev/null)" PNG "desktop: the file is what maim wrote"
check_eq "$(log "$MAIM_LOG")" "-u -f png $shot" "desktop: maim, the whole screen"
check_eq "$(log "$XCLIP_LOG")" "-selection clipboard -t image/png -i $shot" \
    "desktop: copied to the clipboard as PNG"
check_in "$(log "$NOTIFY_LOG")" "string:image-path:$shot" "desktop: announced with the image"
check_in "$(log "$NOTIFY_LOG")" "Copied to the clipboard and saved as" \
    "desktop: announced as copied"
check_eq "$(log "$XDOTOOL_LOG")" "" "desktop: no window asked for"

ds_ -d "$pics" area
check_rc 0 "area: succeeds"
check_eq "$(log "$MAIM_LOG")" "-u -f png -s $out" "area: maim selects"

ds_ -d "$pics" window
check_rc 0 "window: succeeds"
check_eq "$(log "$XDOTOOL_LOG")" "getactivewindow" "window: the active window asked for"
check_eq "$(log "$MAIM_LOG")" "-u -f png -i 4711 $out" "window: maim, that window"

# A name taken in the same second gets a suffix; retry should the second
# turn between the two.
taken=
for _ in 1 2 3; do
    rm -rf -- "$tmp/same"
    mkdir -p "$tmp/same"
    taken=$tmp/same/Screenshot_$(date +%Y-%m-%d-%H-%M-%S)
    printf 'old\n' > "$taken.png"
    ds_ -d "$tmp/same" desktop
    case $out in "$taken"*) break ;; esac
done
check_eq "$out" "$taken-2.png" "a name already taken: -2"
check_eq "$(cat -- "$taken.png")" old "a name already taken: that file untouched"

ds_ -d "$tmp/deep/er" desktop
check_rc 0 "a missing -d directory: made"
check_eq "$(count_png "$tmp/deep/er")" 1 "a missing -d directory: the file in it"

export XDG_PICTURES_DIR="$tmp/xdg"
ds_ desktop
unset XDG_PICTURES_DIR
check_eq "$(count_png "$tmp/xdg")" 1 "no -d: \$XDG_PICTURES_DIR"
export HOME="$tmp/home"
ds_ desktop
check_eq "$(count_png "$tmp/home/Pictures")" 1 "no -d, no \$XDG_PICTURES_DIR: ~/Pictures"

export ROFI_PICK=Area
ds_ -d "$pics"
check_rc 0 "menu: succeeds"
check_in "$(log "$ROFI_LOG")" "-dmenu" "menu: rofi as a dmenu"
check_eq "$(tr '\n' '|' < "$ROFI_ENTRIES")" "Desktop|Area|Window|Window, delayed|" \
    "menu: the four modes offered"
check_eq "$(log "$MAIM_LOG")" "-u -f png -s $out" "menu: the mode picked is taken"
export ROFI_PICK=
before=$(count_png "$pics")
ds_ -d "$pics"
unset ROFI_PICK
check_rc 0 "menu dismissed: exit 0"
check_eq "$(log "$MAIM_LOG")" "" "menu dismissed: maim not called"
check_eq "$out" "" "menu dismissed: no path"
check_eq "$(count_png "$pics")" "$before" "menu dismissed: no file"
ds_ -d "$pics" window
check_eq "$(log "$ROFI_LOG")" "" "a mode given: no menu"

export MAIM_FAIL=1
before=$(count_png "$pics")
ds_ -d "$pics" area
unset MAIM_FAIL
check_rc 1 "a selection cancelled: exit 1"
check_in "$err" "maim took no screenshot" "a selection cancelled: said so"
check_eq "$(count_png "$pics")" "$before" "a selection cancelled: no file left"
check_eq "$(log "$XCLIP_LOG")" "" "a selection cancelled: nothing copied"
check_eq "$(log "$NOTIFY_LOG")" "" "a selection cancelled: nothing announced"

export XDOTOOL_WINDOW=fail
ds_ -d "$pics" window
unset XDOTOOL_WINDOW
check_rc 1 "no active window: exit 1"
check_in "$err" "cannot tell the active window" "no active window: said so"
check_eq "$(log "$MAIM_LOG")" "" "no active window: maim not called"

export XCLIP_FAIL=1
ds_ -d "$pics" desktop
unset XCLIP_FAIL
check_rc 0 "xclip fails: the screenshot still stands"
check_in "$err" "xclip could not copy it" "xclip fails: said so"
check_in "$(log "$NOTIFY_LOG")" "Saved as" "xclip fails: announced as saved only"

ds_ -d "$tmp/a&b" desktop
check_in "$(log "$NOTIFY_LOG")" "file://$tmp/a&amp;b/" "markup: & escaped in the notification"
ds_ -d "$tmp/a\"b" desktop
check_in "$(log "$NOTIFY_LOG")" "file://$tmp/a&quot;b/" \
    "markup: a quote escaped, so it cannot end the href early"

ds_ -d "$pics" delay 1
check_rc 0 "delay 1: succeeds"
check_in "$(log "$NOTIFY_LOG")" "Capturing the active window in 1s" "delay 1: counted down"
check_in "$(log "$NOTIFY_LOG")" "$(printf -- '-p\n-t\n1100')" "delay 1: the countdown asks for an id"
check_in "$(log "$NOTIFY_LOG")" "$(printf -- '-r\n77\n-t\n800')" "delay 1: the countdown replaces itself"
check_in "$(log "$NOTIFY_LOG")" "$(printf -- '-r\n77\n-h\nstring:image-path:%s' "$out")" \
    "delay 1: the result replaces the countdown"
check_eq "$(log "$MAIM_LOG")" "-u -f png -i 4711 $out" "delay 1: maim, the active window"

for args in 'bogus' 'delay x' 'delay 0' 'delay -1' 'window 3' 'delay 1 2' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    ds_ -d "$pics" $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(log "$MAIM_LOG")" "" "refuses [$args]: maim not called"
done
run do-screenshot -h
check_rc 0 "-h: help"

# Without rofi, xclip and notify-send.  The tool appends /usr/local/bin
# to PATH, so ones there cannot be hidden from it.
mkdir -p "$tmp/nox"
for f in "$fakes"/*; do
    case ${f##*/} in
    rofi | xclip | notify-send) ;;
    *) ln -sf "$f" "$tmp/nox/" ;;
    esac
done
PATH=$tmp/nox:/bin:/usr/bin
found=
for t in rofi xclip notify-send; do
    PATH=$PATH:/usr/local/bin command -v "$t" > /dev/null && found="$found $t"
done
if [ -n "$found" ]; then
    PATH=$fakes:$ORIG_PATH
    pass "no rofi, xclip, notify-send: skipped, this host has$found in /bin, /usr/bin or /usr/local/bin"
else
    ds_ -d "$pics"
    check_rc 1 "no mode and no rofi: exit 1"
    check_in "$err" "no rofi to ask for one" "no mode and no rofi: said so"
    ds_ -d "$pics" desktop
    check_rc 0 "no xclip, no notify-send: the screenshot still stands"
    check_in "$err" "no xclip, so not copied" "no xclip: said so"
    check_in "$err" "no notify-send, so not announced" "no notify-send: said so"
    ds_ -d "$pics" delay 1
    check_rc 0 "no notify-send: delay still waits and shoots"
    PATH=$fakes:$ORIG_PATH
fi

finish
