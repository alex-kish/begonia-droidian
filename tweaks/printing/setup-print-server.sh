#!/bin/sh
# Turn the phone into a network print server for a USB-only printer
# (Canon PIXMA MG2550S) connected through a USB-C OTG adapter.
# Run on the phone. Clients (macOS/iOS) find it via AirPrint (avahi/dnssd).
set -eu

sudo apt-get install -y --no-install-recommends printer-driver-gutenprint usbutils
sudo cupsctl --share-printers          # LAN only (@LOCAL), no remote admin

# Find the printer: lsusb shows "04a9:176d Canon, Inc. PIXMA MG2500 Series".
# The URI is built by hand instead of `lpinfo -v`: probing all USB backends
# coincided with a spontaneous reboot on this port.
SERIAL=$(sudo lsusb -v -d 04a9:176d 2>/dev/null | awk '/iSerial/ {print $3}')
sudo lpadmin -p MG2550S -D "Canon PIXMA MG2550S" -L "Redmi Note 8 Pro (USB)" \
    -v "usb://Canon/MG2500%20series?serial=$SERIAL" \
    -m "gutenprint.5.3://bjc-PIXMA-MG2550S/expert" \
    -o printer-is-shared=true -o media-default=iso_a4_210x297mm -E
sudo lpadmin -d MG2550S
lpstat -p MG2550S

# On the Mac (or just pick it in System Settings → Printers, it shows up via AirPrint):
#   lpadmin -p Canon_MG2550S_Redmi -v ipp://RedmiNote8Pro.local:631/printers/MG2550S -m everywhere -E
