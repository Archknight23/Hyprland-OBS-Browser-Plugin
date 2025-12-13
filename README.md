# Hyprland Browser Wrapper (experimental)

An OBS plugin that creates a floating Qt WebEngine browser dock aimed at making custom browser docks usable on Hyprland/Wayland.

### Created for the AUR-Native package of OBS Studio in the context of Hyprland, but could work with Wayland in general. ###

## Authorship
Human-concepted, human-tested, Codex-generated. Built fresh for this experiment—no external plugin code copied.

``` The translation of the above header is that essentially, Codex-CLi was used to work through the logic, out of a need to get custom browser docks to 'work' within the Hyprland (Wayland) compoositor. Thus, the use of AI was solely due to the complexity of the project and the author not having a deep enough understtanding of the C++ language to work on it alone. All testing perfromed by Humans, for Humans.  Auditing and contributions from other Humans who would like to improve and work on this who may have a deeper understanding of this technology are more than welcome. "YEAH, Darling and me vibe coded this with Codex because we wanted to makee it work. It kinda still doesn't completely, so if you wanna help, feel free to fork it. <3" Yeah, we're at the end of the day, a small, underfunded organization, so we supplement our small tech skill with AI agents and independent learning. "Basically, we don't like to vibe code, but did this time for necessity. <3" Basically. We would have used external implemetnations made by humans if it existed.   ```


## Requirements
- OBS built with Qt6 and libobs development files (with a `pkg-config` file for `libobs`).
- Qt6 Core/Gui/Widgets and Qt6 WebEngineWidgets development packages.
- `pkg-config` available in `PATH` for the build configuration.
- Wayland session (tested on Hyprland).

## Build
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

## Install
Pick an install prefix that matches your OBS install (for a user-local install, `~/.local` is usually fine):
```bash
cmake --install build --prefix ~/.local
```
The library installs to `<prefix>/lib/obs-plugins/libhyprland-browser-wrapper.so`. Adjust `OBS_PLUGIN_DESTINATION` if your OBS uses a different plugin path.

## Use
Launch OBS with the plugin in path (example):  
`OBS_PLUGINS_PATH=$HOME/.local/lib/obs-plugins:$OBS_PLUGINS_PATH OBS_PLUGINS_DATA_PATH=$HOME/.local/share/obs/obs-plugins:$OBS_PLUGINS_DATA_PATH obs`

Then open one of two Tools actions:
- **Hypr Browser (Wayland-safe window)**: opens a floating Qt WebEngine window; safest on Wayland/Hyprland.
- **Hypr Browser (Dock; auto Wayland workaround)**: on X11, this is a normal `QDockWidget`; on Wayland/Hyprland it automatically falls back to the texture-based workaround so OBS does not crash when the dock is attached.
- **Hypr Browser (Force texture dock)**: always uses the texture grab workaround.

Usage tips:
- Type a URL and press Enter; `https://` is auto-added when missing.
- Multiple windows/docks are allowed.
- Default page loads `https://obsproject.com` to avoid a blank view.

## Why OBS crashes when you dock the browser on Hyprland

Qt WebEngine widgets cannot be reparented between windows on Wayland. When OBS docks/undocks, it reparents the embedded `QWebEngineView`. On Hyprland that reparent attempt often destroys the surface, which crashes the OBS process. The plugin now detects Wayland sessions (including Hyprland) and swaps the dock to a texture-grab surrogate instead of the live WebEngine widget. Interaction is proxied through the texture view to keep native docking viable without tripping the compositor.

### Alternative: symlink into the user plugin tree
If you prefer not to set env vars, place a symlink where OBS already scans:
```bash
mkdir -p ~/.config/obs-studio/plugins/hyprland-browser-wrapper/bin/64bit
ln -sf ~/.local/lib/obs-plugins/libhyprland-browser-wrapper.so \
  ~/.config/obs-studio/plugins/hyprland-browser-wrapper/bin/64bit/
```
Then launch OBS normally.

## Uninstall
Remove the installed library from your OBS plugins directory (e.g., `rm ~/.local/lib/obs-plugins/libhyprland-browser-wrapper.so`), then restart OBS.
