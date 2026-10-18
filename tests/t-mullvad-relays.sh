#!/bin/sh
# mullvad-relays: when the list is downloaded and when the cache serves,
# a failed or bad download, each selection, each output, the JSON parser
# on layout and escapes, the WireGuard peer, fetch(1) without curl, and
# the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

# Nine relays of the real list, recorded 2026-10-18.
list=$(cat "$top/tests/data/mullvad-relays.json")
cache=$tmp/cache/mullvad-relays.json
export MULLVAD_RELAYS_CACHE="$cache" CURL_ARGV="$tmp/argv" \
    FETCH_ARGV="$tmp/fetch-argv" CURL_BODY="$list"

relays() {
    rm -f -- "$CURL_ARGV" "$FETCH_ARGV"
    run mullvad-relays "$@"
}
asked() {
    cat -- "$CURL_ARGV" 2> /dev/null
}
# hosts: the first column of the table, the header left out.
hosts() {
    printf '%s\n' "$out" | awk 'NR > 1 { printf "%s%s", sep, $1; sep = " " }'
}
cached() {
    mkdir -p -- "${cache%/*}"
    printf '%s\n' "$1" > "$cache"
}

# --- the cache -----------------------------------------------------------

relays
check_rc 0 "no cache: succeeds"
check_in "$(asked)" "https://api.mullvad.net/www/relays/all/" \
    "no cache: the list is downloaded"
check_in "$(asked)" "-fsS" "no cache: curl fails on an HTTP error"
check_eq "$(cat "$cache")" "$list" "no cache: the download is kept"
check_eq "$(printf '%s\n' "$out" | sed -n 1p)" \
    "HOSTNAME       COUNTRY      CITY             PROVIDER    GBPS  FLAGS" \
    "the table: a header, its columns as wide as their widest value"
check_eq "$(hosts)" "al-tia-wg-001 ar-bue-wg-001 au-syd-br-001 ch-zrh-br-001 ch-zrh-wg-001 se-got-wg-001 se-got-wg-002 se-mma-wg-001 us-lax-wg-601" \
    "the table: every relay, in the order of the list"
check_in "$out" "se-mma-wg-001  Sweden       Malmö            31173       20    owned" \
    "the table: a UTF-8 name is padded by its characters, not its bytes"
check_eq "$(ls "$tmp/cache")" "mullvad-relays.json" \
    "no cache: no temporary file left beside it"

relays -c se
check_eq "$(asked)" "" "a cache under a day old: not downloaded again"
check_rc 0 "a cache under a day old: serves"

touch -t 202001010000 "$cache"
relays -c se
check_in "$(asked)" "relays/all" "a cache a day old: downloaded again"

relays -r -c se
check_in "$(asked)" "relays/all" "-r: downloaded although the cache is fresh"

cached '[{"hostname":"xx-old-wg-001","active":true}]'
touch -t 202001010000 "$cache"
export CURL_EXIT=7
relays
check_rc 0 "download fails, a cache: still succeeds"
check_in "$err" "cannot download the relay list; using the cached one" \
    "download fails, a cache: said so"
check_eq "$(hosts)" "xx-old-wg-001" "download fails, a cache: the cache serves"
unset CURL_EXIT

export CURL_CODE=503
relays
check_eq "$(hosts)" "xx-old-wg-001" "HTTP 503: the cache serves"
unset CURL_CODE

export CURL_BODY='<html>Gateway timeout</html>'
relays
check_rc 0 "a page that is not a relay list: still succeeds"
check_in "$err" "using the cached one" "a page that is not a relay list: said so"
check_eq "$(cat "$cache")" '[{"hostname":"xx-old-wg-001","active":true}]' \
    "a page that is not a relay list: the cache is not replaced"
export CURL_BODY='[]'
relays -r
check_eq "$(hosts)" "xx-old-wg-001" "an empty list: the cache is not replaced"
check_eq "$(ls "$tmp/cache")" "mullvad-relays.json" \
    "a bad download: no temporary file left"
export CURL_BODY="$list"

rm -f -- "$cache"
export CURL_EXIT=7
relays
check_rc 1 "download fails, no cache: exit 1"
check_in "$err" "cannot download the relay list" "download fails, no cache: said so"
unset CURL_EXIT

cached '{"error":"rate limited"}'
relays
check_rc 1 "a cache that is not a list: exit 1"
check_in "$err" "not a relay list" "a cache that is not a list: said so"

# --- selection -----------------------------------------------------------

cached "$list"
relays -c se
check_eq "$(hosts)" "se-got-wg-001 se-got-wg-002 se-mma-wg-001" "-c: a country code"
relays -c SWEDEN,al
check_eq "$(hosts)" "al-tia-wg-001 se-got-wg-001 se-got-wg-002 se-mma-wg-001" \
    "-c: a name, any case, and a list"
