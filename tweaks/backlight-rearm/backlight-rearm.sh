#!/bin/sh
# begonia backlight re-arm.
# On screen unblank Phosh writes the brightness to the lm36273 backlight chip
# before the panel/bias power is up, the i2c write fails and the screen stays
# dark. Watch Phosh's PowerSaveMode and re-apply the brightness once the panel
# is powered.
BL=/sys/class/leds/lcd-backlight/brightness

rearm() {
    sleep 0.4
    # Only act when the unblank brightness write actually failed, otherwise the
    # 0 -> level toggle below makes the screen blink for nothing.
    [ "$1" = force ] || journalctl -k --since "-3 s" --no-pager -q \
        --grep "lm36273 write data fail" >/dev/null 2>&1 || return
    v=$(cat "$BL" 2>/dev/null) || return
    [ -n "$v" ] && [ "$v" -gt 1 ] || return
    # Force the lm36273 driver through its close->enable path: the failed write
    # at unblank already updated the driver's cached level, so writing a
    # non-zero level only touches the brightness registers and never re-sends
    # BL_ENABLE. Writing 0 first makes the next write re-enable the backlight.
    echo 0 > "$BL"
    echo "$v" > "$BL"
    logger -t backlight-rearm "re-applied brightness $v"
}

# Phoc (re)start sets the initial brightness with the same race -> re-arm once
(sleep 3; rearm force) &

gdbus monitor --session --dest org.gnome.Mutter.DisplayConfig \
    --object-path /org/gnome/Mutter/DisplayConfig |
while read -r line; do
    case "$line" in
        *PowerSaveMode*"<0>"*) rearm & ;;
        # shell (phoc/phosh) restarted -> it re-sets the brightness with the same race
        *"is owned by"*) (sleep 3; rearm force) & ;;
    esac
done
