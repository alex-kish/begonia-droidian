#!/bin/sh
# begonia (MT6785) Bluetooth through bluebinder: the controller's Supported
# Commands do not advertise LE Set Scan Enable / LE Create Connection, so the
# 4.14 kernel leaves LE Advertising Report, LE Connection Complete and LE Read
# Remote Features Complete (and more) out
# of the LE event mask. Scanning runs but nothing is ever reported, so BLE
# devices (Xbox Series controllers, watches, ...) can't be found.
# Re-apply the LE event mask every time hci0 is powered on.
DEV=${DEV:-hci0}
MASK="ff 0d 08 00 00 00 00 00"   # kernel 0x80dd0 | conn complete, adv report, conn update, read remote features, conn param req

apply() {
    if hciconfig "$DEV" 2>/dev/null | grep -q "UP RUNNING"; then
        hcitool -i "$DEV" cmd 0x08 0x0001 $MASK >/dev/null 2>&1 && logger -t bt-le-event-mask "LE event mask applied on $DEV"
    fi
}

apply
dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/bluez/$DEV'" 2>/dev/null |
while read -r line; do
    case "$line" in
        *'string "Powered"'*) read -r v; case "$v" in *"boolean true"*) sleep 0.3; apply ;; esac ;;
    esac
done
