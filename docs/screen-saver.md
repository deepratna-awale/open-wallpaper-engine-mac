# Screen saver and lock screen

Open Wallpaper Engine installs a screen saver that shows your wallpaper live: while the screen
saver runs, the app draws the wallpaper as it does on the desktop and the screen saver shows its
frames. Nothing is recorded. How it is built: [`architecture.md`](architecture.md), "Lock screen
and screen saver".

## The Screen Saver plugin

Settings › Plugins › **Screen Saver** (on by default) installs the Open Wallpaper Engine screen
saver in `~/Library/Screen Savers`. **Open Screen Saver Settings…** opens the System Settings pane
that holds the screen savers (Screen Saver, or Wallpaper on newer macOS), where you choose it. The
app never changes the system's screen saver setting itself. Turning the plugin off removes the
screen saver.

While the screen saver runs and an Open Wallpaper Engine saver is showing:

- **Scenes** are drawn live as the screen saver's layout plans them (per display, cloned or
  stretched), with the screen saver's own settings: scripts see `engine.isScreensaver()` true,
  clocks and dates show the time, audio-reactive parts follow what the Mac plays, and the sound
  stays off. The pointer stays in the middle (any input ends the screen saver).
- **Web wallpapers and WebM videos** are drawn by the Chromium engine, whichever engine the
  desktop uses: WebKit stops a page the screen saver covers. When the desktop already shows the
  page in Chromium on that display, that page is drawn from; otherwise one of its own, without a
  window. Without the Chromium engine they show their picture, and Settings › Plugins › Screen
  Saver offers to install it.
- **Video wallpapers** (MP4 and MOV in H.264 or HEVC) play their own file.
- Application wallpapers can't be used.

Each frame is shown as it is drawn, at the display's cadence, as on the desktop (60 fps on a
165 Hz display is 55). Until the first frames come, each display shows its lock-screen picture
(with Show Wallpaper on Lock Screen on). The app draws only while the screen saver runs: it stops
when the screen saver stops or the Mac is unlocked, and another screen saver or the System
Settings preview never makes it draw. After the screen saver stops, the lock screen keeps its
last frame.

When the app isn't running, the screen saver asks for it: its broker (the background item below)
launches the app in the background, with no window or Dock icon, and the wallpaper starts loading
at once.

The Details panel says whether the screen saver shows the selected wallpaper (**Screen Saver
Available**), is preparing a video's file (**Rendering Screen Saver**) or not (**Screen Saver Not
Available**, with the reason in its tooltip).

## The Screen Saver tab

Scene Edit / Export's second tab (Wallpaper | Screen Saver | iPhone & iPad Export | Android
Export) makes a scene wallpaper's own version the screen saver:

- It runs a private copy of the wallpaper. Turning layers on or off, adjusting them and changing
  user properties there never touches your desktop, its properties or the Wallpaper Editor's
  edits. These choices are kept for each wallpaper as its screen saver's own, and the screen
  saver draws it with them.
- **Set as Screen Saver** makes this version the screen saver, drawn live on every display,
  turning the plugin on if it is off. Its preview is the screen saver's picture until the
  screen saver has drawn it once. **Stop Using as Screen Saver** goes back to the desktop's
  wallpapers.
- When the app starts, a recording an earlier version set as the screen saver becomes this live
  choice of its wallpaper, and the old recordings are deleted.

A video wallpaper (MP4, M4V or MOV) opens Scene Edit / Export on this tab too, with the
video playing: its screen saver is the video itself, played as it is. **Set as Screen Saver**
makes it the screen saver (turning the plugin on if it is off), and **Stop Using as Screen
Saver** goes back to the desktop's wallpapers.

## Screen saver layout

With several displays, Display Settings' **Screen saver layout** is **Same as wallpaper** (the
displays' layout and groups) by default, or each display's own wallpaper, one stretched across
the displays, or one cloned. See [`display-layouts.md`](display-layouts.md).

## How the frames reach the screen saver

Two savers show the frames, and both stay:

- **Open Wallpaper Engine** in `~/Library/Screen Savers` (a classic `.saver`, macOS 14 and
  later). It runs inside Apple's `legacyScreenSaver` host, whose sandbox lets it reach the app only
  through shared surfaces the app marks global and through Darwin notifications.
- **Open Wallpaper Engine** as a screen saver extension inside the app (macOS 14 and later,
  release builds). It has its own sandbox, shares an App Group with the app, and gets the frames
  over XPC through the app's background item (the broker), so nothing is shared globally.

Why both: the classic saver works with any signature (development builds too), needs nothing
registered, and runs on every supported macOS; but global surfaces are deprecated and readable by
any process. The extension fixes that and avoids the classic host's lifecycle bugs, but it uses a
private extension point (`com.apple.screensaver`) that a macOS update may change, needs the
Developer ID signature for its App Group, and is only in release builds. They share the drawing
code in the app and in the saver, so keeping both costs little, and if one stops working the
other still does. Either can be picked in System Settings.

