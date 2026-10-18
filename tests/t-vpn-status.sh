#!/bin/sh
# vpn-status: each source of a label, the FIB/VRF suffix, a dead tunnel
# told from one wg cannot ask about, the polybar form, on both
# platforms, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export IFCONFIG_DIR="$tmp/ifconfig" WG_DIR="$tmp/wg" PS_DIR="$tmp/ps" \
    VPN_STATUS_COLORS="$tmp/none"
reset() {
    rm -rf -- "$IFCONFIG_DIR" "$WG_DIR" "$PS_DIR" "$tmp/sys" "$tmp/proc"
    mkdir -p "$IFCONFIG_DIR" "$WG_DIR" "$PS_DIR"
    unset WG_EXIT VPN_STATUS_RED
}
# group NAME IF..., iface IF TEXT, shakes IF AGE, endpoint IF ADDRESS
group() {
    g=$1
    shift
    printf '%s\n' "$@" > "$IFCONFIG_DIR/group.$g"
}
iface() {
    printf '%s\n' "$2" > "$IFCONFIG_DIR/$1"
}
shakes() {
    printf 'KEY= %s\n' "$2" > "$WG_DIR/$1.latest-handshakes"
}
endpoint() {
    printf 'KEY=\t%s\n' "$2" > "$WG_DIR/$1.endpoints"
}

# --- FreeBSD -----------------------------------------------------------

export FAKE_UNAME=FreeBSD
mullvad='vpn0: flags=10080c1<UP,RUNNING,NOARP,MULTICAST,LOWER_UP> metric 0 mtu 1420
	description: mullvad (External VPN)
	options=80000<LINKSTATE>
	inet 10.64.32.33 netmask 0xffffffff
	groups: wg vpn
	fib: 1
	nd6 options=101<PERFORMNUD,NO_DAD>'
insa='tun0: flags=1008051<UP,POINTOPOINT,RUNNING,MULTICAST,LOWER_UP> metric 0 mtu 1303
	options=80000<LINKSTATE>
	inet 172.29.163.150 --> 172.29.163.151 netmask 0xffffffff
	groups: tun
	nd6 options=21<PERFORMNUD,AUTO_LINKLOCAL>
	Opened by PID 94488'
freebsd() {
    reset
    group wg vpn0
    group vpn vpn0
    group tun tun0
    iface vpn0 "$mullvad"
    iface tun0 "$insa"
    shakes vpn0 30
    printf 'openconnect --protocol=anyconnect --authgroup=INSA vpn.insa.fr\n' \
        > "$PS_DIR/94488"
}

freebsd
run vpn-status
check_rc 0 "FreeBSD: succeeds"
check_eq "$out" "mullvad/1 INSA" \
    "FreeBSD: description, FIB, and openconnect's --authgroup; vpn0 once"

shakes vpn0 400
run vpn-status
check_eq "$out" "mullvad/1! INSA" "no handshake for 400 s: dead, with a !"
run vpn-status -p
check_eq "$out" "%{F#dc322f}mullvad/1%{F-} INSA" "-p: dead in polybar's red, no !"
export VPN_STATUS_RED='#ff0000'
run vpn-status -p
check_eq "$out" "%{F#ff0000}mullvad/1%{F-} INSA" "-p: \$VPN_STATUS_RED wins"
unset VPN_STATUS_RED
printf 'red="#aa0000"\n' > "$tmp/colors.sh"
export VPN_STATUS_COLORS="$tmp/colors.sh"
run vpn-status -p
check_eq "$out" "%{F#aa0000}mullvad/1%{F-} INSA" "-p: else the red of colors.sh"
export VPN_STATUS_COLORS="$tmp/none"
shakes vpn0 never
run vpn-status
check_eq "$out" "mullvad/1! INSA" "never a handshake: dead"
export WG_EXIT=1
run vpn-status
check_eq "$out" "mullvad/1 INSA" "wg cannot be asked: no ! for it"
unset WG_EXIT

freebsd
iface vpn0 "$(printf '%s\n' "$mullvad" | grep -v -e description -e fib:)"
endpoint vpn0 '185.195.232.66:51820'
run vpn-status
check_eq "$out" "185.195.232.66 INSA" "no description: the WireGuard endpoint, port dropped"
endpoint vpn0 '[2a03:1b20:3:f011::a01f]:51820'
run vpn-status
check_eq "$out" "2a03:1b20:3:f011::a01f INSA" "an IPv6 endpoint, brackets dropped"
rm -f -- "$WG_DIR/vpn0.endpoints"
run vpn-status
check_eq "$out" "vpn0 INSA" "nothing else: the interface name"

