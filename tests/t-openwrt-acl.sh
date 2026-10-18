#!/bin/sh
# openwrt-acl, the local half: what it sends the router, the table it
# makes of the router's answer, and what it refuses before calling ssh.
# The remote half runs on OpenWrt and is not exercised here.
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

for args in '-b 7 list' 'add' "add bad!name" 'add aa:bb:cc' 'del' \
    'list extra' 'clients extra' 'frob'; do
    # shellcheck disable=SC2086  # each case is a word list
    acl $args
    check_rc 1 "refuses [$args]"
    check_eq "$(sent)" "" "refuses [$args]: before calling ssh"
done
for args in '' '-z list'; do
    # shellcheck disable=SC2086
    acl $args
    check_rc 2 "refuses [$args] as a usage error"
done

finish
