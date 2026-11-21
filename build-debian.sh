#!/bin/sh
# Rebuild a plain Debian package with our patches (for packages that Droidian
# takes unchanged from Debian, e.g. gnome-usage).
#
#   ./build-debian.sh gnome-usage   -> out/gnome-usage/*.deb
#
# The Debian source (.dsc, pinned to the version the phone runs) is downloaded from snapshot.debian.org, patches/<pkg>/*.patch
# are added as quilt patches, a local version "+begonia2" is added (sorts after
# Debian's binNMU "+b1"), and the package is built in the Droidian build image.
set -eu

PKG=${1:?usage: $0 <gnome-usage>}
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=quay.io/droidian/build-essential:next-arm64

case "$PKG" in
    gnome-usage) DSC=https://snapshot.debian.org/archive/debian/20251118T024734Z/pool/main/g/gnome-usage/gnome-usage_48.0-1.dsc ;;
    *) echo "unknown package $PKG" >&2; exit 1 ;;
esac

OUT="$HERE/out/$PKG"
rm -rf "$OUT"; mkdir -p "$OUT"

docker run --rm \
    -v "$HERE/patches/$PKG":/patches:ro \
    -v "$OUT":/out \
    -e DSC="$DSC" \
    "$IMAGE" /bin/sh -c '
set -e
exec >/out/build.log 2>&1
apt-get update
apt-get install -y --no-install-recommends devscripts equivs quilt ca-certificates
mkdir /build && cd /build
dget -u -d "$DSC"
dpkg-source -x *.dsc src
cd src
mkdir -p debian/patches
for p in /patches/*.patch; do
    cp "$p" debian/patches/
    echo "$(basename "$p")" >> debian/patches/series
done
DEBEMAIL=begonia@localhost DEBFULLNAME=begonia dch -v "$(dpkg-parsechangelog -S Version)+begonia2" "Apply begonia-droidian patches."
mk-build-deps -i -r -t "apt-get -y --no-install-recommends" debian/control
dpkg-buildpackage -b -uc -us
cp ../*.deb /out/
'
ls "$OUT"/*.deb
