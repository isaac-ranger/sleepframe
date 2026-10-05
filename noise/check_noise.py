#!/usr/bin/env python3
"""Check the noise files three different ways, reading them back from disk.

  1. slope    : Welch spectrum (scipy), straight-line fit in log-log, 30 Hz - 20 kHz
  2. octaves  : energy summed per octave from one whole-file transform (numpy)
  3. sox      : a separate program band-filters each octave and reports its level
  plain       : level, peak, clipping, offset, left/right independence, loop seam

Usage: check_noise.py DIR            exit 0 only if every line passes
       check_noise.py DIR --control  proves the checks can fail: white held to pink's law
"""
import re, subprocess, sys, wave
import numpy as np
from scipy import signal

LAW = {"white": 0.0, "pink": 1.0, "brown": 2.0}     # power ~ 1/f**alpha
OCT = 10 * np.log10(2)                              # 3.0103 dB
fails = 0


def line(ok, text):
    global fails
    fails += 0 if ok else 1
    print(("  pass  " if ok else "  FAIL  ") + text)


def load(path):
    with wave.open(path, "rb") as w:
        assert w.getnchannels() == 2 and w.getsampwidth() == 2, "want 16-bit stereo"
        rate, raw = w.getframerate(), w.readframes(w.getnframes())
    return rate, np.frombuffer(raw, "<i2").reshape(-1, 2).astype(np.float64) / 32767.0


def check(path, alpha):
    rate, x = load(path)
    want = OCT * (-alpha)                           # dB per octave, power density
    # 1. slope by Welch + least squares
    for ch, side in enumerate("LR"):
        f, p = signal.welch(x[:, ch], rate, nperseg=1 << 16)
        m = (f >= 30) & (f <= 20000)
        slope = np.polyfit(np.log2(f[m]), 10 * np.log10(p[m]), 1)[0]
        line(abs(slope - want) < 0.05, f"1 slope {side}: {slope:+.3f} dB/octave (law {want:+.3f})")
    # 2. octave sums from the whole-file transform: band energy changes by (1-alpha)*3.01 dB
    centres = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    f = np.fft.rfftfreq(x.shape[0], 1 / rate)
    power = sum(np.abs(np.fft.rfft(x[:, ch])) ** 2 for ch in (0, 1))
    band = [10 * np.log10(power[(f >= c / 2 ** .5) & (f < c * 2 ** .5)].sum()) for c in centres]
    steps = np.diff(band)
    worst = np.abs(steps - OCT * (1 - alpha)).max()
    line(worst < 0.3, f"2 octave steps: {' '.join(f'{s:+.2f}' for s in steps)} dB (law {OCT*(1-alpha):+.2f}, worst miss {worst:.2f})")
    # 3. sox filters each octave itself and reports the level
    lev = []
    for c in (250, 500, 1000, 2000, 4000, 8000):
        out = subprocess.run(["sox", path, "-n", "sinc", "-t", f"{c/40:.2f}", f"{c/2**.5:.1f}-{c*2**.5:.1f}", "stats"],
                             capture_output=True, text=True).stderr
        lev.append(float(re.search(r"RMS lev dB\s+(-?[\d.]+)", out).group(1)))
    steps = np.diff(lev)
    worst = np.abs(steps - OCT * (1 - alpha)).max()
    line(worst < 0.3, f"3 sox octave steps: {' '.join(f'{s:+.2f}' for s in steps)} dB (worst miss {worst:.2f})")
    # plain
    rms = 20 * np.log10(np.sqrt((x ** 2).mean(axis=0)))
    line(np.abs(rms + 20).max() < 0.05, f"level: L {rms[0]:.2f} R {rms[1]:.2f} dBFS (want -20.00)")
    peak = 20 * np.log10(np.abs(x).max()); at_rail = int((np.abs(x) >= 1.0).sum())
    line(at_rail == 0 and peak < -1, f"peak {peak:.1f} dBFS, samples at the limit {at_rail}")
    line(np.abs(x.mean(axis=0)).max() < 1e-4, f"offset: {x.mean(axis=0)[0]:+.1e} {x.mean(axis=0)[1]:+.1e}")
    r = np.corrcoef(x[:, 0], x[:, 1])[0, 1]
    line(abs(r) < 0.01, f"left/right correlation {r:+.4f} (independent is 0)")
    for ch, side in enumerate("LR"):
        seam = abs(x[0, ch] - x[-1, ch]); usual = np.quantile(np.abs(np.diff(x[:, ch])), 0.999)
        line(seam <= usual, f"loop seam {side}: step {seam:.4f}, ordinary large step {usual:.4f}")
    below = power[(f > 0) & (f < 15)].sum() / power.sum()
    line(below < 1e-6, f"energy below 15 Hz: {below:.1e} of the total")


def is_prime(n):
    return n > 1 and all(n % k for k in range(2, int(n ** 0.5) + 1))


d = sys.argv[1]
if "--control" in sys.argv:
    print("control: white noise held to pink's law (every spectrum line below must FAIL)")
    passed_before = fails
    check(f"{d}/white.wav", 1.0)
    # the control is itself checked: the four spectrum lines must have failed
    caught = fails - passed_before
    print("control caught" if caught >= 4 else f"CONTROL BROKEN: only {caught} of 4 spectrum lines failed")
    sys.exit(0 if caught >= 4 else 1)
lengths = {}
for name, alpha in LAW.items():
    print(name)
    check(f"{d}/{name}.wav", alpha)
    rate, x = load(f"{d}/{name}.wav")
    secs = len(x) / rate
    lengths[name] = secs
    line(secs == int(secs) and is_prime(int(secs)), f"length {secs:g} s is a whole, prime number of seconds")
print("together")
line(len(set(lengths.values())) == len(lengths), "no two loops are the same length: " +
     ", ".join(f"{n} {v:g} s" for n, v in lengths.items()))
print("ALL PASS" if fails == 0 else f"{fails} FAILED")
sys.exit(1 if fails else 0)