relays -C 'got,Los Angeles, CA'
check_eq "$(hosts)" "se-got-wg-001 se-got-wg-002 us-lax-wg-601" \
    "-C: a city code, and a name holding a comma"
relays -C malmö
check_eq "$(hosts)" "se-mma-wg-001" "-C: a UTF-8 name"
relays -t br
check_eq "$(hosts)" "au-syd-br-001 ch-zrh-br-001" "-t br: the bridges"
relays -t WireGuard -c ch
check_eq "$(hosts)" "ch-zrh-wg-001" "-t: a full name, with -c"
relays -o -c ch,ar
check_eq "$(hosts)" "ch-zrh-br-001 ch-zrh-wg-001" "-o: owned by Mullvad only"
relays -d
check_eq "$(hosts)" "al-tia-wg-001" "-d: DAITA only"
relays -s 20 -p 31173 -t wg
check_eq "$(hosts)" "ch-zrh-wg-001 se-got-wg-001 se-got-wg-002 se-mma-wg-001" \
    "-s and -p: speed at least, provider"
relays -p XTOM
check_eq "$(hosts)" "us-lax-wg-601" "-p: any case"
relays se-got ch-zrh-br-001
check_eq "$(hosts)" "ch-zrh-br-001 se-got-wg-001 se-got-wg-002" \
    "hosts: a prefix, and a full name"
relays -c fr
check_rc 1 "nothing selected: exit 1"
check_in "$err" "no relay matches" "nothing selected: said so"
check_eq "$out" "" "nothing selected: no header alone"

# --- output --------------------------------------------------------------

relays -f hostname,ipv4_addr_in,pubkey ch-zrh
check_eq "$out" "ch-zrh-br-001	193.32.127.117	
ch-zrh-wg-001	193.32.127.71	chvEpRH+05o+ESv8QLzNyY3Phirsym0mUvF03Kt7oCo=" \
    "-f: the fields, tab-separated; one a bridge lacks is empty"
relays -f hostname,nosuch
check_rc 2 "-f with an unknown field: exit 2"
check_in "$err" "no such field: nosuch" "-f with an unknown field: named"
check_eq "$out" "" "-f with an unknown field: nothing printed"

relays -i us-lax
check_in "$out" "hostname:           us-lax-wg-601" "-i: keys aligned"
check_in "$out" "status_messages:    xTom servers in LAX will be moved." \
    "-i: a status message"
check_in "$out" "ipv6_addr_in:       2602:fa19::f001" "-i: a value with colons"
relays us-lax
check_in "$out" "10    notice" "a status message: the notice flag"
relays ar-bue
check_eq "$(printf '%s\n' "$out" | sed -n 2p)" \
    "ar-bue-wg-001  Argentina  Buenos Aires  DataPacket  10" \
    "no flags: no trailing blanks"
relays -i au-syd-br-001
check_in "$out" "ipv6_addr_in:           " "-i: null is empty"
check_in "$out" "ssh_fingerprint_sha256: SHA256:" "-i: a bridge's own fields"
relays -i se-got
check_eq "$(printf '%s\n' "$out" | grep -c '^hostname:')" 2 "-i: one block per relay"
check_in "$out" "daita:              false

hostname:           se-got-wg-002" "-i: a blank line between relays"

relays -L
check_eq "$out" "CC  COUNTRY      CODE  CITY             RELAYS
al  Albania      tia   Tirana           1
ar  Argentina    bue   Buenos Aires     1
au  Australia    syd   Sydney           1
ch  Switzerland  zrh   Zurich           2
se  Sweden       got   Gothenburg       2
se  Sweden       mma   Malmö            1
us  USA          lax   Los Angeles, CA  1" "-L: the places, with their counts"
relays -L -t br
check_eq "$(printf '%s\n' "$out" | sed 1d)" "au  Australia    syd   Sydney  1
ch  Switzerland  zrh   Zurich  1" "-L: counts only what is selected"

relays -w se-got-wg-001
check_rc 0 "-w: succeeds"
check_eq "$out" "[Peer]
# se-got-wg-001, Gothenburg, Sweden, 31173
PublicKey = 5JMPeO7gXIbR5CnUa/NPNK4L5GqUnreF0/Bozai4pl4=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 185.213.154.66:51820" "-w: the relay's [Peer] section"
relays -w ch-zrh
check_rc 0 "-w: a prefix matching a bridge and one WireGuard relay"
check_in "$out" "# ch-zrh-wg-001," "-w: the bridge is not considered"
relays -w se-got
check_rc 1 "-w with two relays selected: exit 1"
check_in "$err" "2 relays match; name one, or add -R" "-w with two: said so"
check_eq "$out" "" "-w with two: no section"
relays -w -R -c se
check_rc 0 "-w -R: succeeds"
check_eq "$(printf '%s\n' "$out" | grep -c '^PublicKey = ')" 1 "-w -R: one section"
relays -w au-syd-br-001
check_rc 1 "-w for a bridge: exit 1"
check_in "$err" "no relay matches" "-w for a bridge: nothing to print"

