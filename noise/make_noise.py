#!/usr/bin/env python3
"""Make white, pink and brown noise as seamless stereo loops of about two minutes.

Each noise is built in the frequency domain: every frequency gets a random phase
and a random (Gaussian) strength whose average power follows the colour's law,

    power(f)  proportional to  1 / f**alpha      alpha = 0 white, 1 pink, 2 brown

so the amplitude at f is scaled by f**(-alpha/2). Per doubling of frequency that is
0 dB (white), -3.01 dB (pink), -6.02 dB (brown).  Nothing below 20 Hz, no DC.
The inverse transform of a spectrum is exactly periodic, so the loop has no seam.
Left and right are made from separate random draws.
"""
import sys, wave
import numpy as np

RATE = 48000
# One length per colour, each a prime number of seconds: no two loops share a period, so a mix
# of them does not come round to the same combination (any two realign only after hours).
SECONDS = {"white": 127, "pink": 131, "brown": 137}
LOW_CUT = 20.0                    # Hz; nothing below this
TARGET_RMS_DB = -20.0             # dB below full scale, each channel
COLOURS = {"white": 0.0, "pink": 1.0, "brown": 2.0}


def channel(alpha, rng, n):
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    spec = rng.standard_normal(f.size) + 1j * rng.standard_normal(f.size)
    shape = np.zeros_like(f)
    keep = f >= LOW_CUT
    shape[keep] = f[keep] ** (-alpha / 2.0)
    spec *= shape
    if n % 2 == 0:
        spec[-1] = spec[-1].real      # the Nyquist bin of a real signal is real
    x = np.fft.irfft(spec, n)
    return x * (10 ** (TARGET_RMS_DB / 20.0) / np.sqrt(np.mean(x * x)))


def main(outdir="."):
    for i, (name, alpha) in enumerate(COLOURS.items()):
        n = RATE * SECONDS[name]
        rng = np.random.default_rng(20261004 + i)      # fixed seed: the file can be remade exactly
        both = np.stack([channel(alpha, rng, n), channel(alpha, rng, n)], axis=1)
        peak = np.abs(both).max()
        # 16-bit with triangular dither of one step, the standard way to round
        dither = (rng.random(both.shape) - rng.random(both.shape))
        pcm = np.round(both * 32767.0 + dither)
        clipped = int(np.sum(np.abs(pcm) > 32767))
        pcm = np.clip(pcm, -32767, 32767).astype("<i2")
        with wave.open(f"{outdir}/{name}.wav", "wb") as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        print(f"{name}: {n} samples per channel, peak {20*np.log10(peak):.1f} dBFS, clipped samples {clipped}")


if __name__ == "__main__":
    main(*sys.argv[1:])