freebsd
printf 'openconnect vpn.insa.fr --authgroup INSA\n' > "$PS_DIR/94488"
run vpn-status
check_eq "$out" "mullvad/1 INSA" "--authgroup as two words, wherever it is"
printf '/usr/local/sbin/openvpn --config /etc/* --daemon\n' > "$PS_DIR/94488"
run vpn-status
check_eq "$out" "mullvad/1 /etc/*" \
    "no --authgroup: the first non-option argument, never glob-expanded"
printf '/usr/local/sbin/openvpn --daemon\n' > "$PS_DIR/94488"
run vpn-status
check_eq "$out" "mullvad/1 openvpn" "no argument: the process's name"
rm -f -- "$PS_DIR/94488"
run vpn-status
check_eq "$out" "mullvad/1 tun0" "the process is gone: the interface name"

freebsd
iface tun0 "$(printf '%s\n' "$insa" | sed 's/UP,POINTOPOINT,RUNNING/UP,POINTOPOINT/')"
run vpn-status
check_eq "$out" "mullvad/1" "an interface UP but not RUNNING is not a tunnel"
iface vpn0 "$(printf '%s\n' "$mullvad" | sed 's/<UP,RUNNING/<RUNNING/')"
run vpn-status
check_eq "$out" "" "no tunnel: nothing"
run vpn-status -p
check_eq "$out" "%{F#dc322f}none%{F-}" "no tunnel, -p: a red none"

# --- Linux -------------------------------------------------------------

export FAKE_UNAME=Linux SYSFS="$tmp/sys" PROCFS="$tmp/proc"
# net IF FLAGS [wireguard|tun|vrf]
net() {
    mkdir -p "$SYSFS/class/net/$1"
    printf '%s\n' "$2" > "$SYSFS/class/net/$1/flags"
    case ${3-} in
    wireguard | vrf)
        printf 'DEVTYPE=%s\nINTERFACE=%s\n' "$3" "$1" > "$SYSFS/class/net/$1/uevent"
        ;;
    tun)
        printf 'INTERFACE=%s\n' "$1" > "$SYSFS/class/net/$1/uevent"
        printf '0x1002\n' > "$SYSFS/class/net/$1/tun_flags"
        ;;
    *)
        printf 'INTERFACE=%s\n' "$1" > "$SYSFS/class/net/$1/uevent"
        ;;
    esac
}
linux() {
    reset
    net eth0 0x1003
    net wg0 0x90d1 wireguard          # UP, RUNNING, POINTOPOINT, NOARP
    printf 'mullvad (External VPN)\n' > "$SYSFS/class/net/wg0/ifalias"
    shakes wg0 30
    net tun0 0x10d1 tun
    mkdir -p "$PROCFS/4242/fdinfo" "$PROCFS/self/fdinfo"
    printf 'pos:\t0\nflags:\t02\nmnt_id:\t27\n' > "$PROCFS/4242/fdinfo/3"
    printf 'pos:\t0\nflags:\t02\nmnt_id:\t27\niff:\ttun0\n' > "$PROCFS/4242/fdinfo/5"
    printf 'openconnect --authgroup=INSA vpn.insa.fr\n' > "$PS_DIR/4242"
}

linux
run vpn-status
check_rc 0 "Linux: succeeds"
check_eq "$out" "INSA mullvad" \
    "Linux, in interface order: the alias, and the tun owner found through fdinfo"

linux
net vrf-blue 0x0481 vrf
ln -s ../vrf-blue "$SYSFS/class/net/wg0/master"
run vpn-status
check_eq "$out" "INSA mullvad/vrf-blue" "Linux: a tunnel in a VRF gets the VRF's name"

linux
shakes wg0 400
run vpn-status
check_eq "$out" "INSA mullvad!" "Linux: a stale handshake is dead"
export WG_EXIT=1
run vpn-status
check_eq "$out" "INSA mullvad" "Linux without root: wg cannot be asked, no !"
unset WG_EXIT

linux
printf '0x10d0\n' > "$SYSFS/class/net/tun0/flags"
run vpn-status
check_eq "$out" "mullvad" "Linux: a tunnel that is not UP is skipped"
rm -f -- "$PROCFS/4242/fdinfo/5"
printf '0x10d1\n' > "$SYSFS/class/net/tun0/flags"
run vpn-status
check_eq "$out" "tun0 mullvad" "Linux: no owner to be seen: the interface name"

# --- both --------------------------------------------------------------

export FAKE_UNAME=Plan9
run vpn-status
check_rc 1 "an unknown platform: exit 1"
export FAKE_UNAME=FreeBSD
for args in 'extra' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    run vpn-status $args
    check_rc 2 "refuses [$args] as a usage error"
done
run vpn-status -h
check_rc 0 "-h: help"

finish
