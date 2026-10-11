# Screen saver and lock screen

macOS screen savers can't run Wallpaper Engine scenes, so Open Wallpaper Engine records a
seamless loop of the wallpaper and installs a screen saver that plays it. How it is built:
[`architecture.md`](architecture.md), "Lock screen and screen saver".

## The Screen Saver plugin

Settings › Plugins › **Screen Saver** (on by default) installs the Open Wallpaper Engine screen
saver in `~/Library/Screen Savers`. **Open Screen Saver Settings…** opens the System Settings pane
that holds the screen savers (Screen Saver, or Wallpaper on newer macOS), where you choose it. The
app never changes the system's screen saver setting itself. Turning the plugin off
removes the screen saver and its videos.

While it is on, the loop of the wallpaper you are showing is recorded in the background, at low
priority, waiting while the Mac is on battery or hot:

- **Scenes**: a loop the length of the scene's own animation where it repeats exactly (at most
  30 s), otherwise the stretch that comes back closest to its start (5 to 30 s), crossfaded at
  the seam.
- **Web pages and WebM videos**: recorded from the page on a stepped clock, so the loop is
  smooth even when a frame is slow to capture. A page that never loops smoothly isn't used.
- **Video wallpapers** (MP4 and MOV in H.264 or HEVC) play their own file, with nothing recorded.
- Audio-reactive wallpapers hear a steady beat while they are recorded, so they still move.
- Application wallpapers can't be used.

The loop is recorded at the largest display's pixels; the scene in it is drawn as Render
Resolution and Upscaling draw the live wallpaper, then fitted to the video. The Details panel shows whether a wallpaper's screen saver is
available (**Screen Saver Available**), being made (**Rendering Screen Saver**) or not
(**Screen Saver Not Available**, with the reason in its tooltip).

A loop is a recording: clocks, dates, media info and audio-reactive parts show the moment it was
recorded.

## The Screen Saver tab

Scene Edit / Export's second tab (Wallpaper | Screen Saver | iPhone & iPad Export | Android
Export) makes the
screen saver from a scene wallpaper's own version:

- It runs a private copy of the wallpaper. Turning layers on or off, adjusting them and changing
  user properties there never touches your desktop, its properties or the Wallpaper Editor's
  edits. These choices are kept for each wallpaper as its screen saver's own, and the live
  screen saver draws it with them.
- **Set as Screen Saver** makes this version of the wallpaper the screen saver, turning the
  plugin on if it is off. Nothing is recorded: while the screen saver runs, the app draws it live
  on every display with the tab's choices (its layers and user properties), so clocks, dates and
  audio-reactive parts move. Its preview is the screen saver's still until a live draw keeps a
  frame of it. **Stop Using as Screen Saver** goes back to the desktop's wallpaper.
- When the app starts, a recording an earlier version set as the screen saver becomes this
  live pick of its wallpaper.

A video wallpaper (MP4, M4V or MOV) opens Scene Edit / Export on this tab too, with the
video playing: its screen saver is the video itself, so there is nothing to record or adjust.
**Set as Screen Saver** makes it the screen saver (turning the plugin on if it is off), and
**Stop Using as Screen Saver** goes back to the desktop's wallpaper.

## Screen saver layout

With several displays, Display Settings' **Screen saver layout** is **Same as wallpaper** (the
displays' layout and groups) by default, or a loop per display, one stretched across the
displays, or one cloned. See [`display-layouts.md`](display-layouts.md).

## Live screen saver (in progress)

Development builds draw the screen saver live instead of playing the recording; release builds
keep the recording until this has been tried on real screen saver hosts (Phase 0 below).

- While the screen saver runs and an Open Wallpaper Engine saver is showing, the app draws each
  display's wallpaper live as the screen saver's layout plans it (per display, cloned or
  stretched), with the screen saver's own settings: scripts see `engine.isScreensaver()` true, the
  clock layers are drawn and live, audio-reactive parts follow what the Mac plays, and the sound
  stays off. The saver shows each frame as it comes, at the display's cadence (60 fps on a 165 Hz
  display is 55, as on the desktop).
- Web wallpapers and WebM videos are drawn by the Chromium engine whichever engine the desktop
  uses (WebKit stops a page the screen saver covers). When the desktop already shows the page in
  Chromium on that display, that page is drawn from; otherwise a page of its own, without a
  window. Without the Chromium engine they show their picture, and Settings › Plugins › Screen
  Saver offers to install it.
- It draws only then: it stops when the screen saver stops (or the Mac is unlocked), and another
  screen saver or the System Settings preview never makes it draw.
- Until the first frames come, each display shows its lock-screen picture (with Show Wallpaper on
  Lock Screen on). When the app isn't running, the saver asks for it: the broker launches it in
  the background, with no window or Dock icon, and it starts loading the wallpaper at once.
- The saver plays the recorded loop whenever the app isn't drawing and there is one (for now: the
  recordings go in a later step). A Screen Saver mode recording set as the screen saver always
  plays as recorded.
- After the screen saver stops the lock screen keeps its last frame. A view the host makes at the
  lock shows the live frames at once.

Two savers show the frames: the screen saver in `~/Library/Screen Savers` (macOS 14 and later),
and a screen saver extension in macOS's newer format, inside the app, which is built only for
testing so far (macOS 14 and later; it needs the app's broker, below).

### Testing it (Phase 0)

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
