#!/bin/sh
# Build the Genesis Plus GX libretro core (Sega Mega Drive / Genesis,
# Master System, Game Gear, Sega CD) for the phone. Debian doesn't package
# it (non-commercial licence), so it is built from the libretro sources in
# the same arm64 image the Droidian packages are built in.
#
#   ./build-genesis-core.sh            -> out/genesis_plus_gx_libretro.so
#   scp out/genesis_plus_gx_libretro.so begonia:/tmp/ && ssh begonia \
#     sudo install -m644 /tmp/genesis_plus_gx_libretro.so /usr/lib/aarch64-linux-gnu/libretro/
#
# RetroArch already ships genesis_plus_gx_libretro.info in /usr/share/libretro/info.
set -eu

REV=${REV:-4fd32efe1fec3537d11f7aaa24cb961c6ff57fdd}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/out"
IMAGE=quay.io/droidian/build-essential:next-arm64

mkdir -p "$OUT"
docker run --rm --platform linux/arm64 -v "$OUT":/out "$IMAGE" sh -euc "
  git clone -q https://github.com/libretro/Genesis-Plus-GX.git /src
  cd /src && git checkout -q $REV
  make -f Makefile.libretro platform=unix -j\$(nproc) >/dev/null
  strip genesis_plus_gx_libretro.so
  cp genesis_plus_gx_libretro.so /out/
"
ls -l "$OUT/genesis_plus_gx_libretro.so"
