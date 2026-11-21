#!/bin/sh
# begonia (MT6785) Bluetooth through bluebinder: the controller's Supported
# Commands do not advertise LE Set Scan Enable / LE Create Connection, so the
# 4.14 kernel leaves LE Advertising Report, LE Connection Complete and LE Read
# Remote Features Complete (and more) out
# of the LE event mask. Scanning runs but nothing is ever reported, so BLE
# devices (Xbox Series controllers, watches, ...) can't be found.
# Re-apply the LE event mask every time hci0 is powered on.
#
# It also turns on LE privacy, so that the kernel distributes our IRK and
# identity address during pairing (IdKey). Xbox Series controllers otherwise
# do not keep the bond: every reconnect fails with "PIN or Key Missing".
# bluetoothd does not apply Privacy=device from main.conf on this port, so
# set it with btmgmt (it needs the adapter powered off). The IRK must stay the
# same across reboots, otherwise bonded devices can't resolve our address:
# it is generated once and kept in /etc/bluetooth/begonia-irk.
DEV=${DEV:-hci0}
MASK="ff 0d 08 00 00 00 00 00"   # kernel 0x80dd0 | conn complete, adv report, conn update, read remote features, conn param req

IRK_FILE=/etc/bluetooth/begonia-irk
[ -s "$IRK_FILE" ] || { umask 077; od -An -tx1 -N16 /dev/urandom | tr -d " \n" > "$IRK_FILE"; }
IRK=$(cat "$IRK_FILE")

ensure_privacy() {
    if ! btmgmt --index "${DEV#hci}" info 2>/dev/null | grep -q "current settings:.* privacy"; then
        btmgmt --index "${DEV#hci}" power off >/dev/null 2>&1
        btmgmt --index "${DEV#hci}" privacy on "$IRK" >/dev/null 2>&1 && logger -t bt-le-event-mask "LE privacy enabled on $DEV"
        btmgmt --index "${DEV#hci}" power on >/dev/null 2>&1
    fi
}

apply() {
    if hciconfig "$DEV" 2>/dev/null | grep -q "UP RUNNING"; then
        hcitool -i "$DEV" cmd 0x08 0x0001 $MASK >/dev/null 2>&1 && logger -t bt-le-event-mask "LE event mask applied on $DEV"
    fi
}

ensure_privacy
apply
dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/bluez/$DEV'" 2>/dev/null |
while read -r line; do
    case "$line" in
        *'string "Powered"'*) read -r v; case "$v" in *"boolean true"*) sleep 0.3; apply ;; esac ;;
    esac
done
