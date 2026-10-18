#!/bin/sh
# default-gateway: both platforms' parsers, the options as each tool
# receives them, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

export ROUTE_LOG="$tmp/route.log" IP_LOG="$tmp/ip.log"

# freebsd OUTPUT ARG... — run as FreeBSD with route(8) answering OUTPUT
freebsd() {
    export FAKE_UNAME=FreeBSD ROUTE_OUTPUT="$1"
    shift
    : > "$ROUTE_LOG"
    run default-gateway "$@"
}

# linux OUTPUT ARG... — run as Linux with ip(8) answering OUTPUT
linux() {
    export FAKE_UNAME=Linux IP_OUTPUT="$1"
    shift
    : > "$IP_LOG"
    run default-gateway "$@"
}

route_v4='   route to: 0.0.0.0
destination: 0.0.0.0
       mask: 0.0.0.0
    gateway: 192.0.2.1
        fib: 0
  interface: em0
      flags: <UP,GATEWAY,DONE,STATIC>'
route_v6='   route to: ::
destination: ::
    gateway: fe80::1%em0
  interface: em0'
route_tunnel='   route to: 0.0.0.0
destination: 0.0.0.0
  interface: wg0
      flags: <UP,DONE,STATIC>'

freebsd "$route_v4"
check_rc 0 "FreeBSD: found"
check_eq "$out" "192.0.2.1" "FreeBSD: the gateway"
check_eq "$(cat "$ROUTE_LOG")" "-n get -inet default" "FreeBSD: asks route for the IPv4 default"
freebsd "$route_v4" -i
check_eq "$out" "192.0.2.1 em0" "FreeBSD -i: gateway and interface"
freebsd "$route_v4" -f 2
check_eq "$(cat "$ROUTE_LOG")" "-n get -fib 2 -inet default" "FreeBSD -f: the FIB reaches route"
freebsd "$route_v6" -6
check_eq "$out" "fe80::1%em0" "FreeBSD -6: link-local keeps its one scope"
check_eq "$(cat "$ROUTE_LOG")" "-n get -inet6 default" "FreeBSD -6: asks for the IPv6 default"
freebsd "$route_tunnel" -i
check_eq "$out" "wg0 wg0" "FreeBSD: no gateway prints the interface, both columns"
export ROUTE_EXIT=1
freebsd ''
unset ROUTE_EXIT
check_rc 1 "FreeBSD: no default route is exit 1"
check_in "$err" "no IPv4 default route" "FreeBSD: no default route said so"

linux 'default via 192.0.2.1 dev eth0 proto dhcp metric 100'
check_rc 0 "Linux: found"
check_eq "$out" "192.0.2.1" "Linux: the gateway"
check_eq "$(cat "$IP_LOG")" "-4 route show default" "Linux: asks ip for the IPv4 default"
linux 'default via 192.0.2.1 dev eth0' -f 100
check_eq "$(cat "$IP_LOG")" "-4 route show default table 100" "Linux -f: the table reaches ip"
linux 'default via fe80::1 dev eth0 proto ra metric 1024' -6 -i
check_eq "$out" "fe80::1%eth0 eth0" "Linux -6: link-local gains its scope"
linux 'default proto static metric 100
	nexthop via 192.0.2.1 dev eth0 weight 1
	nexthop via 192.0.2.2 dev eth1 weight 1' -i
check_eq "$out" "192.0.2.1 eth0" "Linux: multipath gives the first nexthop"
linux 'default via inet6 fe80::1 dev eth0 proto bird'
check_eq "$out" "fe80::1%eth0" "Linux: an IPv6 nexthop of an IPv4 route"
linux 'default dev wg0 scope link
default via 192.0.2.1 dev eth0 metric 600' -i
check_eq "$out" "wg0 wg0" "Linux: the first route wins, even without a gateway"
linux ''
check_rc 1 "Linux: no default route is exit 1"

freebsd "$route_v4" -s
check_eq "$(wc -c < "$tmp/out" | tr -d ' ')" 9 "-s: no trailing newline"
freebsd "$route_v4"
check_eq "$(wc -c < "$tmp/out" | tr -d ' ')" 10 "without -s: a trailing newline"

export FAKE_UNAME=Plan9
run default-gateway
check_rc 1 "an unknown platform: exit 1"
check_in "$err" "unsupported platform: Plan9" "an unknown platform: named"

for args in '-f x' '-f 1a' 'extra' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    freebsd "$route_v4" $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(cat "$ROUTE_LOG")" "" "refuses [$args]: route is not asked"
done

finish
