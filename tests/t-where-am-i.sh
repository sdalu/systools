#!/bin/sh
# where-am-i: the place for an associated SSID from the configuration,
# unknown otherwise, on FreeBSD (real ifconfig output in tests/data/) and
# on Linux (iw, else wpa_cli, over a sysfs tree), the interface chosen,
# the wired facts -v reports, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

data=$top/tests/data
export IFCONFIG_DIR="$tmp/ifconfig" ROUTE_LOG="$tmp/route.log" \
    IP_LOG="$tmp/ip.log" IW_DIR="$tmp/iw" IW_LOG="$tmp/iw.log" \
    WPA_DIR="$tmp/wpa" WPA_LOG="$tmp/wpa.log" SYSFS="$tmp/sys" \
    XDG_CONFIG_HOME="$tmp/config" FAKE_UNAME=FreeBSD
unset WHERE_AM_I_CONFIG ROUTE_OUTPUT IP_OUTPUT
mkdir -p "$IFCONFIG_DIR" "$IW_DIR" "$WPA_DIR" "$XDG_CONFIG_HOME"
conf=$XDG_CONFIG_HOME/where-am-i
cat -- "$data/ifconfig-wlan0.txt" > "$IFCONFIG_DIR/wlan0"
printf 'wlan0\n' > "$IFCONFIG_DIR/group.wlan"
printf '%s\n' '# place  ssid' '' 'home rezo_zero' 'work  eduroam' \
    'cafe Café Wi Fi  ' 'rezo  rezo' > "$conf"

wai() {
    : > "$ROUTE_LOG"
    : > "$IP_LOG"
    : > "$IW_LOG"
    : > "$WPA_LOG"
    run where-am-i "$@"
}
# ssid NAME — wlan0 associated with NAME
ssid() {
    sed "s/^\([[:space:]]*ssid \)rezo_zero /\1$1 /" "$data/ifconfig-wlan0.txt" \
        > "$IFCONFIG_DIR/wlan0"
}

wai
check_rc 0 "FreeBSD, a known SSID: exit 0"
check_eq "$out" home "FreeBSD, a known SSID: its place"
check_eq "$err" "" "FreeBSD: nothing on stderr without -v"
check_eq "$(cat "$ROUTE_LOG")" "" "without -v: no wired facts gathered"
ssid eduroam
wai
check_eq "$out" work "FreeBSD: another place"
ssid 'Café Wi Fi'
wai
check_eq "$out" cafe "an SSID with spaces, trailing blanks in the configuration"
ssid rezo_zero_5G
wai
check_rc 1 "an SSID not configured: exit 1"
check_eq "$out" unknown "an SSID not configured: unknown, no prefix match"

sed 's/status: associated/status: no carrier/' "$data/ifconfig-wlan0.txt" \
    > "$IFCONFIG_DIR/wlan0"
wai
check_rc 1 "not associated: exit 1"
check_eq "$out" unknown "not associated: a known SSID is not trusted"

printf 'wlan0\nwlan1\n' > "$IFCONFIG_DIR/group.wlan"
cat -- "$data/ifconfig-wlan0.txt" > "$IFCONFIG_DIR/wlan1"
wai
check_eq "$out" home "the first associated member of the wlan group"
wai -i wlan0
check_eq "$out" unknown "-i: that interface only"
rm -f -- "$IFCONFIG_DIR/wlan1"
printf 'wlan0\n' > "$IFCONFIG_DIR/group.wlan"
cat -- "$data/ifconfig-wlan0.txt" > "$IFCONFIG_DIR/wlan0"
wai -i wlan9
check_rc 1 "-i, an interface that does not exist: exit 1"
: > "$IFCONFIG_DIR/group.wlan"
wai
check_eq "$out" unknown "no wireless interface: unknown"
printf 'wlan0\n' > "$IFCONFIG_DIR/group.wlan"

printf '#gone rezo_zero\n' > "$tmp/commented"
wai -c "$tmp/commented"
check_eq "$out" unknown "a commented-out line is not read"

wai -q
check_rc 0 "-q: exit 0"
check_eq "$out" "" "-q: nothing printed"

mv -- "$conf" "$tmp/elsewhere"
wai -v
check_eq "$out" unknown "no configuration: unknown"
check_in "$err" "no configuration in $conf" "no configuration: -v says where it looked"
wai -c "$tmp/elsewhere"
check_eq "$out" home "-c names the configuration"
export WHERE_AM_I_CONFIG="$tmp/elsewhere"
wai
check_eq "$out" home "\$WHERE_AM_I_CONFIG names it"
printf 'other rezo_zero\n' > "$tmp/third"
wai -c "$tmp/third"
unset WHERE_AM_I_CONFIG
check_eq "$out" other "-c before \$WHERE_AM_I_CONFIG"
mv -- "$tmp/elsewhere" "$conf"

ROUTE_OUTPUT=$(cat "$data/route-get-default.txt")
export ROUTE_OUTPUT
cat -- "$data/ifconfig-net0-lagg.txt" > "$IFCONFIG_DIR/net0"
wai -v
check_eq "$out" home "-v: the answer unchanged"
check_in "$err" "wifi: wlan0 associated with ssid rezo_zero: home" "-v: the SSID and its place"
check_in "$err" "wire: if=net0 ip=192.168.1.10 port=wlan0" \
    "-v, FreeBSD: the default route's interface, address and active lagg port"
