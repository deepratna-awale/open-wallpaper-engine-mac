# Capture request: sound-layer `spatialization`

What we need is WE's stereo output levels for a sound object that has `"spatialization": true`. No library wallpaper uses it, so our model comes only from wallpaper64.exe and OpenAL Soft 1.21.1 (see `docs/scenescript-plan.md`, "Spatialization").

## Projects

Each project is a 1920×1080 orthographic scene with a 440 Hz tone at 0.5 amplitude, 48 kHz, looping. The object's `origin` script moves it once per second (`engine.runtime`) through 11 steps, then starts again.

| folder | file | spatialization | movement |
|---|---|---|---|
| `1-spatial-mono-pan` | mono | on (defaults: `mindistance` 1, `attenuation` 1) | x = 0, 192, …, 1920 (y 540, z 0) |
| `2-spatial-mono-depth` | mono | on, `mindistance` 0.5, `attenuation` 2 | x 960, z = 750, 600, …, −750 |
| `3-spatial-stereo-pan` | stereo (the same tone in both channels) | on | like 1 |
| `4-plain-mono` | mono | off | like 1 (the reference level) |

## Procedure

1. Import each folder into WE as a local project (the editor's "Open wallpaper", or copy it into `projects/myprojects`). Play it as the wallpaper. Keep WE's volume at 100% and use no audio enhancements.
2. Write down the output device and whether Windows reports it as **headphones or speakers**. OpenAL Soft picks HRTF for headphones, and our model is only for the speaker (stereo "panpot") path. If you can, capture both.
3. Record the system output as a stereo WAV for at least 25 s per project, for example with Audacity using "Windows WASAPI" and the output device's loopback. Start at the wallpaper's load if you can, and note the offset if not.
4. Deliver the WAVs. Also give the left and right RMS for each one-second step, the middle 0.6 s of each second, found by lining up the steps from the level changes. Put them in `/Volumes/980Pro/agentSS-out/response/sound-spatialization/`.

## What we expect (speakers)

- **1:** see `expected-1-pan.md`. Values are relative to project 4's level per channel. Left and right cross over as the object moves from x = 0 to x = 1920. At the centre each channel is 0.679 of the plain level: in WE's frame the scene lies behind OpenAL's listener.
- **2:** see `expected-2-depth.md`. On the scene plane the distance is (750 − z)/750 of a unit, and the gain is `0.5 / (0.5 + 2·(d − 0.5))`. The sound stays centred.
- **3:** the same level as a plain stereo tone, not moving. OpenAL Soft doesn't spatialize stereo sources.
- In all projects, the first frame after load may be silent: before the render context has a camera, WE places the sound at (0, 0, 100000).

Any difference from these tables, especially in the sign of the pan (left and right swapped) or the centre level, tells us which assumption is wrong. The assumptions are the camera axes at ctx+0x160/0x16c/0x178 and the speaker decoder.
