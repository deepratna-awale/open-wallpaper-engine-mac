# Sound spatialization: WE 2.8.0.42 ground truth

## Setup
- **Output device:** "Speaker (Realtek(R) Audio)", the laptop's built-in speakers and the default device. Windows reports them as **speakers**, not headphones, so this is the speaker (panpot) path. A second device, the VG27VQ3B display audio, was not used. HRTF was not captured: no headphones are connected.
- **WE settings:** volume at the default. Playback rules were temporarily set to "run" so that maximized windows wouldn't pause the wallpaper, then restored.
- **Recording:** WASAPI loopback of the default device, using the Python `soundcard` package (`record_loopback.py`), stereo 48 kHz 16-bit, 27 s per project. Recording starts about 0.8 s before the openWallpaper command.
  - The system output was **muted** by the user. Loopback captures the mix before the endpoint mute, so the levels are unaffected. The user's volume was not touched.
  - `soundcard` reported occasional "data discontinuity" warnings, i.e. dropped capture buffers. Only the middle 0.6 s of each second is used, and the steady values below repeat to 4 decimals across cycles.
- **WAVs:** `1-spatial-mono-pan.wav`, `2-spatial-mono-depth.wav`, `3-spatial-stereo-pan.wav`, `4-plain-mono.wav`.
- **Analysis:** `analyze.py`, with full per-second numbers in `results.json`.
  - Seconds are counted from the tone onset (the wallpaper load, engine.runtime ≈ 0). The step is second % 11. RMS is taken over the middle 0.6 s, as requested.
  - **Reference:** project 4 (plain mono, no spatialization) has L/R RMS **0.11924 / 0.11924**, flat.

## 1: spatial mono, panned left → right (relative to project 4, per channel)
Values from the second cycle (t = 11…21 s), which repeat exactly in the third.

| step | x | measured L / R | expected L / R |
|---|---|---|---|
| 0 | 0 | **1.0760 / 0.3172** | 1.0579 / 0.3314 |
| 1 | 192 | 1.0053 / 0.3761 | 0.9904 / 0.3886 |
| 2 | 384 | 0.9288 / 0.4426 | 0.9174 / 0.4528 |
| 3 | 576 | 0.8476 / 0.5162 | 0.8400 / 0.5234 |
| 4 | 768 | 0.7636 / 0.5956 | 0.7598 / 0.5993 |
| 5 | 960 | **0.6788 / 0.6788** | 0.6788 / 0.6788 |
| 6 | 1152 | 0.5956 / 0.7636 | 0.5993 / 0.7598 |
| 7 | 1344 | 0.5162 / 0.8476 | 0.5234 / 0.8400 |
| 8 | 1536 | 0.4426 / 0.9288 | 0.4528 / 0.9174 |
| 9 | 1728 | 0.3761 / 1.0053 | 0.3886 / 0.9904 |
| 10 | 1920 | **0.3172 / 1.0760** | 0.3314 / 1.0579 |

- **Pan sign:** correct. The object at x = 0 is loud in the **left** channel.
- **Centre:** exactly **0.6788** in both channels.
- **Symmetry:** the curve is symmetric.
- **Pan strength:** stronger than modelled at the edges, by +0.018 on the near side and −0.014 on the far side at x = 0/1920. Mid-steps are within about 0.004–0.01.
- **Onset:** the very first second after load (t = 0) reads 1.0329 / 0.3045, lower because it contains the load transient.

## 2: spatial mono in depth (mindistance 0.5, attenuation 2; relative to project 4)

| step | z | distance | measured L = R | expected |
|---|---|---|---|---|
| 0 | 750 | 0.00 | 1.0000 | 1.0000 |
| 1 | 600 | 0.20 | 0.6788 | 0.6788 |
| 2 | 450 | 0.40 | 0.6788 | 0.6788 |
| 3 | 300 | 0.60 | 0.4848 | 0.4849 |
| 4 | 150 | 0.80 | 0.3085 | 0.3085 |
| 5 | 0 | 1.00 | 0.2262 | 0.2263 |
| 6 | −150 | 1.20 | 0.1785 | 0.1786 |
| 7 | −300 | 1.40 | 0.1475 | 0.1476 |
| 8 | −450 | 1.60 | 0.1256 | 0.1257 |
| 9 | −600 | 1.80 | 0.1094 | 0.1095 |
| 10 | −750 | 2.00 | 0.0969 | 0.0970 |

- **Match:** to 4 decimals, and the sound stays centred (L = R).
- **Onset:** the first cycle's step 0 (first second after load) reads 0.9572, the expected load-time transient. From the second cycle on it is exactly 1.0000.

## 3: spatial stereo tone
- **Not spatialized:** it stays at a **constant 1.6789× the plain-mono level** in both channels at every step, with no pan and no attenuation.
- **Level:** 1.6789 ≈ 1/0.5956, so a *plain* (non-spatialized) mono source plays at about 0.596 of the level of the same tone as a stereo source.
- **Onset:** the first second after load reads 1.611, again the load transient.

## Load transient
In every project the first second after load is a few percent low (0.957–0.97 of steady state). This is consistent with a silent or placeholder first frame before the camera exists.