check_in "$(cat "$ROUTE_LOG")" "-n get default" "-v, FreeBSD: route asked for the default"
unset ROUTE_OUTPUT
wai -v
check_in "$err" "wire: if=none ip=none port=none" "-v, no default route: none"

# Linux: wlp2s0 is wireless, eth0 is not.
export FAKE_UNAME=Linux
mkdir -p "$SYSFS/class/net/wlp2s0/wireless" "$SYSFS/class/net/eth0"
printf '%s\n' 'Connected to 02:00:00:00:00:03 (on wlp2s0)' \
    '	SSID: eduroam' '	freq: 5180' > "$IW_DIR/wlp2s0"
wai
check_rc 0 "Linux, iw, a known SSID: exit 0"
check_eq "$out" work "Linux, iw: its place"
check_eq "$(cat "$IW_LOG")" "dev wlp2s0 link" "Linux: only the wireless interface asked"
rm -f -- "$IW_DIR/wlp2s0"
wai
check_rc 1 "Linux, iw, not connected: exit 1"
check_eq "$out" unknown "Linux, iw, not connected: unknown"
mkdir -p "$SYSFS/class/net/wlp3s0/wireless"
printf '%s\n' 'Connected to 02:00:00:00:00:04 (on wlp3s0)' \
    '	SSID: eduroam' > "$IW_DIR/wlp3s0"
wai
check_eq "$out" work "Linux: past one not connected to the next"
rm -rf -- "$SYSFS/class/net/wlp3s0" "$IW_DIR/wlp3s0"

mv -- "$SYSFS/class/net/wlp2s0/wireless" "$tmp/wireless"
wai
check_eq "$(cat "$IW_LOG")" "" "Linux, no wireless interface: iw not asked"
mv -- "$tmp/wireless" "$SYSFS/class/net/wlp2s0/wireless"

export IP_OUTPUT='192.0.2.1 via 192.168.1.254 dev bond0 src 192.168.1.20 uid 1000'
mkdir -p "$SYSFS/class/net/bond0/bonding"
printf 'eth0\n' > "$SYSFS/class/net/bond0/bonding/active_slave"
wai -v
unset IP_OUTPUT
check_in "$err" "wire: if=bond0 ip=192.168.1.20 port=eth0" \
    "-v, Linux: the route's interface, source address and active bond port"
check_in "$(cat "$IP_LOG")" "-4 route get" "-v, Linux: ip asked for a route"

# Without iw: wpa_cli.  The tool appends /sbin, /usr/sbin and
# /usr/local/bin to PATH, so an iw there cannot be hidden from it.
mkdir -p "$tmp/noiw"
for f in "$fakes"/*; do
    [ "${f##*/}" = iw ] || ln -sf "$f" "$tmp/noiw/"
done
# awk too, from wherever it is found: under the Linux layer, not /usr/bin.
ln -sf "$(command -v awk)" "$tmp/noiw/awk"
sbin=/sbin:/usr/sbin:/usr/local/bin
PATH=$tmp/noiw:/bin:/usr/bin
if PATH=$PATH:$sbin command -v iw > /dev/null; then
    PATH=$fakes:$ORIG_PATH
    pass "Linux, no iw: skipped, this host has iw in /sbin, /usr/sbin or /usr/local/bin"
else
    printf '%s\n' 'bssid=02:00:00:00:00:03' 'ssid=rezo_zero' \
        'wpa_state=COMPLETED' > "$WPA_DIR/wlp2s0"
    wai
    check_eq "$out" home "Linux, no iw: wpa_cli, completed"
    check_eq "$(cat "$WPA_LOG")" "-i wlp2s0 status" "Linux, no iw: wpa_cli asked"
    sed 's/COMPLETED/SCANNING/' "$WPA_DIR/wlp2s0" > "$WPA_DIR/x" &&
        mv -- "$WPA_DIR/x" "$WPA_DIR/wlp2s0"
    wai
    check_eq "$out" unknown "Linux, no iw: wpa_cli, scanning: unknown"
    rm -f -- "$tmp/noiw/wpa_cli"
    if PATH=$PATH:$sbin command -v wpa_cli > /dev/null; then
        pass "Linux, neither: skipped, this host has wpa_cli in /sbin, /usr/sbin or /usr/local/bin"
    else
        wai -v
        check_eq "$out" unknown "Linux, neither iw nor wpa_cli: unknown"
        check_in "$err" "neither iw nor wpa_cli to ask wlp2s0" "Linux, neither: -v says so"
    fi
    PATH=$fakes:$ORIG_PATH
fi

export FAKE_UNAME=SunOS
wai
check_rc 1 "an unsupported platform: exit 1"
check_eq "$out" unknown "an unsupported platform: unknown"
check_in "$err" "unsupported platform: SunOS" "an unsupported platform: said so"
export FAKE_UNAME=FreeBSD

for args in 'extra' '-z' '-c' '-i'; do
    # shellcheck disable=SC2086  # each case is a word list
    wai $args
    check_rc 2 "refuses [$args] as a usage error"
done
run where-am-i -h
check_rc 0 "-h: help"

finish