### The background item

Release builds register the broker as a background item while the Screen Saver plugin is on
(System Settings › General › Login Items › Allow in the Background lists it as Open Wallpaper
Engine). It is a small process that runs from login, so it knows when a screen saver really runs:
it launches the app only then, when a saver shows while the app isn't running, never when you
select the screen saver or click Preview in System Settings. A copy it launched quits two minutes
after the screen saver ends, unless you opened one of its windows.
If it is turned off there, Settings › Plugins › Screen Saver says so and opens Login Items; the
savers then show only the still while the app isn't running, and the extension shows the still
even while it is.

### Development builds

Xcode registers every app it builds, and macOS would list each development copy's extension as
another Open Wallpaper Engine screen saver and let its broker take the release one's place. So only
release builds (`OWE_EMBED_SCREEN_SAVER_EXTENSION`, the app target's "Embed Screen Saver Extension
and Broker" phase) carry the extension, the broker and its launch agent. Development builds keep
the classic saver; the lab build below adds the rest to a copy for testing.

### Testing it (lab build)

`Scripts/build-saver-lab.sh <out>` builds, without installing or registering anything:

- `<out>/OWE Live Lab.saver`: the screen saver, with its own bundle id
  (`app.openwallpaperengine.saver.lab`), name and class, so it sits beside the installed one;
- `<out>/Open Wallpaper Engine.app`: a development build of the app with the extension
  (`Contents/PlugIns/OpenWallpaperEngineSaverExtension.appex`, listed as *OWE Live Lab
  (extension)*) and the broker (`Contents/Helpers/owe-saver-broker`);
- `<out>/app.openwallpaperengine.saver-broker.plist`: the broker's launch agent.

Both lab savers log under the subsystem `app.openwallpaper.engine.saverlab` (views, lifecycle
notifications, surfaces found, the XPC connection, frames shown, fallbacks, and every 10 s the
process's CPU and GPU time, parked or not); the app logs `Live screen saver: …` lines.

1. Note which screen saver is selected (System Settings › Wallpaper › Screen Saver; Screen Saver
   on macOS 14 and 15), and quit Open Wallpaper Engine.
2. The broker (both savers: it launches the app for them when it isn't running): copy the plist
   to an internal disk first (`launchctl` refuses one on a volume with ownership disabled), then
   `cp <out>/app.openwallpaperengine.saver-broker.plist /private/tmp/` and
   `launchctl bootstrap gui/$(id -u) /private/tmp/app.openwallpaperengine.saver-broker.plist`.
   For the extension also `pluginkit -a "<out>/Open Wallpaper Engine.app/Contents/PlugIns/OpenWallpaperEngineSaverExtension.appex"`.
3. `open "<out>/Open Wallpaper Engine.app"` (Settings › Plugins › Screen Saver on). Like any
   build of the app, it installs its own Open Wallpaper Engine screen saver; your usual app puts
   its own back when it starts.
4. For the legacy saver: `cp -R "<out>/OWE Live Lab.saver" ~/Library/Screen\ Savers/`.
5. In a Terminal: `/usr/bin/log stream --level debug --predicate 'subsystem == "app.openwallpaper.engine.saverlab" OR (subsystem == "app.openwallpaperengine" AND eventMessage CONTAINS "Live screen saver")'`.
6. Select *OWE Live Lab* (or *OWE Live Lab (extension)*), click Preview, wait a minute and move
   the mouse. Then let the screen saver start on its own (the idle time, or a Hot Corner) and,
   where the Mac asks for the password after the screen saver, check that the lock screen keeps
   the last frame before unlocking. Leave the Mac at the desktop for a minute (the cost lines of
   hidden hosts).
7. Put it back: select the screen saver from step 1; `rm -rf ~/Library/Screen\ Savers/OWE\ Live\ Lab.saver`;
   `launchctl bootout gui/$(id -u)/app.openwallpaperengine.saver-broker`; for the extension
   `pluginkit -r "<out>/Open Wallpaper Engine.app/Contents/PlugIns/OpenWallpaperEngineSaverExtension.appex"`;
   quit the lab app and start your usual one.

## Lock screen picture

Settings › General › **Show Wallpaper on Lock Screen** (on by default) sets each display's desktop
picture to a picture of what it shows: its wallpaper, its part of a stretch, a flipped clone or
its split regions, with the display options. macOS shows that picture on the lock screen and
tints the menu bar from it. Pictures are updated when a wallpaper, layout or option changes, and
shown again after a Space change, a wake or a display change. Your own picture comes back when
the setting is turned off or the app quits.
