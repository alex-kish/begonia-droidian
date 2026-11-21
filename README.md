# begonia-droidian

Fixes and tweaks for **Droidian on the Xiaomi Redmi Note 8 Pro (begonia, MT6785 / Helio G90T, Mali-G76)**.

Packages are built exactly like Droidian CI does (`quay.io/droidian/build-essential:next-arm64` + `releng-build-package`), with our patches applied on top of the Droidian branches the phone runs. The build runs natively on Apple Silicon or any arm64 host with Docker.

```sh
./build.sh libhybris   # -> out/libhybris/*.deb
./build.sh phoc        # -> out/phoc/*.deb
```

## Patches

### libhybris (`feature/next/lindroid-drm`)

`libGLES_mali.so` keeps its current GL context in bionic TLS slot 3 (`[tpidr_el0 + 24]`). On glibc threads that slot overlaps application static TLS, so the Mali driver reads a garbage context and crashes. For example, Firefox crashes on its `CanvasRenderer` thread in `glGetString`.

libhybris already has a TLS patcher (`HYBRIS_PATCH_TLS`) that rewrites these accesses to a libhybris-owned area. It only patched the first `ldr` after each `mrs xN, tpidr_el0` and only within 4 instructions. The Mali driver keeps the thread pointer in a callee-saved register (e.g. `x29`) and reads the slot again much later. Our patches:

- `0001` follows the register until it is redefined (or `ret`/`ldp` into it) and patches every slot 3..4 access;
- `0002` does not treat branch immediates (`bl`, `b.cond`, ...) as register writes.
- `0003` fixes `eglGetConfigAttrib` on Wayland. The `lindroid-drm` branch turned it into a hand-written wrapper (commit `38de2ac`) that passes the hybris display handle to the Android EGL without mapping it, so every call failed with `EGL_BAD_DISPLAY`. Any client that checks config attributes (RetroArch, SDL) found no usable config. With the fix, RetroArch runs on Mali-G76 / OpenGL ES 3.2.

To enable it per application:

```sh
HYBRIS_PATCH_TLS=libGLES_mali.so firefox
```

With this, Firefox runs WebRender on the GPU without crashing (A/B tested: unpatched crashes in ~20 s, patched stays up).

Enabling it globally (`/etc/environment`) currently breaks `pulseaudio` audio HAL loading. This is still under investigation.

### phoc (`group/next/phosh-0.47`)

On rotation phoc raised an opaque black "shield" until all layer surfaces re-configured, which takes about 0.4–0.6 s on this phone (Phosh redraws with GTK3 on the CPU).

- `0001` keeps the last presented frame instead of the black shield. `PHOC_MODESET_SHIELD=1` restores the old behaviour.
- `0002` animates the rotation. Before the new transform is applied, the scene is rendered once more and copied into a texture **on the GPU** (`glCopyTexSubImage2D`, ~2 ms). `wlr_renderer_read_pixels` takes 0.6–0.8 s here, and locking swapchain buffers breaks the android renderer's per-buffer EGL surfaces. When the layout transaction is done, the new layout is copied the same way. Both frames then rotate into place as one object while cross-fading (350 ms). `PHOC_ROTATION_ANIM=0` turns it off.

### gnome-usage (Debian 48.0-1)

Built with `./build-debian.sh gnome-usage` (Debian source from snapshot.debian.org + our quilt patches, version `+begonia1`).

The Storage view summed every mount point. On Droidian the 52 GB root filesystem is mounted 49 times (`/`, `/android/data`, `/android/vendor`, the overlays and apex mounts of the Android LXC container), so Usage showed ~280 GB. `0001` counts each filesystem once: all of its mount points report the same statfs numbers.

The Network view listed ~20 empty MediaTek modem interfaces (`ccmni0`…`ccmni20`) and opened an empty one by default. `0002` hides interfaces with zero traffic in the period. Wi‑Fi was missing because `vnstat` had created its database before `wlan0` existed (Wi‑Fi comes up with the Android container) and `AlwaysAddNewInterfaces` is off. Clean the database once on the phone:

```sh
for i in $(seq 2 20) -lan; do sudo vnstat --remove -i ccmni$i --force; done
for i in dummy0 ifb0 ifb1 tunl0 ip_vti0 ip6_vti0 ip6tnl0; do sudo vnstat --remove -i $i --force; done
sudo vnstat --add -i wlan0 && sudo systemctl restart vnstat
```

