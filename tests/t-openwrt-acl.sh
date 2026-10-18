#!/bin/sh
# openwrt-acl: what the local half sends the router, the table it makes
# of the router's answer and what it refuses before calling ssh; then the
# router's half, run here against stand-ins.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export SSH_ARGV="$tmp/ssh.argv" SSH_OUTPUT="$tmp/records"
tab=$(printf '\t')
cat > "$SSH_OUTPUT" <<EOF
iface${tab}w0${tab}wlan0${tab}allow${tab}2.4
iface${tab}w1${tab}wlan1${tab}allow${tab}5
name${tab}aa:bb:cc:dd:ee:01${tab}phone
name${tab}aa:bb:cc:dd:ee:02${tab}laptop
mac${tab}w0${tab}aa:bb:cc:dd:ee:01
mac${tab}w1${tab}aa:bb:cc:dd:ee:01
mac${tab}w0${tab}aa:bb:cc:dd:ee:02
mac${tab}w0${tab}aa:bb:cc:dd:ee:03
EOF

acl() {
    rm -f -- "$SSH_ARGV"
    run openwrt-acl "$@"
}
sent() {
    cat -- "$SSH_ARGV" 2> /dev/null
}

acl -H router -s home list
check_rc 0 "list: succeeds"
check_in "$(sent)" "router" "list: the host given with -H"
check_in "$(sent)" "sh -s -- 'home' 'dump' '0' '0' '0' 'all'" \
    "list: the SSID and the defaults reach the remote helper"
check_in "$out" "home on router" "list: the heading"
check_in "$out" "aa:bb:cc:dd:ee:01   phone                   yes      yes" \
    "list: a device on both bands"
check_in "$out" "aa:bb:cc:dd:ee:02   laptop                  yes      -         confined" \
    "list: a device on one band is marked confined"
check_in "$out" "aa:bb:cc:dd:ee:03   ?" "list: a device with no name"

acl -n -b 5GHz add AA-BB-CC-DD-EE-FF aabbccddee00 phone
check_rc 0 "add: succeeds"
check_in "$(sent)" "'add' '1' '0' '0' '5' 'aa:bb:cc:dd:ee:ff' 'aa:bb:cc:dd:ee:00' 'phone'" \
    "add: MACs normalised, a name passed for the router, -n and -b 5GHz as 5"

acl -s "it's" list
check_in "$(sent)" "'it'\\''s'" "an SSID with a quote is quoted for the remote shell"

acl -n -b 6g add aa:bb:cc:dd:ee:ff
check_in "$(sent)" "'add' '1' '0' '0' '6' " "-b 6g is 6"

for args in '-b 7 list' 'add' "add bad!name" 'add aa:bb:cc' 'del' \
    'list extra' 'clients extra' 'frob' '-f -l add aa:bb:cc:dd:ee:ff' '' \
    '-z list'; do
    # shellcheck disable=SC2086  # each case is a word list
    acl $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(sent)" "" "refuses [$args]: before calling ssh"
done

# --- the router's half -------------------------------------------------
# The script openwrt-acl sends over ssh, lifted out of it and run here
# against stand-ins for uci, ubus, jsonfilter and wifi.  Its arguments:
# ssid verb dry full defer band [mac...].

sed -n "/<<'REMOTE'\$/,/^REMOTE\$/p" "$top/bin/openwrt-acl" | sed '1d;$d' \
    > "$tmp/remote.sh"
export UCI_STATE="$tmp/uci" UCI_LOG="$tmp/uci.log" UBUS_LOG="$tmp/ubus.log" \
    WIFI_LOG="$tmp/wifi.log" HOSTAPD_RUN_DIR="$tmp/run" \
    JSONFILTER_OUTPUT='sec0