relays -R -c se
check_rc 0 "-R: succeeds"
check_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "-R: a header and one relay"
case $(hosts) in
se-got-wg-001 | se-got-wg-002 | se-mma-wg-001) pass "-R: one of those selected" ;;
*) fail "-R: one of those selected" ;;
esac
draws=
n=0
while [ "$n" -lt 12 ]; do
    relays -R -f hostname
    draws="$draws $out"
    n=$((n + 1))
done
# shellcheck disable=SC2086  # the draws are words
check_eq "$(printf '%s\n' $draws | grep -c '^[a-z][a-z]-[a-z]*-[a-z]*-[0-9]*$')" 12 \
    "-R: twelve draws, each one relay"
# shellcheck disable=SC2086
if [ "$(printf '%s\n' $draws | sort -u | wc -l)" -gt 1 ]; then
    pass "-R: twelve draws, not the same relay every time"
else
    fail "-R: twelve draws, not the same relay every time"
fi

# --- the parser ----------------------------------------------------------

# A layout of its own: indented, a line per key, an escaped quote and
# backslash, a nested object, and a relay that is not active.
cached '[
  {
    "hostname" : "zz-tst-wg-001",
    "city_name": "Saint \"Q\" \\ Town",
    "active"   : false,
    "extra"    : { "a": 1, "b": [true, null] },
    "status_messages": [ ]
  },
  {
    "hostname": "zz-tst-wg-002", "active": true, "status_messages": [
      {"message": "one, two", "timestamp": "t1"},
      {"message": "three", "timestamp": "t2"} ]
  }
]'
relays
check_eq "$(hosts)" "zz-tst-wg-002" "an inactive relay: left out"
relays -a -f hostname,city_name
check_eq "$out" 'zz-tst-wg-001	Saint "Q" \ Town
zz-tst-wg-002	' "-a: the inactive one too; escapes undone, layout ignored"
relays -a zz-tst-wg-001
check_in "$out" "inactive" "-a: the inactive flag"
relays -f status_messages
check_eq "$out" "one, two t1 | three t2" \
    "a list of objects: values joined, objects by a bar"

# --- fetch(1) where there is no curl -----------------------------------

# A PATH of its own: the stand-ins but those named, and the shell and
# the base tools the script and this file call, so no real curl or
# fetch can be reached whichever directory holds it.  The tools are
# exec wrappers rather than links: Linux compatibility on FreeBSD
# resolves a link's absolute target against the FreeBSD root.
without() {
    w_dir=$(printf '%s' "$tmp/without-$*" | tr ' ' -)
    mkdir -p -- "$w_dir"
    for w_f in "$fakes"/*; do
        case " $* " in
        *" ${w_f##*/} "*) ;;
        *) ln -sf "$w_f" "$w_dir/" ;;
        esac
    done
    # shellcheck disable=SC2086  # SH may carry options: SH='bash --posix'
    set -- $SH
    for w_t in "$1" awk cat find mkdir mktemp mv rm sed; do
        w_f=$(PATH=$ORIG_PATH command -v "$w_t") || continue
        printf '#!/bin/sh\nexec "%s" "$@"\n' "$w_f" > "$w_dir/$w_t"
        chmod 755 "$w_dir/$w_t"
    done
    printf '%s\n' "$w_dir"
}

rm -f -- "$cache"
export FETCH_BODY="$list"
PATH=$(without curl)
relays -c al
PATH=$fakes:$ORIG_PATH
check_rc 0 "no curl: succeeds"
check_eq "$(hosts)" "al-tia-wg-001" "no curl: fetch downloads the list"
check_eq "$(sed 5d "$FETCH_ARGV")" "-q
-T
30
-o
https://api.mullvad.net/www/relays/all/" "no curl: fetch is asked for the list"
check_in "$(sed -n 5p "$FETCH_ARGV")" "$cache." \
    "no curl: into a file beside the cache"
unset FETCH_BODY

rm -f -- "$cache"
PATH=$(without curl fetch)
relays
PATH=$fakes:$ORIG_PATH
check_rc 1 "no curl, no fetch, no cache: exit 1"
check_in "$err" "neither curl nor fetch is installed" "no curl, no fetch: said so"

# --- refusals ------------------------------------------------------------

cached "$list"
touch -t 202001010000 "$cache"
for args in '-s fast' '-s 2.5' '-f a,,b' '-f hostname;id' '-L -i' '-i -f hostname' \
    '-L -R' '-w -i' '-f hostname -w' 'SE-GOT' 'se/got' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    relays $args
    check_rc 2 "refuses [$args] as a usage error"
    check_eq "$(asked)" "" "refuses [$args]: nothing downloaded"
done
relays ''
check_rc 2 "refuses an empty host"

relays -h
check_rc 0 "-h: exit 0"
check_in "$out" "usage: mullvad-relays" "-h: the usage"

finish
