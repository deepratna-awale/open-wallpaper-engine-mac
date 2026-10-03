# 3299228616 "Lonely Cat": clock area in WE 2.8.0.42

## Capture
- **Settings:** default properties, English, 1920x1080 on monitor 2.
- **Audio:** audio was playing on the PC, so the bars react.
- **Shots:** `full_1..3.png` are full-resolution screenshots 1 s apart; the Windows taskbar covers the bottom 48 px.
- **Crops:** `clock_crop_1..3.png` crop x 780–1120, y 140–300, scaled 3x with nearest-neighbour.

## How WE draws the clock area
- **No dark or translucent rectangle behind the clock.** The time, the date and the bars sit directly on the scene.
- **AM/PM:** "AM" is drawn once at full brightness, top right of the minutes, at about (1065–1090, 193–203).
  - A **second, faint copy sits directly below it**, at about 25–30% opacity, like a dim mirrored or ghost text layer.
  - So a second label exists in WE too. It is dim and below the first, not a second full-strength label.
- **Date line overlaps the lower audio bars in WE as well.** "Saturday, 3 October" sits at about y 250–262. The lower bar row starts at the same height and grows **upward through the date text**: bars are drawn over the date's left part (see `clock_crop_3`).
- **Bars:** two rows of white vertical bars, one above the time (growing up from about y 188) and one below (from about y 275).
  - They span about x 825–1060.
  - The right-hand part of each row shows short dashes, the low or near-silent bins.
