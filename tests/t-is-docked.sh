#!/bin/sh
# is-docked: each criterion on each platform, the internal panels that
# do not count, and the refusals.
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

# --- FreeBSD: sysctl, ifconfig, xrandr ---------------------------------

# drm-kmod's connector sysctls: the internal panel and one external
# connector on card0, another on card1, and a status-like OID that is not
# a connector's.
drm_sysctls() {
    cat <<EOF
sys.class.drm.card0-eDP-1.status: connected
sys.class.drm.card0-eDP-1.connector_id: 236
sys.class.drm.card0-$1.status: $2
sys.class.drm.card0-$1.connector_id: 245
sys.class.drm.card1-$3.status: $4
sys.class.drm.card0.gt.gt0.throttle_reason_status: 0
EOF
}

export FAKE_UNAME=FreeBSD
docked_freebsd() {
    SYSCTL_DRM=$(drm_sysctls DP-1 connected HDMI-A-1 disconnected)
    export SYSCTL_ACLINE=1 IFCONFIG_LIST="em0 lo0 wlan0 ue0" SYSCTL_DRM
}

docked_freebsd
run is-docked
check_rc 0 "FreeBSD docked: exit 0"
check_eq "$out" "docked=acline,if-usb,screen" "FreeBSD docked: said so"
run is-docked -v
check_in "$err" "usb_nic: yes (ue0)" "FreeBSD -v: the USB interface named"
check_in "$err" "screen: yes (DP-1)" "FreeBSD -v: the external connector named"
run is-docked -q
check_rc 0 "FreeBSD -q: exit 0"
check_eq "$out" "" "FreeBSD -q: prints nothing"

docked_freebsd
export SYSCTL_ACLINE=0
run is-docked
check_rc 1 "FreeBSD on battery: undocked"
check_eq "$out" "undocked" "FreeBSD on battery: said so"
unset SYSCTL_ACLINE
run is-docked
check_rc 1 "FreeBSD with no acline OID: undocked, not an error"

docked_freebsd
export IFCONFIG_LIST="em0 lo0 wlan0 tun0"
run is-docked
check_rc 1 "FreeBSD with no ue interface: undocked"

docked_freebsd
SYSCTL_DRM=$(drm_sysctls DP-1 disconnected HDMI-A-1 disconnected)
run is-docked
check_rc 1 "FreeBSD, only the eDP panel connected: undocked"
SYSCTL_DRM=$(drm_sysctls LVDS-1 connected DSI-1 connected)
run is-docked
check_rc 1 "FreeBSD, LVDS and DSI are internal panels too: undocked"
SYSCTL_DRM=$(drm_sysctls DP-1 disconnected HDMI-A-1 connected)
run is-docked -v
check_rc 0 "FreeBSD, a screen on the second card: docked"
check_in "$err" "screen: yes (HDMI-A-1)" "FreeBSD, the second card's connector named"

docked_freebsd
unset SYSCTL_DRM
export DISPLAY=:0 XRANDR_OUTPUT='Screen 0: minimum 8 x 8
eDP-1 connected primary 1920x1080+0+0
DP-1-1 connected 2560x1440+1920+0
HDMI-1 disconnected'
run is-docked -v
check_rc 0 "FreeBSD without drm-kmod, X running: xrandr decides"
check_in "$err" "screen: yes (DP-1-1)" "FreeBSD via xrandr: the external output named"
export XRANDR_OUTPUT='eDP-1 connected primary 1920x1080+0+0
DP-1 disconnected'
run is-docked
check_rc 1 "FreeBSD via xrandr: eDP alone is undocked"
unset DISPLAY
run is-docked
check_rc 1 "FreeBSD, neither drm-kmod nor X: undocked"
check_in "$err" "cannot check screens" "FreeBSD, neither drm-kmod nor X: said so"
unset XRANDR_OUTPUT

# --- Linux: sysfs ------------------------------------------------------

export FAKE_UNAME=Linux SYSFS="$tmp/sys"

# psu NAME TYPE ONLINE, net NAME DEVICE-PATH [wireless], drm CONNECTOR STATUS
psu() {
    mkdir -p "$SYSFS/class/power_supply/$1"
    printf '%s\n' "$2" > "$SYSFS/class/power_supply/$1/type"
    printf '%s\n' "$3" > "$SYSFS/class/power_supply/$1/online"
}
net() {
    mkdir -p "$SYSFS/devices/$2" "$SYSFS/class/net/$1"
    # relative, as sysfs's own links are
    ln -s "../../../devices/$2" "$SYSFS/class/net/$1/device"
    [ -z "${3-}" ] || mkdir "$SYSFS/class/net/$1/wireless"
}
drm() {
    mkdir -p "$SYSFS/class/drm/$1"
    printf '%s\n' "$2" > "$SYSFS/class/drm/$1/status"
}
usb=pci0000:00/0000:00:14.0/usb2/2-1/2-1:1.0
pci=pci0000:00/0000:00:1f.6
docked_linux() {
    rm -rf -- "$SYSFS"
    psu BAT0 Battery 0
    psu AC Mains 1
    net lo virtual
    net eno1 "$pci"
    net enx001122334455 "$usb"
    drm card1-eDP-1 connected
    drm card1-DP-1 connected
    drm card1-HDMI-A-1 disconnected
}

docked_linux
run is-docked -v
check_rc 0 "Linux docked: exit 0"
check_in "$err" "power: yes (AC)" "Linux: the Mains supply named"
check_in "$err" "usb_nic: yes (enx001122334455)" "Linux: the USB interface named"
check_in "$err" "screen: yes (DP-1)" "Linux: the external connector named"

docked_linux
printf '0\n' > "$SYSFS/class/power_supply/AC/online"
psu ucsi-source-psy-USBC000:001 USB 1
run is-docked -v
check_rc 0 "Linux, powered by the dock over USB-C: docked"
check_in "$err" "power: yes (ucsi-source-psy-USBC000:001)" "Linux: the USB supply named"
printf '0\n' > "$SYSFS/class/power_supply/ucsi-source-psy-USBC000:001/online"
run is-docked
check_rc 1 "Linux on battery: undocked"

docked_linux
rm -rf -- "$SYSFS/class/net/enx001122334455"
net wlx001122334455 "$usb.wifi" wireless
run is-docked
check_rc 1 "Linux, a USB Wi-Fi dongle is not the dock: undocked"

docked_linux
printf 'disconnected\n' > "$SYSFS/class/drm/card1-DP-1/status"
drm card1-LVDS-1 connected
drm card1-DSI-1 connected
run is-docked
check_rc 1 "Linux, internal panels only: undocked"

# --- both --------------------------------------------------------------

export FAKE_UNAME=Plan9
run is-docked
check_rc 1 "an unknown platform: exit 1"
check_in "$err" "unsupported platform" "an unknown platform: said so"

export FAKE_UNAME=FreeBSD
for args in 'extra' '-z'; do
    # shellcheck disable=SC2086  # each case is a word list
    run is-docked $args
    check_rc 2 "refuses [$args] as a usage error"
done
run is-docked -h
check_rc 0 "-h: help"

finish