wlan0
sec1
wlan1'
router() {
    cat > "$UCI_STATE" <<EOF
wireless.radio0.band 2g
wireless.radio1.band 5g
wireless.sec0.device radio0
wireless.sec0.ssid home
wireless.sec0.macfilter allow
wireless.sec0.maclist AA-BB-CC-DD-EE-01
wireless.sec0.maclist aa:bb:cc:dd:ee:02
wireless.sec1.device radio1
wireless.sec1.ssid home
wireless.sec1.macfilter allow
wireless.sec1.maclist AABBCCDDEE01
EOF
    rm -rf -- "$HOSTAPD_RUN_DIR"
    mkdir -p "$HOSTAPD_RUN_DIR"
    : > "$HOSTAPD_RUN_DIR/hostapd-wlan0.maclist"
    : > "$HOSTAPD_RUN_DIR/hostapd-wlan1.maclist"
    : > "$UCI_LOG"
    unset UBUS_EXIT JSONFILTER_EXIT
}
remote() {
    rc=0
    # shellcheck disable=SC2086  # SH may carry options
    $SH "$tmp/remote.sh" "$@" > "$tmp/out" 2> "$tmp/err" || rc=$?
    out=$(cat "$tmp/out")
    err=$(cat "$tmp/err")
}

router
remote home dump 0 0 0 all
check_rc 0 "dump: succeeds"
check_in "$out" "mac${tab}sec0${tab}aa:bb:cc:dd:ee:01" \
    "an entry stored as AA-BB-CC-DD-EE-01 is listed as aa:bb:cc:dd:ee:01"
check_in "$out" "mac${tab}sec1${tab}aa:bb:cc:dd:ee:01" \
    "and one stored as AABBCCDDEE01 too, so both bands show one device"

router
remote home del 1 0 0 all aa:bb:cc:dd:ee:01
check_in "$out" "- sec0 AA-BB-CC-DD-EE-01" "del: finds an entry spelt with dashes"
check_in "$out" "- sec1 AABBCCDDEE01" "del: and one with no separators, by its stored spelling"
router
remote home add 1 0 0 all aa:bb:cc:dd:ee:01
check_eq "$out" "nothing to change" "add: a device already there in another spelling is not added twice"

router
remote home add 0 0 0 all aa:bb:cc:dd:ee:09
check_rc 0 "add, applied: succeeds"
check_in "$out" "committed; reloading home" "add: the BSSes carrying the SSID reloaded, not all wifi"
check_in "$(cat "$UCI_LOG")" "add_list wireless.sec0.maclist=aa:bb:cc:dd:ee:09" "add: committed to uci"
check_in "$(cat "$HOSTAPD_RUN_DIR/hostapd-wlan1.maclist")" "aa:bb:cc:dd:ee:09" \
    "add: hostapd's accept-list file rewritten"
check_eq "$(cat "$HOSTAPD_RUN_DIR/hostapd-wlan1.maclist")" "aa:bb:cc:dd:ee:01
aa:bb:cc:dd:ee:09" "add: hostapd is given each MAC as aa:bb:cc:dd:ee:ff"

router
sed 's/ssid home$/ssid Home\/Guest [1]/' "$UCI_STATE" > "$UCI_STATE.new"
mv -- "$UCI_STATE.new" "$UCI_STATE"
remote 'Home/Guest [1]' dump 0 0 0 all
check_rc 0 "an SSID with a / and brackets: found"
check_in "$out" "iface${tab}sec1${tab}wlan1" "an SSID with a /: both radios"
remote 'Home' dump 0 0 0 all
check_rc 1 "an SSID is matched whole, not as a prefix"

router
rm -f -- "$HOSTAPD_RUN_DIR/hostapd-wlan1.maclist"
remote home add 0 0 0 all aa:bb:cc:dd:ee:09
check_rc 0 "no accept-list file for one BSS: still committed"
check_in "$out" "not applied" "no accept-list file: not applied rather than a full reload"
check_not_in "$out" "full wifi reload" "no accept-list file: no full reload without -f"
router
remote home add 0 1 0 all aa:bb:cc:dd:ee:09
check_in "$out" "committed; full wifi reload" "-f: the full reload"

router
export UBUS_EXIT=1
remote home add 0 0 0 all aa:bb:cc:dd:ee:09
check_rc 1 "ubus fails: exit 1"
check_in "$err" "ubus cannot report the wireless status" "ubus fails: said so"
check_eq "$(cat "$UCI_LOG")" "" "ubus fails: nothing committed"
router
export JSONFILTER_EXIT=1
remote home clients 0 0 0 all
check_rc 1 "jsonfilter fails: exit 1, not a report of no clients"
check_in "$err" "jsonfilter cannot read the wireless status" "jsonfilter fails: said so"
unset JSONFILTER_EXIT

finish
