#!/bin/sh
# Build a Droidian package with our patches, exactly like Droidian CI does.
#
#   ./build.sh libhybris        -> out/libhybris/*.deb
#   ./build.sh phoc             -> out/phoc/*.deb
#
# Sources are taken from the Droidian GitHub branch the phone runs,
# patches/<pkg>/*.patch are applied on top as git commits, and the package is
# built in quay.io/droidian/build-essential with releng-build-package (which
# derives the version from git, so our build sorts after the official one).
set -eu

PKG=${1:?usage: $0 <libhybris|phoc>}
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=quay.io/droidian/build-essential:next-arm64

case "$PKG" in
    libhybris) REPO=https://github.com/droidian/libhybris.git; BRANCH=feature/next/lindroid-drm; BASE=91f805b ;;
    phoc)      REPO=https://github.com/droidian/phoc.git;      BRANCH=group/next/phosh-0.47;    BASE=7e682c6 ;;
    *) echo "unknown package $PKG" >&2; exit 1 ;;
esac

SRC="$HERE/build/$PKG"
OUT="$HERE/out/$PKG"

rm -rf "$SRC" "$OUT"
mkdir -p "$OUT"
git clone -q -b "$BRANCH" "$REPO" "$SRC"
git -C "$SRC" checkout -q -B "begonia/$BRANCH" "$BASE"

if ls "$HERE/patches/$PKG"/*.patch >/dev/null 2>&1; then
    git -C "$SRC" -c user.name=begonia -c user.email=begonia@localhost \
        am -q "$HERE/patches/$PKG"/*.patch
fi
git -C "$SRC" log --oneline "$BASE"..HEAD

docker run --rm \
    -v "$SRC":/buildd/sources \
    -v "$OUT":/out \
    -e RELENG_FULL_BUILD=yes \
    -e RELENG_HOST_ARCH=arm64 \
    "$IMAGE" \
    /bin/sh -c 'cd /buildd/sources && releng-build-package >/out/build.log 2>&1; rc=$?; cp /buildd/*.deb /out/ 2>/dev/null; exit $rc'

ls "$OUT"/*.deb
