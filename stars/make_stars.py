#!/usr/bin/env python3
"""Turn the Bright Star Catalogue (CDS V/50, catalog.gz) into stars.dat for the scene.

One line per star: x,y,z,vmag,r,g,b
  x,y,z  unit vector in the scene's axes: +Y is celestial north, +X is RA 0h on the equator,
         -Z is RA 6h. (A pure rotation of the usual equatorial axes, so the sky is not mirrored.)
  vmag   visual magnitude (smaller is brighter)
  r,g,b  colour from the B-V index, 0..1, brightest channel = 1
"""
import gzip, math, sys

def colour(bv):
    bv = max(-0.4, min(2.0, bv))
    t = 4600.0 * (1.0 / (0.92 * bv + 1.7) + 1.0 / (0.92 * bv + 0.62))   # Ballesteros 2012
    # blackbody to RGB, Tanner Helland's fit, good for 1000-40000 K
    k = t / 100.0
    r = 255.0 if k <= 66 else 329.698727446 * (k - 60) ** -0.1332047592
    g = 99.4708025861 * math.log(k) - 161.1195681661 if k <= 66 else 288.1221695283 * (k - 60) ** -0.0755148492
    b = 255.0 if k >= 66 else (0.0 if k <= 19 else 138.5177312231 * math.log(k - 10) - 305.0447927307)
    c = [max(0.0, min(255.0, v)) for v in (r, g, b)]
    m = max(c)
    return [v / m for v in c], t

def parse(line):
    try:
        ra = (int(line[75:77]) + int(line[77:79]) / 60 + float(line[79:83]) / 3600) * 15.0
        dec = int(line[84:86]) + int(line[86:88]) / 60 + int(line[88:90]) / 3600
        if line[83] == "-":
            dec = -dec
        vmag = float(line[102:107])
    except ValueError:
        return None                      # the catalogue keeps 14 non-star entries with blank positions
    try:
        bv = float(line[109:114])
    except ValueError:
        bv = 0.6                         # no colour measured: treat as sun-like
    return int(line[0:4]), line[4:14].strip(), ra, dec, vmag, bv

def vec(ra, dec):
    a, d = math.radians(ra), math.radians(dec)
    X, Y, Z = math.cos(d) * math.cos(a), math.cos(d) * math.sin(a), math.sin(d)
    return X, Z, -Y

stars = [s for s in (parse(l) for l in gzip.open("catalog.gz", "rt", encoding="latin-1")) if s]
with open("../game/stars.dat", "w") as f:
    for hr, name, ra, dec, vmag, bv in stars:
        x, y, z = vec(ra, dec)
        (r, g, b), _ = colour(bv)
        f.write(f"{x:.6f},{y:.6f},{z:.6f},{vmag:.2f},{r:.3f},{g:.3f},{b:.3f}\n")
print(f"{len(stars)} stars written; brightest {min(s[4] for s in stars)}, faintest {max(s[4] for s in stars)}")

# ---- checks against stars I know
by = {s[0]: s for s in stars}
def show(hr, label, ra_h, dec_d, v):
    s = by[hr]; ok = abs(s[2] / 15 - ra_h) < 0.01 and abs(s[3] - dec_d) < 0.02 and abs(s[4] - v) < 0.06
    print(f"  {'pass' if ok else 'FAIL'}  {label}: RA {s[2]/15:.3f} h, Dec {s[3]:+.2f}, V {s[4]}, B-V {s[5]}, about {colour(s[5])[1]:.0f} K, rgb {[round(c,2) for c in colour(s[5])[0]]}")
    return ok
ok = all([show(2491, "Sirius", 6.752, -16.72, -1.46), show(7001, "Vega", 18.616, 38.78, 0.03),
          show(2061, "Betelgeuse", 5.919, 7.41, 0.50), show(1713, "Rigel", 5.242, -8.20, 0.12),
          show(424, "Polaris", 2.530, 89.26, 2.02)])
# handedness: looking at Orion with north up, Betelgeuse (east) must be LEFT of Bellatrix
def sub(a, b): return [a[i] - b[i] for i in range(3)]
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def dot(a, b): return sum(a[i]*b[i] for i in range(3))
bet, bel = vec(by[2061][2], by[2061][3]), vec(by[1790][2], by[1790][3])
fwd = [(bet[i] + bel[i]) / 2 for i in range(3)]; right = cross(fwd, [0, 1, 0])
left_ok = dot(bet, right) < dot(bel, right)
print(f"  {'pass' if left_ok else 'FAIL'}  not mirrored: Betelgeuse sits left of Bellatrix with north up")
pol = vec(by[424][2], by[424][3]); print(f"  {'pass' if pol[1] > 0.999 else 'FAIL'}  Polaris is at the scene's north (+Y): y = {pol[1]:.4f}")
sys.exit(0 if ok and left_ok and pol[1] > 0.999 else 1)
