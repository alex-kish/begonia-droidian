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

## Tweaks (`tweaks/`)

- `backlight-rearm`: user service. On unblank, phosh writes the brightness to the `lm36273` backlight chip before panel bias power is up. The i2c write fails, the driver caches the level and the screen stays black. The service watches `PowerSaveMode` and, only when the write failed, re-enables the backlight (0 → level).
- `brightness-restore`: the port's `brightness.service` writes 2047 (max) on every boot. A drop-in replaces that with the level saved at shutdown (`/var/lib/begonia/brightness`), plus a timer saves it every 5 minutes in case the phone goes down with the screen off. Install: `begonia-brightness` → `/usr/local/sbin/`, `restore.conf` → `/etc/systemd/system/brightness.service.d/`, `begonia-brightness-save.{service,timer}` → `/etc/systemd/system/`.
- `pulse/default.pa` (`~/.config/pulse/default.pa`): the Droidian PulseAudio config restores only per-stream volumes, so the speaker volume was 100% after every boot. It loads `module-device-restore` before the droid card and then includes the system config.
- `wallpaper/`: PNG wallpapers at panel resolution (decoding is cheaper than the default SVG on rotation).
- `printing/`: the phone as an AirPrint server for a USB-only Canon PIXMA MG2550S plugged in through USB-C OTG (CUPS + gutenprint, shared on the LAN, advertised via avahi). The port's USB is in host mode with an OTG adapter, but the phone does not charge while the printer is connected.
- `firefox/user.js`: GPU rendering, HW video decode off (MTK V4L2 is not usable from Firefox).

## Other findings

- `mobile-power-saver` writes `0` to `devfreq1/max_freq` on screen off, which causes a kernel NULL dereference and reboot. Disabled.
- Updating via GNOME Software can remove image-only Droidian packages (network-manager `…wwan.fix`, `libglibutil`). Hold them, and upgrade only with `apt` after reviewing removals.
- Hot-restarting `phosh.service` is unreliable on this port (BindsTo `android-service@hwcomposer`). Reboot instead.
- Hardware VP9 decode (`droidvdec`) tops out around 4K30 / 1440p50. That is the SoC limit, not a throttling issue.
