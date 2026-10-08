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

The Scene Editor (Live)'s second tab (Wallpaper | Screen Saver | iPhone & iPad Export | Android
Export) makes the
screen saver from a scene wallpaper's own version:

- It runs a private copy of the wallpaper. Turning layers on or off, adjusting them and changing
  user properties there never touches your desktop, its properties or the Wallpaper Editor's
  edits. These choices are kept for each wallpaper as its screen saver's own, so the next
  recording reuses them.
- A note at the top reminds you the screen saver is a video: hide layers that show the date, the
  time or other live data, or use the daily re-recording.
- **Record and Set as Screen Saver** records the loop and makes it the screen saver, turning the
  plugin on if it is off. The previous video is replaced at once, never left missing or
  half-written. **Preview Recording** plays it beside the live preview. While a recording is set,
  the desktop's wallpaper isn't recorded; **Stop Using as Screen Saver** goes back to it.
- **Re-record Every Day at** a time you choose (off by default): while Open Wallpaper Engine is
  running, the screen saver is recorded again each day with that day's date and time, at
  background priority, waiting while the battery is below 30 %. A time missed while the Mac slept
  or the app was quit is recorded once at the next wake or launch. The tab shows when it was last
  recorded and when it will be next.

A video wallpaper (MP4, M4V or MOV) opens the Scene Editor (Live) on this tab too, with the
video playing: its screen saver is the video itself, so there is nothing to record or adjust.
**Set as Screen Saver** makes it the screen saver (turning the plugin on if it is off), and
**Stop Using as Screen Saver** goes back to the desktop's wallpaper.

## Screen saver layout

With several displays, Display Settings' **Screen saver layout** is **Same as wallpaper** (the
displays' layout and groups) by default, or a loop per display, one stretched across the
displays, or one cloned. See [`display-layouts.md`](display-layouts.md).

## Lock screen picture

Settings › General › **Show Wallpaper on Lock Screen** (on by default) sets each display's desktop
picture to a picture of what it shows: its wallpaper, its part of a stretch, a flipped clone or
its split regions, with the display options. macOS shows that picture on the lock screen and
tints the menu bar from it. Pictures are updated when a wallpaper, layout or option changes, and
shown again after a Space change, a wake or a display change. Your own picture comes back when
the setting is turned off or the app quits.
