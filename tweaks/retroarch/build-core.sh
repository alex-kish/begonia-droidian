#!/bin/sh
# Build libretro cores Debian doesn't package, in the same arm64 image the
# Droidian packages are built in.
#
#   genesis  Genesis Plus GX: Mega Drive/Genesis, Master System, Game Gear,
#            Sega CD (non-commercial licence, so not in Debian)
#   pcsx     PCSX ReARMed: PlayStation with an ARM64 dynarec and a built-in
#            HLE BIOS, so games run without a Sony BIOS dump
#
#   ./build-core.sh genesis|pcsx   -> out/<core>_libretro.so
#   scp out/<core>_libretro.so begonia:/tmp/ && ssh begonia \
#     sudo install -m644 /tmp/<core>_libretro.so /usr/lib/aarch64-linux-gnu/libretro/
#
# RetroArch already ships the matching .info files in /usr/share/libretro/info.
set -eu

case "${1:?usage: $0 genesis|pcsx}" in
    genesis) REPO=https://github.com/libretro/Genesis-Plus-GX.git
             REV=4fd32efe1fec3537d11f7aaa24cb961c6ff57fdd
             SO=genesis_plus_gx_libretro.so ;;
    pcsx)    REPO=https://github.com/libretro/pcsx_rearmed.git
             REV=7b0e8f8fadfbce3d170d195b9d9eecaabfa08c8e
             SO=pcsx_rearmed_libretro.so ;;
    *) echo "unknown core $1" >&2; exit 1 ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/out"
IMAGE=quay.io/droidian/build-essential:next-arm64

mkdir -p "$OUT"
docker run --rm --platform linux/arm64 -v "$OUT":/out "$IMAGE" sh -euc "
  git clone -q $REPO /src
  cd /src && git checkout -q $REV && git submodule -q update --init --recursive
  make -f Makefile.libretro platform=unix -j\$(nproc) >/dev/null
  strip $SO
  cp $SO /out/
"
ls -l "$OUT/$SO"
