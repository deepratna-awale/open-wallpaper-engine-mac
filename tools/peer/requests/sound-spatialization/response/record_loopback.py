"""Record the default output device via WASAPI loopback to a stereo 48 kHz WAV (soundcard package)."""
import sys, wave, numpy as np, soundcard as sc

seconds, path = float(sys.argv[1]), sys.argv[2]
spk = sc.default_speaker()
mic = sc.get_microphone(id=str(spk.name), include_loopback=True)
with mic.recorder(samplerate=48000, channels=2) as rec:
    data = rec.record(numframes=int(48000 * seconds))
pcm = np.clip(data, -1, 1)
with wave.open(path, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
    w.writeframes((pcm * 32767).astype("<i2").tobytes())
print("recorded", path, data.shape, "peak L/R %.4f %.4f" % tuple(np.abs(data).max(axis=0)), "device", spk.name)
