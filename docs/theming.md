# Theming

Settings › General › Theming lets macOS follow the colour of the wallpaper on the main display.
A master switch turns it on, and a checkbox per target says what follows. Everything is off by
default.

The code is the local package `Packages/OWETheming` (Foundation, Core Graphics and ImageIO only;
`swift test --package-path Packages/OWETheming`) and the app's side in `OpenWallpaperEngine/Theming/`
(`ThemingController`, `DesktopPictureTheming`) with the section in `Settings/ThemingSection.swift`.

## The colour

- **Scheme colour.** A Wallpaper Engine project can set `general.properties.schemecolor`, an
  "r g b" string of 0…1 floats (for example `"0.69 0.27 0.33"`). It is a user property, so the user
  can change it in the Details panel and presets can change it. The colour used is, in order: the
  running instance's value (live edits and presets), the value the user saved for that display's
  properties, then project.json's (`SchemeColorSource`).
- **Main colour.** With "Use the wallpaper's main color when it has no scheme color", a wallpaper
  without one uses the most common colour of its picture: k-means (k = 5, farthest-point seeds,
  8 rounds) in OKLab over a 32×32 copy, off the main thread (`DominantColor`). The picture is the
  scene's loading snapshot, else the desktop picture OWE made of a video or web wallpaper, else
  the Workshop preview. Without this option, such a wallpaper leaves everything as it is.
- **When.** The colour is worked out again when the main display's wallpaper changes, when its
  `schemecolor` changes (live or saved), when the screens change and when a setting changes,
  0.4 s after the last of a burst. The global preferences follow the main display's wallpaper.

## What each checkbox changes

All preferences are the current user's global domain (`NSGlobalDomain`). The keys were found by
reading this Mac's preferences (`defaults read -g`) and the strings of System Settings' Appearance
pane and of SkyLight on macOS 27; nothing was written while finding them.

| Checkbox | What it changes | Values |
|---|---|---|
| Menu Bar | The desktop picture OWE sets: its menu bar strip is filled with the colour. No preference. | — |
| Accent Color | `AppleAccentColor` (Appearance › Color) | integer: −1 Graphite, 0 Red, 1 Orange, 2 Yellow, 3 Green, 4 Blue, 5 Purple, 6 Pink; absent is Multicolor |
| | `AppleHighlightColor` (Appearance › Text highlight color) | `"r g b Other"`, a custom colour |
| Tinted Icon Color | `AppleIconAppearanceTheme` (Appearance › Icon & widget style) | `Tinted` + the current variant (`Automatic`, `Light`, `Dark`); the other styles are `Regular…` and `Clear…` |
| | `AppleIconAppearanceTintColor` | `Other` (the palette names Red … Graphite are the others; absent follows the accent colour) |
| | `AppleIconAppearanceCustomTintColor` | `"r g b a"` |
| Folder Color | `AppleIconAppearanceTintColor` and `AppleIconAppearanceCustomTintColor` only | as above |

### Menu Bar

macOS has no API for the menu bar's colour. The bar is translucent over the desktop picture, so
the picture's top strip shows through it. When this is on, each desktop picture OWE sets gets its
top strip filled with the colour: the menu bar's height on that display (the frame's top minus the
visible frame's top, or the safe area's top inset when taller), mapped into the picture as macOS's
default "Fill Screen" shows it (`MenuBarStrip`). It is drawn by one hook in the two places OWE
writes a desktop picture (`DesktopSnapshotCache.setDesktopPicture`, `LockScreenPicture.apply`),
just after the file is written and before it is shown (`DesktopPictureTheming`).

Limits:

- Only the pictures OWE sets get the strip: a scene's lock-screen picture ("Show Wallpaper on
  Lock Screen") and a video or web wallpaper's picture ("Adjust Menu Bar Color"). With neither,
  the desktop picture stays the user's own and the menu bar is unchanged.
- The bar is translucent, so the colour shows as a tint, not as the exact colour.
- A display whose menu bar hides itself has no strip.
- A web wallpaper's picture gets the strip with its next snapshot (when its page loads); scenes and
  videos get it at once.

### Accent Color

macOS 27 still has a fixed accent palette: System Settings shows eight swatches and stores an
integer, and there is no custom accent. The colour maps to the nearest swatch by OKLab distance
(`AccentPalette`). The text highlight colour does take a custom colour (`Other`), so it is set to
the colour at 30% over white, which is how light macOS's own highlights are. After writing, OWE
posts the distributed notification `AppleColorPreferencesChangedNotification`, which System
Settings posts too, so running apps redraw.

### Tinted Icon Color

The icon and widget style of macOS 26 and later is `AppleIconAppearanceTheme`; its colour is
`AppleIconAppearanceTintColor`, with `Other` for a custom colour in
`AppleIconAppearanceCustomTintColor`. SkyLight reads them and the Dock and Finder draw the icons.
System Settings applies a change through a private SkyLight call, and there is no public
notification for it, so after OWE writes the keys the Dock shows the change when it starts again.
OWE never restarts it on its own: when a write happened, the section shows **Apply Now (Restarts
Dock)**, which runs `killall Dock` on the user's click. If an icon still doesn't change, logging out
and in applies it.

### Folder Color

macOS 26 and later colour folders with the "Icon, widget & folder color" setting, the same
`AppleIconAppearanceTintColor` / `AppleIconAppearanceCustomTintColor` the tinted style uses; folders
use it with every icon style, and without it they follow the accent colour. So Folder Color writes
those two keys and leaves the icon style alone. Folder Color and Tinted Icon Color share them: the
keys are restored when both are off.

## Saving and restoring

- **Before the first change** of a key, its value (or its absence) is saved in a journal under the
  app's defaults (`ThemingJournal`, `UserDefaultsJournalStore`), on disk before the write happens.
- **Unchanged values aren't written**, and no notification is posted for them.
- **Turning a checkbox off** restores its keys; **turning the master switch off** restores all of
  them. A key goes back only while it still holds what OWE wrote: if the user changed it in System
  Settings since, their choice stays.
- **Quitting** restores everything when "Restore on Quit" is on (the default). Off, the colours stay,
  and the originals are kept, so turning theming off later still restores them.
- **After a crash**, the journal still says a session was running, so the next launch restores the
  originals first; theming then applies again if it is on.
- **Isolated copies** (tests, development copies, `OWE_ISOLATED_STATE`) read the preferences but
  never write them (`ReadOnlyAppearanceWriter`), and don't change the desktop picture.

All writes go through the `SystemAppearanceWriter` protocol: `GlobalPreferencesWriter` uses
CFPreferences and the distributed notification centre, and the package's tests use a fake.
