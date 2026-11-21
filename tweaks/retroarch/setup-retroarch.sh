#!/bin/sh
# RetroArch on begonia: GLES on Mali through libhybris (needs libhybris patch
# 0003), touch menu (glui) and the neo-retropad touch overlay.
set -eu
sudo apt-get install -y --no-install-recommends retroarch retroarch-assets libretro-core-info \
    libretro-nestopia libretro-bsnes-mercury-performance libretro-gambatte libretro-mgba \
    libretro-desmume libretro-beetle-psx libretro-beetle-pce-fast

# Touch overlay from https://github.com/libretro/common-overlays (gamepads/neo-retropad)
OV=~/.config/retroarch/overlays/gamepads
mkdir -p "$OV" ~/Games/ROMs
[ -d "$OV/neo-retropad" ] || { tmp=$(mktemp -d); git clone -q --depth 1 --filter=blob:none --sparse \
    https://github.com/libretro/common-overlays.git "$tmp" && git -C "$tmp" sparse-checkout set gamepads/neo-retropad \
    && cp -r "$tmp/gamepads/neo-retropad" "$tmp/COPYING" "$OV/"; rm -rf "$tmp"; }

# Run once so RetroArch writes its default config, then adjust it
[ -f ~/.config/retroarch/retroarch.cfg ] || timeout 5 retroarch >/dev/null 2>&1 || true
python3 - <<'PY'
import os, re
p = os.path.expanduser("~/.config/retroarch/retroarch.cfg"); s = open(p).read()
want = {
    "video_driver": "gl", "input_driver": "wayland", "input_joypad_driver": "udev",
    "menu_driver": "glui", "video_fullscreen": "true",
    "input_overlay_enable": "true",
    "input_overlay": "~/.config/retroarch/overlays/gamepads/neo-retropad/neo-retropad.cfg",
    "input_overlay_auto_scale": "true", "input_overlay_hide_in_menu": "true",
    "input_overlay_hide_when_gamepad_connected": "true", "input_overlay_auto_rotate": "true",
    "input_overlay_opacity": "0.600000",
    "rgui_browser_directory": "~/Games/ROMs", "content_directory": "~/Games/ROMs",
    "menu_show_core_updater": "false", "pause_nonactive": "true",
}
for k, v in want.items():
    line = f'{k} = "{v}"'
    if re.search(rf"^{k} = .*$", s, re.M): s = re.sub(rf"^{k} = .*$", line, s, flags=re.M)
    else: s += line + "\n"
open(p, "w").write(s)
PY

# Launcher with the Mali TLS fix (same as Firefox)
mkdir -p ~/.local/share/applications
sed -e 's#^Exec=retroarch#Exec=env HYBRIS_PATCH_TLS=libGLES_mali.so retroarch#' \
    /usr/share/applications/com.libretro.RetroArch.desktop > ~/.local/share/applications/com.libretro.RetroArch.desktop
