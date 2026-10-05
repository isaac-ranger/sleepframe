#!/usr/bin/env python3
"""Cut each chosen recording into a seamless loop at a matched loudness.

usage: make_loops.py [NAME...]        (no names: all of them)

For each entry in LOOPS: take the window, bring it to 48 kHz stereo, fold the last
FADE seconds into the first (equal-power), so the end meets the start without a seam,
set the loudness, and write
    loops/NAME.flac   24-bit master
    loops/NAME.ogg    what ships (Vorbis q8)
and a line in loops/LOOPS.tsv saying exactly what was done to which source.

Nothing else is done to the sound: no noise reduction, no EQ, no compression.
The one exception is marked `tame`, for a clap that would wake a sleeper.
"""
import subprocess, sys, time
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
RAW, OUT = HERE / "raw", HERE / "loops"
SR = 48000
TARGET_LUFS = -30.0      # masters sit low; the scene and launcher set the playing level

# name: (source file, start s, end s or None, crossfade s, extra)
# Every loop comes out a prime number of seconds long (157, 277, 197, 317, 359, 439), like the
# noises (127, 131, 137): no two share a period, so a mix does not come round to the same combination.
# Heard on the headset 2026-10-04 and dropped: steady night rain (sounds urban), Dellec beach #1 and #2
# (small bird calls that would be heard looping), wind in a cornfield (not right). Thunder: only the
# opening stretch of ordinary distant rolls; the big claps were bad even held down, so nothing is tamed.
LOOPS = {
    "rain-porch":   ("fs-454128-kyles-rain-heavy-porch.flac", 136.0, 299.0, 6.0, {}),
    "rain-rural":   ("fs-200270-jmbphilmes-rain-heavy-rural.wav", 100.0, 383.0, 6.0, {}),
    "rain-tent":    ("bsb-0820-rain-thunder-tent.wav", 2.0, 205.0, 6.0, {}),
    "ocean-cliff":  ("bsb-2570-ocean-cliff1.flac", 2.0, 327.0, 8.0, {}),
    "wind-trees":   ("bsb-1451-wind-strong-trees2.flac", 2.0, 369.0, 8.0, {}),
    "thunder":      ("bsb-2719-rain-thunder4-35min.flac", 5.0, 454.0, 10.0, {}),
}


def decode(path, start, end):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start)]
    if end is not None:
        cmd += ["-to", str(end)]
    cmd += ["-i", str(path), "-ac", "2", "-af", f"aresample={SR}:resampler=soxr:precision=28",
            "-f", "f32le", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def lufs(x):
    """Integrated loudness, read by ffmpeg's ebur128."""
    p = subprocess.run(["ffmpeg", "-v", "info", "-f", "f64le", "-ar", str(SR), "-ac", "2", "-i", "-",
                        "-af", "ebur128", "-f", "null", "-"], input=x.tobytes(), capture_output=True)
    for line in reversed(p.stderr.decode().splitlines()):
        if line.strip().startswith("I:"):
            return float(line.split()[1])
    raise RuntimeError("no loudness read")


def tame(x, over_db):
    """Hold down anything that rises more than over_db above the bed. Slow gain, no pumping:
    the level is read in 400 ms steps, the gain moves over a second."""
    win = int(0.4 * SR)
    n = len(x) // win
    lvl = np.sqrt((x[: n * win].reshape(n, win, 2) ** 2).mean(axis=(1, 2)))
    bed = np.median(lvl)
    ceiling = bed * 10 ** (over_db / 20)
    gain = np.minimum(1.0, ceiling / np.maximum(lvl, 1e-12))
    # look a step ahead and behind so the gain is already down when the clap arrives
    gain = np.minimum.reduce([gain, np.roll(gain, 1), np.roll(gain, -1)])
    t = (np.arange(n) + 0.5) * win
    g = np.interp(np.arange(len(x)), t, gain)
    k = SR                                  # one-second smoothing
    c = np.cumsum(np.pad(g, (k // 2 + 1, k // 2), mode="edge"))      # a running mean, by running sum
    g = ((c[k:] - c[:-k]) / k)[: len(x)]
    held = int((gain < 0.999).sum())
    return x * g[:, None], held * 0.4, float(20 * np.log10(gain.min()))


def make(name):
    src, start, end, fade, extra = LOOPS[name]
    x = decode(RAW / src, start, end)
    x -= x.mean(axis=0)
    note = ""
    if "tame" in extra:
        x, secs, deepest = tame(x, extra["tame"])
        note = f"tamed {secs:.0f} s of claps over +{extra['tame']:.0f} dB, deepest {deepest:.1f} dB"
    f = int(fade * SR)
    body, tail = x[:-f].copy(), x[-f:]
    ramp = np.linspace(0.0, 1.0, f)[:, None]
    body[:f] = body[:f] * np.sqrt(ramp) + tail * np.sqrt(1.0 - ramp)     # equal power: the bed keeps its level
    was = lufs(body)
    body *= 10 ** ((TARGET_LUFS - was) / 20)
    peak = float(np.abs(body).max())
    if peak > 0.98:                          # never clip: come down instead, and say so
        body *= 0.98 / peak
        note = (note + "; " if note else "") + f"lowered {20 * np.log10(peak / 0.98):.1f} dB more to keep the peak clear"
    now = lufs(body)

    OUT.mkdir(exist_ok=True)
    flac, ogg = OUT / f"{name}.flac", OUT / f"{name}.ogg"
    common = ["ffmpeg", "-v", "error", "-y", "-f", "f64le", "-ar", str(SR), "-ac", "2", "-i", "-"]
    subprocess.run(common + ["-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24", str(flac)],
                   input=body.tobytes(), check=True)
    subprocess.run(common + ["-c:a", "libvorbis", "-q:a", "8", str(ogg)], input=body.tobytes(), check=True)

    secs = len(body) / SR
    line = (f"{name}\t{src}\t{start:g}-{end:g} s\tcrossfade {fade:g} s\tloop {int(secs // 60)}:{secs % 60:04.1f}\t"
            f"{was:.1f} -> {now:.1f} LUFS\tpeak {20 * np.log10(np.abs(body).max()):.1f} dBFS\t{note}\t{time.strftime('%Y-%m-%d')}")
    rows = [r for r in (OUT / "LOOPS.tsv").read_text().splitlines() if not r.startswith(name + "\t")] \
        if (OUT / "LOOPS.tsv").exists() else []
    (OUT / "LOOPS.tsv").write_text("\n".join(rows + [line]) + "\n")
    print(line.replace("\t", "  |  "), f" |  ogg {ogg.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    for n in (sys.argv[1:] or LOOPS):
        make(n)
