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
    # Broad, soft latewood gradients (no hard "contour line" edges).
    rings = np.clip((f - 0.45) / 0.45, 0, 1) ** 2.0 * (1.0 - np.clip((f - 0.9) / 0.1, 0, 1))
    grain = noise(1.2, sx=0.02, sy=1.0, lo=0.004, hi=0.5)      # long streaks along x
    fine = noise(0.6, sx=0.06, sy=1.0, lo=0.05, hi=0.5)
    pores = (noise(0.2, sx=0.12, sy=1.0, lo=0.15, hi=0.5) > 0.8).astype(np.float64)
    # Broad colour streaks along the board read as wood more than ring lines do.
    streaks = noise(2.0, sx=40.0, sy=1.0, lo=0.002, hi=0.05)
    tone = 0.72 - 0.035 * rings + 0.3 * (grain - 0.5) + 0.12 * (fine - 0.5) + 0.16 * (streaks - 0.5) - 0.08 * pores
    height = 0.03 * rings + 0.9 * grain + 0.35 * fine - 0.5 * pores
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


def rock_granular():
    """Igneous rock (granite, gabbro): interlocking mineral grains of three
    tones (dark mafics, pale feldspar, glassy quartz) with fine pits."""
    a = noise(0.6, lo=0.02, hi=0.12)
    b = noise(0.6, lo=0.02, hi=0.12)
    dark = (a > 0.62).astype(np.float64)
    pale = ((b > 0.6) & (a < 0.5)).astype(np.float64)
    fine = noise(0.4, lo=0.1, hi=0.5)
    pits = (noise(0.5, lo=0.08, hi=0.4) < 0.15).astype(np.float64)
    tone = 0.72 - 0.38 * dark + 0.22 * pale + 0.1 * (fine - 0.5) - 0.2 * pits
    albedo = np.stack([tone + pale * 0.04, tone + pale * 0.02, tone - pale * 0.02], axis=-1)
    height = 0.5 * a + 0.4 * fine - 0.9 * pits + 0.3 * pale
    rough = 0.8 - 0.25 * pale * (b > 0.75) + 0.08 * pits
    save("rock_granular", albedo, height, rough, 7.0)


def rock_layered():
    """Sedimentary rock (limestone, sandstone, shale): wavy bedding layers
    of varying tone and thickness, with sand grains and small voids."""
    yy = np.mgrid[0:SIZE, 0:SIZE][0] / SIZE
    bend = noise(2.6, lo=0.0, hi=0.008)
    layers = noise(1.6, sx=40.0, sy=1.0, lo=0.003, hi=0.08)  # bands: varies along y only
    layers = warp(layers, bend, bend, 0.04)
    grains = noise(0.3, lo=0.15, hi=0.5)
    voids = (noise(0.5, lo=0.05, hi=0.3) < 0.12).astype(np.float64)
    tone = 0.66 + 0.3 * (layers - 0.5) + 0.1 * (grains - 0.5) - 0.25 * voids
    height = 0.8 * layers + 0.35 * grains - 0.9 * voids
    rough = 0.86 + 0.06 * (grains - 0.5)
    save("rock_layered", warm(tone, (1.0, 0.97, 0.92)), height, rough, 6.0)


def crystal_etched():
    """Raw crystal faces: frosty micro-etch, triangular etch pits, parallel
    growth striations and a few fine fractures. Near-white albedo."""
    frost = noise(0.2, lo=0.2, hi=0.5)
    stria = noise(1.0, sx=40.0, sy=1.0, lo=0.01, hi=0.2)
    pits = np.zeros((SIZE, SIZE))
    tri = np.zeros((SIZE, SIZE))
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    cell = SIZE // 48
    jitter = RNG.integers(0, cell, (48, 48, 2))
    on = RNG.random((48, 48)) < 0.35
    size = RNG.integers(cell // 6, cell // 3, (48, 48))
    lx = (xx % cell)
    ly = (yy % cell)
    cx = jitter[yy // cell % 48, xx // cell % 48, 0]
    cy = jitter[yy // cell % 48, xx // cell % 48, 1]
    s = size[yy // cell % 48, xx // cell % 48]
    dx = (lx - cx) / np.maximum(s, 1)
    dy = (ly - cy) / np.maximum(s, 1)
    # Triangle (trigon) membership: three half-planes.
    inside = (dy < 0.5) & (dy > -1.0 + np.abs(dx) * 1.7)
    tri = inside.astype(np.float64) * on[yy // cell % 48, xx // cell % 48]
    depth = np.clip(1.0 - np.sqrt(dx * dx + (dy + 0.25) ** 2), 0, 1)
    pits = tri * depth
    cracks = 1.0 - np.abs(noise(1.8, lo=0.003, hi=0.05) - 0.5) * 2
    cracks = np.clip((cracks - 0.965) * 30, 0, 1)
    tone = 0.92 + 0.05 * (frost - 0.5) - 0.12 * tri - 0.15 * cracks
    height = 0.25 * frost + 0.5 * stria - 1.2 * pits - 0.6 * cracks
    rough = 0.55 + 0.25 * frost - 0.2 * tri + 0.1 * cracks
    save("crystal_etched", tone, height, rough, 5.0)


def ore_metallic():
    """Metallic ore (pyrite, galena): striated crystal faces with tarnish."""
    stria = noise(1.2, sx=40.0, sy=1.0, lo=0.01, hi=0.3)
    stria2 = noise(1.2, sx=1.0, sy=40.0, lo=0.01, hi=0.3)
    tarnish = noise(2.6, lo=0.0, hi=0.02)
    pits = (noise(0.5, lo=0.08, hi=0.4) < 0.12).astype(np.float64)
    tone = 0.88 + 0.06 * (stria - 0.5) - 0.3 * np.clip(tarnish - 0.6, 0, 1) - 0.2 * pits
    tarn = np.clip((tarnish - 0.6) * 3, 0, 1)
    albedo = np.stack([tone + tarn * 0.05, tone - tarn * 0.02, tone + tarn * 0.08], axis=-1)
    height = 0.7 * stria + 0.3 * stria2 - 1.0 * pits
    rough = 0.3 + 0.2 * tarn + 0.1 * pits
    save("ore_metallic", albedo, height, rough, 4.0)


def burlap():
    """Coarse woven jute sacking for sand bags: over-under weave with fuzz."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    threads = 64
    u = xx / SIZE * threads
    v = yy / SIZE * threads
    wobble = noise(2.0, lo=0.002, hi=0.03)
    u = u + (wobble - 0.5) * 2.0
    v = v + (noise(2.0, lo=0.002, hi=0.03) - 0.5) * 2.0
    warp_t = np.abs(np.sin(u * np.pi))
    weft_t = np.abs(np.sin(v * np.pi))
    over = ((np.floor(u) + np.floor(v)) % 2).astype(np.float64)
    h = np.where(over > 0.5, warp_t, weft_t)
    fuzz = noise(0.3, lo=0.2, hi=0.5)
    tone = 0.62 + 0.3 * h + 0.12 * (fuzz - 0.5)
    height = h + 0.2 * fuzz
    rough = 0.95 - 0.05 * h
    save("burlap", warm(tone, (1.0, 0.9, 0.72)), height, rough, 6.0)


if __name__ == "__main__":
    wanted = set(sys.argv[2:])
    for fn in (wood, metal, iron, leather, ceramic, stone, parchment, cork,
               rock_granular, rock_layered, crystal_etched, ore_metallic, burlap):
        if not wanted or fn.__name__ in wanted:
            fn()
