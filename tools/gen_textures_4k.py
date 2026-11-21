"""Generate tileable 4K PBR texture sets for PotionCrafter props.

Every set is built from FFT-filtered noise, which is periodic by construction,
so the textures tile seamlessly (they're applied with triplanar mapping).
Albedo maps are near-neutral detail (the prop's own colour tints them in
Godot), normal maps are OpenGL-style (Y+, Godot's convention) derived from a
height field, and roughness maps are greyscale.

Usage:  python tools/gen_textures_4k.py [size] [set ...]   (default 4096, all sets)
Output: content/textures_4k/<set>_{albedo,normal,rough}.jpg
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 4096
OUT = os.path.join(os.path.dirname(__file__), "..", "content", "textures_4k")
RNG = np.random.default_rng(20261120)

_fx = np.fft.fftfreq(SIZE)[None, :]
_fy = np.fft.fftfreq(SIZE)[:, None]


def noise(beta=2.0, sx=1.0, sy=1.0, lo=0.0, hi=0.5):
    """Periodic fractal noise in [0,1]: white noise shaped by 1/f^beta in the
    frequency domain. sx/sy stretch it (grain), lo/hi band-limit it."""
    white = RNG.standard_normal((SIZE, SIZE))
    f = np.sqrt((_fx * sx) ** 2 + (_fy * sy) ** 2)
    f[0, 0] = 1.0
    amp = 1.0 / f ** (beta * 0.5)
    amp[(f < lo) | (f > hi)] = 0.0
    amp[0, 0] = 0.0
    n = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    n -= n.min()
    return n / max(n.max(), 1e-9)


def warp(field, dx, dy, strength):
    """Periodic domain warp: sample `field` at (x + dx*s, y + dy*s), wrapping."""
    h, w = field.shape
    yy, xx = np.mgrid[0:h, 0:w]
    sx = (xx + (dx - 0.5) * strength * w) % w
    sy = (yy + (dy - 0.5) * strength * h) % h
    return field[sy.astype(np.int32), sx.astype(np.int32)]


def normal_from_height(height, strength):
    """Tangent-space normal map (OpenGL, Y+) from a periodic height field."""
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx = -gx * strength
    ny = gy * strength  # image rows go down; OpenGL green points up
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return (n * 0.5 + 0.5)


def save(name, albedo, height, rough, normal_strength):
    os.makedirs(OUT, exist_ok=True)
    a = np.clip(albedo, 0.0, 1.0)
    if a.ndim == 2:
        a = np.stack([a, a, a], axis=-1)
    Image.fromarray((a * 255.0 + 0.5).astype(np.uint8)).save(os.path.join(OUT, f"{name}_albedo.jpg"), quality=92)
    n = normal_from_height(height, normal_strength)
    Image.fromarray((n * 255.0 + 0.5).astype(np.uint8)).save(os.path.join(OUT, f"{name}_normal.jpg"), quality=95)
    r = np.clip(rough, 0.0, 1.0)
    Image.fromarray((r * 255.0 + 0.5).astype(np.uint8)).save(os.path.join(OUT, f"{name}_rough.jpg"), quality=92)
    print("wrote", name)


def warm(gray, tint=(1.0, 0.96, 0.9)):
    return np.stack([gray * tint[0], gray * tint[1], gray * tint[2]], axis=-1)


def wood():
    low = noise(2.6, lo=0.0, hi=0.005)
    low2 = noise(2.6, lo=0.0, hi=0.012)
    # Growth rings running along x, warped by slow noise.
    yy = np.mgrid[0:SIZE, 0:SIZE][0] / SIZE
    # Growth rings along x: many thin rings of uneven width, each a soft
    # earlywood band ending in a sharp dark latewood line (flat-sawn oak).
    ring_count = 48
    phase = (yy + (low - 0.5) * 0.09 + (low2 - 0.5) * 0.01) * ring_count
    f = phase - np.floor(phase)
    width_jitter = noise(2.8, lo=0.0, hi=0.01)
    f = np.clip(f * (0.8 + 0.4 * width_jitter), 0, 1)
    rings = np.clip((f - 0.72) / 0.2, 0, 1) ** 1.5 * (1.0 - np.clip((f - 0.93) / 0.07, 0, 1))
    grain = noise(1.2, sx=0.02, sy=1.0, lo=0.004, hi=0.5)      # long streaks along x
    fine = noise(0.6, sx=0.06, sy=1.0, lo=0.05, hi=0.5)
    pores = (noise(0.2, sx=0.12, sy=1.0, lo=0.15, hi=0.5) > 0.8).astype(np.float64)
    tone = 0.72 - 0.11 * rings + 0.3 * (grain - 0.5) + 0.12 * (fine - 0.5) - 0.08 * pores
    height = 0.2 * rings + 0.9 * grain + 0.35 * fine - 0.5 * pores
    rough = 0.62 + 0.15 * (grain - 0.5) + 0.1 * pores - 0.08 * rings
    save("wood", warm(tone, (1.0, 0.93, 0.85)), height, rough, 6.0)


def metal():
    brushed = noise(1.0, sx=0.02, sy=1.0, lo=0.01, hi=0.5)
    smudge = noise(2.4, lo=0.0, hi=0.03)
    scratches = np.zeros((SIZE, SIZE))
    for _ in range(900):
        x0, y0 = RNG.integers(0, SIZE, 2)
        ang = RNG.uniform(0, np.pi)
        length = RNG.integers(40, 600)
        t = np.arange(length)
        xs = ((x0 + np.cos(ang) * t) % SIZE).astype(np.int32)
        ys = ((y0 + np.sin(ang) * t) % SIZE).astype(np.int32)
        scratches[ys, xs] = np.maximum(scratches[ys, xs], RNG.uniform(0.3, 1.0))
    tone = 0.9 + 0.06 * (brushed - 0.5) - 0.12 * (smudge - 0.5) ** 2 * 4 + 0.05 * scratches
    height = 0.6 * brushed - 0.8 * scratches
    rough = 0.3 + 0.12 * (brushed - 0.5) + 0.25 * np.clip(smudge - 0.55, 0, 1) - 0.08 * scratches
    save("metal", tone, height, rough, 3.0)


def iron():
    base = noise(2.0, lo=0.002, hi=0.5)
    pits = (noise(0.4, lo=0.08, hi=0.5) > 0.8).astype(np.float64)
    blotch = noise(2.6, lo=0.0, hi=0.02)
    tone = 0.75 + 0.18 * (base - 0.5) - 0.2 * pits + 0.1 * (blotch - 0.5)
    rust = np.clip((blotch - 0.68) * 4, 0, 1)
    albedo = np.stack([tone + rust * 0.25, tone + rust * 0.05, tone - rust * 0.1], axis=-1)
    height = 0.8 * base - 1.2 * pits
    rough = 0.72 + 0.12 * (base - 0.5) + 0.1 * pits + 0.1 * rust
    save("iron", albedo, height, rough, 5.0)


def leather():
    cells = noise(1.0, lo=0.03, hi=0.09)
    pebble = np.abs(cells - 0.5) * 2
    creases = 1.0 - np.abs(noise(2.2, lo=0.002, hi=0.03) - 0.5) * 2
    creases = np.clip((creases - 0.85) * 6, 0, 1)
    wear = noise(2.6, lo=0.0, hi=0.015)
    tone = 0.78 + 0.12 * pebble - 0.18 * creases + 0.14 * (wear - 0.5)
    height = 0.9 * pebble - 0.8 * creases
    rough = 0.6 - 0.12 * (wear - 0.5) + 0.1 * creases
    save("leather", warm(tone, (1.0, 0.95, 0.9)), height, rough, 7.0)


def ceramic():
    craze = 1.0 - np.abs(noise(1.6, lo=0.004, hi=0.06) - 0.5) * 2
    craze = np.clip((craze - 0.94) * 14, 0, 1)
    speck = (noise(0.1, lo=0.2, hi=0.5) > 0.86).astype(np.float64)
    pool = noise(2.6, lo=0.0, hi=0.02)
    tone = 0.95 - 0.06 * craze - 0.15 * speck + 0.05 * (pool - 0.5)
    height = -0.6 * craze + 0.3 * pool
    rough = 0.18 + 0.1 * craze + 0.05 * (pool - 0.5)
    save("ceramic", tone, height, rough, 2.5)


def stone():
    big = noise(2.2, lo=0.001, hi=0.5)
    grains = noise(0.5, lo=0.05, hi=0.5)
    specks = (grains > 0.8).astype(np.float64)
    pits = (noise(0.6, lo=0.03, hi=0.3) < 0.18).astype(np.float64)
    tone = 0.7 + 0.25 * (big - 0.5) + 0.15 * specks - 0.25 * pits
    height = 1.0 * big + 0.3 * grains - 0.9 * pits
    rough = 0.82 + 0.1 * (grains - 0.5) + 0.06 * pits
    save("stone", warm(tone, (1.0, 0.98, 0.95)), height, rough, 6.0)


def parchment():
    fibres = noise(1.0, sx=0.1, sy=1.0, lo=0.01, hi=0.5)
    blotch = noise(2.6, lo=0.0, hi=0.02)
    tone = 0.9 + 0.08 * (fibres - 0.5) - 0.18 * np.clip(blotch - 0.6, 0, 1)
    height = 0.6 * fibres + 0.2 * blotch
    rough = 0.85 + 0.05 * (fibres - 0.5)
    save("parchment", warm(tone, (1.0, 0.96, 0.88)), height, rough, 2.0)


def cork():
    granules = noise(0.8, lo=0.02, hi=0.25)
    holes = (noise(0.5, lo=0.06, hi=0.4) < 0.2).astype(np.float64)
    tone = 0.75 + 0.3 * (granules - 0.5) - 0.35 * holes
    height = 0.9 * granules - 1.0 * holes
    rough = 0.9 + 0.05 * (granules - 0.5)
    save("cork", warm(tone, (1.0, 0.95, 0.88)), height, rough, 6.0)


if __name__ == "__main__":
    wanted = set(sys.argv[2:])
    for fn in (wood, metal, iron, leather, ceramic, stone, parchment, cork):
        if not wanted or fn.__name__ in wanted:
            fn()