The CPU and memory numbers were checked and are correct: memory = `MemTotal − MemAvailable`, the same as `free`, and CPU = user+nice+sys over total, including iowait and irq.

## Tweaks (`tweaks/`)

- `phosh/60-chvt-before-start.conf` (`/etc/systemd/system/phosh.service.d/`): Droidian runs `chvt 7` as `ExecStartPost`, in parallel with the main process taking over `/dev/tty7` (`TTYVHangup`). When the race is lost, `capsh` gets `SIGHUP` within milliseconds. phosh and hwcomposer (`BindsTo` each other) then restart in a loop with a black screen; we saw 70+ restarts after one boot. The drop-in switches the VT in `ExecStartPre` instead.
- `bt-le-scan/` covers BLE on the MT6785 through bluebinder. The controller's Supported Commands don't list the LE scan/connect commands, so the 4.14 kernel leaves LE Advertising Report, LE Connection Complete and LE Read Remote Features Complete out of the LE event mask. Scans find nothing, and LE connections hang before any ATT traffic. `bt-le-event-mask.service` re-applies the mask (`hcitool cmd 0x08 0x0001 ff 0d 08 …`) every time hci0 powers on, and `mobile-power-saver` powers Bluetooth off whenever the screen goes off. `50-uhid.conf` adds bluetoothd to `android_uhid` so HID-over-GATT can create input devices. Status: BLE scanning, pairing and encryption work. An Xbox Series controller pairs, but it doesn't keep the bond across power cycles ("PIN or Key Missing", then "unlikely error" on HID reads). HOG setup also sometimes fails (`uhid_create … getpeername`), so the controller isn't usable over Bluetooth yet.
- `retroarch/setup-retroarch.sh`: RetroArch from Debian with packaged cores (NES, SNES, GB/GBC, GBA, DS, PSX, PC Engine). It uses the `gl` driver (needs libhybris `0003`), the touch menu (`glui`) and the libretro `neo-retropad` touch overlay. ROMs go in `~/Games/ROMs`.

- `backlight-rearm`: user service. On unblank, phosh writes the brightness to the `lm36273` backlight chip before panel bias power is up. The i2c write fails, the driver caches the level and the screen stays black. The service watches `PowerSaveMode` and, only when the write failed, re-enables the backlight (0 → level).
- `brightness-restore`: the port's `brightness.service` writes 2047 (max) on every boot. A drop-in replaces that with the level saved at shutdown (`/var/lib/begonia/brightness`), plus a timer saves it every 5 minutes in case the phone goes down with the screen off. Install: `begonia-brightness` → `/usr/local/sbin/`, `restore.conf` → `/etc/systemd/system/brightness.service.d/`, `begonia-brightness-save.{service,timer}` → `/etc/systemd/system/`.
- `pulse/default.pa` (`~/.config/pulse/default.pa`): the Droidian PulseAudio config restores only per-stream volumes, so the speaker volume was 100% after every boot. It loads `module-device-restore` before the droid card and then includes the system config.
- `wallpaper/`: PNG wallpapers at panel resolution (decoding is cheaper than the default SVG on rotation).
- `printing/`: the phone as an AirPrint server for a USB-only Canon PIXMA MG2550S plugged in through USB-C OTG (CUPS + gutenprint, shared on the LAN, advertised via avahi). The port's USB is in host mode with an OTG adapter, but the phone does not charge while the printer is connected.
- `firefox/user.js`: GPU rendering, HW video decode off (MTK V4L2 is not usable from Firefox).

## Other findings

- Droidian disables systemd suspend on purpose (`AllowSuspend=no`). Power saving with the screen off comes from `mobile-power-saver`: it caps CPU frequencies, moves work to the little cores, freezes apps and services and puts Bluetooth into power save. Its write to the only devfreq device (`devfreq1`, `10012000.dvfsrc`, the DRAM/VCORE DVFS controller) oopses the kernel and reboots the phone, so `tweaks/power-saver/90_begonia.gschema.override` adds it to the `devfreq-blacklist` the daemon provides for this. Install it to `/usr/share/glib-2.0/schemas/` and run `glib-compile-schemas` there.
- Updating via GNOME Software can remove image-only Droidian packages (network-manager `…wwan.fix`, `libglibutil`). Hold them, and upgrade only with `apt` after reviewing removals.
- Hot-restarting `phosh.service` is unreliable on this port (BindsTo `android-service@hwcomposer`). Reboot instead.
- Hardware VP9 decode (`droidvdec`) tops out around 4K30 / 1440p50. That is the SoC limit, not a throttling issue.
