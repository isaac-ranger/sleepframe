#!/usr/bin/env python3
"""Measure a field recording before anyone has to listen to it.

usage: inspect_sound.py FILE [FILE...]

Prints, per file: format, length, peak, clipped samples, loudness over time, the
events that stand out of the bed (time, how far above it), low hum, and left/right
balance. Writes a spectrogram beside the report in looks/.

This screens out bad files. It does not say a file sounds good; ears do that.
"""
import json, subprocess, sys
from pathlib import Path

import numpy as np

SR = 48000
LOOKS = Path(__file__).parent / "looks"


def probe(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=codec_name,sample_rate,channels,bits_per_raw_sample,bits_per_sample:format=duration",
         "-of", "json", str(path)], capture_output=True, text=True).stdout
    j = json.loads(out)
    s = j["streams"][0]
    bits = s.get("bits_per_raw_sample") or s.get("bits_per_sample") or "?"
    return s["codec_name"], int(s["sample_rate"]), int(s["channels"]), bits, float(j["format"]["duration"])


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "2", "-ar", str(SR), "-f", "f32le", "-"],
        capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)


def db(x):
    return 20 * np.log10(np.maximum(x, 1e-12))


def band_rms(mono, lo, hi):
    spec = np.fft.rfft(mono[: min(len(mono), SR * 60)])
    f = np.fft.rfftfreq(min(len(mono), SR * 60), 1 / SR)
    m = (f >= lo) & (f < hi)
    return np.sqrt(np.sum(np.abs(spec[m]) ** 2)) / len(spec)


def inspect(path):
    path = Path(path)
    codec, sr, ch, bits, dur = probe(path)
    x = decode(path)
    mono = x.mean(axis=1)
    peak = float(np.abs(x).max())
    clipped = int((np.abs(x) >= 0.999).sum())

    # the bed: RMS in 400 ms windows, hop 100 ms
    win, hop = int(0.4 * SR), int(0.1 * SR)
    n = (len(mono) - win) // hop
    idx = np.arange(n)[:, None] * hop + np.arange(0, win, 8)[None, :]
    lvl = db(np.sqrt((mono[idx] ** 2).mean(axis=1)))
    med = float(np.median(lvl))
    p5, p95 = np.percentile(lvl, [5, 95])

    # slow drift: one-minute medians
    per_min = [float(np.median(lvl[i:i + 600])) for i in range(0, len(lvl), 600)]

    # events: stretches more than 8 dB over a rolling 20 s median
    k = 200
    pad = np.pad(lvl, (k // 2, k // 2), mode="edge")
    roll = np.array([np.median(pad[i:i + k]) for i in range(0, len(lvl), 10)])
    roll = np.repeat(roll, 10)[: len(lvl)]
    over = lvl - roll
    events, i = [], 0
    while i < len(over):
        if over[i] > 8:
            j = i
            while j < len(over) and over[j] > 4:
                j += 1
            events.append((i * hop / SR, (j - i) * hop / SR, float(over[i:j].max())))
            i = j
        else:
            i += 1

    # spectrum balance and mains hum (50 and 60 Hz against their neighbours)
    low, mid, high = (band_rms(mono, a, b) for a, b in ((20, 200), (200, 2000), (2000, 16000)))
    top = band_rms(mono, 16000, 22000)
    hum = {}
    seg = mono[: min(len(mono), SR * 60)] * np.hanning(min(len(mono), SR * 60))
    spec = np.abs(np.fft.rfft(seg))
    f = np.fft.rfftfreq(len(seg), 1 / SR)
    for hz in (50, 60, 100, 120):
        # mean power against mean power, so plain noise reads 0 dB
        line = np.mean(spec[(f > hz - 0.5) & (f < hz + 0.5)] ** 2)
        near = np.mean(spec[((f > hz - 8) & (f < hz - 2)) | ((f > hz + 2) & (f < hz + 8))] ** 2)
        hum[hz] = float(10 * np.log10(line / near))
    lr = float(db(np.sqrt((x[:, 0] ** 2).mean())) - db(np.sqrt((x[:, 1] ** 2).mean())))
    corr = float(np.corrcoef(x[::16, 0], x[::16, 1])[0, 1])
    dc = float(mono.mean())

    LOOKS.mkdir(exist_ok=True)
    png = LOOKS / (path.stem + ".spec.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-lavfi",
                    "aformat=channel_layouts=mono,showspectrumpic=s=1800x700:legend=1:scale=log:fscale=log:drange=100",
                    str(png)])

    print(f"\n== {path.name}")
    print(f"   {codec} {sr} Hz {ch} ch {bits} bit   {int(dur // 60)}:{dur % 60:04.1f}")
    print(f"   peak {db(peak):.1f} dBFS   clipped samples {clipped}   DC {dc:+.5f}")
    print(f"   bed level median {med:.1f} dB   quiet-to-loud (5%..95%) {p5:.1f} .. {p95:.1f}  = {p95 - p5:.1f} dB swing")
    print("   by minute: " + " ".join(f"{v:.0f}" for v in per_min))
    print(f"   balance low/mid/high {db(low):.0f} / {db(mid):.0f} / {db(high):.0f} dB   above 16 kHz {db(top):.0f}")
    print("   hum over neighbours: " + "  ".join(f"{hz} Hz {v:+.0f} dB" for hz, v in hum.items()))
    print(f"   left minus right {lr:+.1f} dB   left/right likeness {corr:.2f}")
    print(f"   events over the bed (>8 dB): {len(events)}")
    for t, d, a in events[:40]:
        print(f"      {int(t // 60)}:{t % 60:04.1f}  lasts {d:.1f} s  +{a:.0f} dB")
    if len(events) > 40:
        print(f"      ... and {len(events) - 40} more")
    print(f"   picture {png}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        inspect(p)
