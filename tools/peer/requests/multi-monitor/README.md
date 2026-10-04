# WE 2.8.42 multi-monitor options (partial)

This PC has 2 monitors, each 1920x1080: the laptop panel, and an ASUS VG27VQ3B to its right.

## Where the options are
- **Location:** the main UI → **Displays** → the "Choose Display" panel. It's the dropdown above the monitor tiles (seen earlier: "Clone single wallpaper").
- **Mode dropdown values** (from `ui/dist/scripts/scripts.js` and `locale/ui_en-us.json`):

| value | label |
|---|---|
| 0 | Wallpaper per display |
| 1 | Stretch single wallpaper |
| 2 | Clone single wallpaper |

- **Screensaver modes:** the screensaver has the same three ("Screensaver per display" / "Stretch single screensaver" / "Clone single screensaver").
- **Other buttons:** "Load profile" and "Save profile".

## Monitor groups
A monitor tile's right-click menu has:
- **Add Stretch Group** (`createGroup=1`) and **Add Clone Group** (`createGroup=2`);
- for clone groups: **Set main clone display** / **Remove main clone display** (`source`), and **Flip clone display**. At least one display must be an unflipped source;
- Mute / Unmute per monitor.

The hint text reads: "Windows may not support cloning from HDR to non-HDR displays."

## config.json
- **Layout and selection:** they live in `<winuser>.general.wallpaperconfig`. This PC currently has (`wallpaperconfig_before.json`):

```json
{"layout": 2, "profile": {"splits": {}},
 "selectedwallpapers": {"Monitor0": {"file": "…/scene.json"}, "Monitor1": {"file": "…/scene.json"}}}
```

- **`layout`:** the dropdown value. 2 = clone here, and `selectedwallpapers` still keeps a file per monitor.
- **Groups:** they're saved in the monitor profile as `groups: { "group_<hash of member locations>": { monitors: [<location>…], layout: 1|2, source?: <location> } }`, written via the UI's profile save.
- **Per-monitor properties:** in `wproperties[<project path>].MonitorN`.

## Not done yet
- Screenshots of each mode, the clone vs individual GPU cost, and the span screenshot.
- They were blocked: a Windows Firewall prompt (for WE's mobile pairing) is open over the screen and must be answered at the PC.
