// GPU rendering; needs HYBRIS_PATCH_TLS=libGLES_mali.so (set in ~/.local/share/applications/firefox.desktop)
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.software", false);
user_pref("layers.acceleration.disabled", false);
user_pref("layers.acceleration.force-enabled", true);
user_pref("media.hardware-video-decoding.enabled", false);
user_pref("media.ffmpeg.v4l2.enabled", false);
user_pref("media.ffmpeg.vaapi.enabled", false);
