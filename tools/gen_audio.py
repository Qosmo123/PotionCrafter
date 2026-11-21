"""Synthesise every sound effect for PotionCrafter (no recorded samples).

Impacts are modal synthesis (a struck object rings at a few inharmonic
partials, each with its own decay: glass, ceramic, iron, wood, stone,
crystal). Liquids are built from Minnaert bubbles (short rising chirps), fire
and machines from spectrally shaped noise. Loops are made in the frequency
domain or with wrap-around placement, so they repeat seamlessly.

Usage:  python tools/gen_audio.py [name ...]      (default: everything)
Output: content/audio/<name>.wav  (32 kHz, mono, 16-bit)
Loops are the files whose name ends in "_loop"; AudioDirector loops them.
"""
import os
import sys
import wave

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "content", "audio")
RNG = np.random.default_rng(20261121)
SOUNDS = {}


# --- building blocks ---------------------------------------------------------

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def fade(x, t_in=0.002, t_out=0.01):
    x = x.copy()
    a = max(1, int(t_in * SR))
    b = max(1, int(t_out * SR))
    x[:a] *= np.linspace(0.0, 1.0, a)
    x[-b:] *= np.linspace(1.0, 0.0, b)
    return x


def band(n, lo, hi, slope=2.0, periodic=True):
    """Noise limited to lo..hi Hz with soft skirts. Built by shaping white
    noise in the frequency domain, so the result is periodic over n samples."""
    spec = np.fft.rfft(RNG.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f = np.maximum(f, 1e-3)
    shape = 1.0 / (1.0 + (lo / f) ** (2 * slope)) / (1.0 + (f / hi) ** (2 * slope))
    out = np.fft.irfft(spec * np.sqrt(shape), n)
    return out / (np.std(out) + 1e-12)


def slow(n, cycles_max=4, lo=0.0, hi=1.0):
    """Smooth periodic control curve in lo..hi (a handful of low harmonics)."""
    t = np.arange(n) / n
    x = np.zeros(n)
    for k in range(1, cycles_max + 1):
        x += RNG.standard_normal() / k * np.sin(2 * np.pi * (k * t + RNG.random()))
    x = (x - x.min()) / (x.max() - x.min() + 1e-12)
    return lo + (hi - lo) * x


def modal(f0, ratios, decays, amps, dur, detune=0.0, click=0.0, click_hz=(3000, 12000)):
    """Struck resonator: decaying sine partials plus an optional contact click."""
    t = t_axis(dur)
    x = np.zeros_like(t)
    for r, d, a in zip(ratios, decays, amps):
        f = f0 * r
        if f > SR * 0.45:
            continue
        ph = RNG.random() * 2 * np.pi
        x += a * np.exp(-t / d) * np.sin(2 * np.pi * f * t + ph)
        if detune > 0.0:  # a near-twin mode beats against it (real objects aren't symmetric)
            x += a * 0.6 * np.exp(-t / (d * 0.9)) * np.sin(2 * np.pi * f * (1.0 + detune) * t)
    if click > 0.0:
        n = len(t)
        c = band(n, click_hz[0], click_hz[1]) * np.exp(-t / 0.004)
        x += click * c
    return fade(x, 0.0005, min(0.02, dur * 0.2))


def bubble(f0, dur, rise=0.3, amp=1.0):
    """One Minnaert bubble: a sine that rises slightly in pitch as it decays."""
    t = t_axis(dur)
    f = f0 * (1.0 + rise * t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return amp * np.sin(ph) * np.exp(-t / (dur * 0.3)) * np.minimum(t / 0.002, 1.0)


def add_wrap(buf, start, sig):
    """Mix sig into buf at start, wrapping past the end (keeps loops seamless)."""
    n = len(buf)
    idx = (start + np.arange(len(sig))) % n
    np.add.at(buf, idx, sig)


def add_at(buf, start, sig):
    end = min(len(buf), start + len(sig))
    if end > start:
        buf[start:end] += sig[: end - start]


def bubbles(dur, rate_hz, f_lo, f_hi, d_lo, d_hi, wrap=True, rise=0.3):
    n = int(dur * SR)
    buf = np.zeros(n)
    for _ in range(int(dur * rate_hz)):
        f = np.exp(RNG.uniform(np.log(f_lo), np.log(f_hi)))
        d = RNG.uniform(d_lo, d_hi) * (f_lo / f) ** 0.35 * (f_hi / f_lo) ** 0.2
        b = bubble(f, max(d, 0.004), rise, RNG.uniform(0.3, 1.0))
        (add_wrap if wrap else add_at)(buf, RNG.integers(0, n), b)
    return buf


def clicks(dur, rate_hz, lo, hi, tau=0.002, wrap=True, amp_pow=2.0):
    """Random sharp grains (crackles, gravel, rattle)."""
    n = int(dur * SR)
    buf = np.zeros(n)
    m = int(0.03 * SR)
    for _ in range(int(dur * rate_hz)):
        g = band(m, lo, hi) * np.exp(-np.arange(m) / (tau * SR)) * RNG.random() ** amp_pow
        (add_wrap if wrap else add_at)(buf, RNG.integers(0, n), g)
    return buf


def reverb(x, decay=1.2, mix=0.35, tail=1.5, lo=200, hi=5000):
    """Baked room tail: convolve with exponentially decaying noise."""
    n_ir = int(tail * SR)
    ir = band(n_ir, lo, hi) * np.exp(-np.arange(n_ir) / (decay * SR / 6.9))
    ir[: int(0.012 * SR)] = 0.0
    n = len(x) + n_ir
    size = 1 << (n - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]
    dry = np.concatenate([x, np.zeros(n_ir)])
    return dry + mix * wet / (np.max(np.abs(wet)) + 1e-12) * np.max(np.abs(x))


def bell(freq, dur, bright=1.0):
    return modal(freq, [1.0, 2.0, 2.76, 4.07, 5.4], [dur * 0.35, dur * 0.22, dur * 0.16, dur * 0.1, dur * 0.07],
                 [1.0, 0.5 * bright, 0.35 * bright, 0.2 * bright, 0.1 * bright], dur, detune=0.003)


def sound(name, variants=1):
    def deco(fn):
        for v in range(variants):
            SOUNDS[name if variants == 1 else "%s_%d" % (name, v + 1)] = (fn, v)
        return fn
    return deco


# --- impacts (one per material resonance) -------------------------------------

@sound("impact_glass", 4)
def impact_glass(v):
    f0 = [1750, 2080, 2420, 2900][v]
    return modal(f0, [1.0, 2.32, 4.25, 6.63, 9.38], [0.22, 0.14, 0.09, 0.05, 0.03], [1.0, 0.55, 0.4, 0.25, 0.12], 0.55,
                 detune=0.004, click=0.5)


@sound("impact_ceramic", 2)
def impact_ceramic(v):
    f0 = [980, 1240][v]
    return modal(f0, [1.0, 1.92, 3.14, 4.7], [0.07, 0.045, 0.03, 0.02], [1.0, 0.6, 0.35, 0.2], 0.3, click=0.6, click_hz=(1500, 7000))


@sound("impact_iron", 3)
def impact_iron(v):
    f0 = [540, 640, 780][v]
    return modal(f0, [1.0, 2.76, 5.4, 8.93, 13.34], [0.5, 0.36, 0.24, 0.14, 0.08], [1.0, 0.7, 0.5, 0.35, 0.2], 0.9,
                 detune=0.002, click=0.5, click_hz=(2500, 12000))


@sound("impact_wood", 3)
def impact_wood(v):
    f0 = [170, 215, 265][v]
    x = modal(f0, [1.0, 2.45, 4.1, 6.3], [0.05, 0.03, 0.02, 0.012], [1.0, 0.5, 0.25, 0.12], 0.22, click=0.0)
    t = t_axis(0.22)
    return x + 0.5 * band(len(t), 250, 2200) * np.exp(-t / 0.012)


@sound("impact_stone", 3)
def impact_stone(v):
    t = t_axis(0.2)
    x = band(len(t), 1200 + 300 * v, 6500) * np.exp(-t / 0.014)
    x += 0.7 * modal(620 + 140 * v, [1.0, 1.7, 2.9], [0.03, 0.02, 0.012], [1.0, 0.6, 0.3], 0.2) * 3.0
    return fade(x, 0.0003, 0.02)


@sound("impact_crystal", 3)
def impact_crystal(v):
    f0 = [2640, 3140, 3960][v]
    return modal(f0, [1.0, 1.5, 2.67, 4.0, 5.33], [0.7, 0.5, 0.32, 0.2, 0.12], [1.0, 0.5, 0.45, 0.25, 0.12], 1.1,
                 detune=0.0025, click=0.25)


@sound("impact_soft", 2)
def impact_soft(v):
    t = t_axis(0.16)
    x = band(len(t), 60, 420 + 120 * v) * np.exp(-t / 0.03)
    x += 0.8 * np.sin(2 * np.pi * (95 + 20 * v) * t) * np.exp(-t / 0.035)
    return fade(x, 0.002, 0.03)


# --- glassware and bottling ---------------------------------------------------

@sound("glass_ting", 3)
def glass_ting(v):
    f0 = [3100, 3650, 4300][v]
    return 0.8 * modal(f0, [1.0, 2.3, 4.2], [0.12, 0.07, 0.04], [1.0, 0.4, 0.2], 0.3, detune=0.003, click=0.2)


@sound("glass_scrape_loop")
def glass_scrape_loop(_v):
    n = int(1.6 * SR)
    rough = np.abs(band(n, 30, 140)) ** 1.5
    return (band(n, 2000, 2500, 4) + 0.7 * band(n, 3500, 4100, 4) + 0.3 * band(n, 800, 7000)) * (0.25 + rough)


@sound("cork_pop")
def cork_pop(_v):
    t = t_axis(0.32)
    # Hollow neck resonance dropping in pitch as the cork leaves, plus the air burst.
    f = 520 * np.exp(-t / 0.5) + 380
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.045)
    x += 0.5 * np.sin(2 * np.pi * np.cumsum(f * 2.9) / SR) * np.exp(-t / 0.02)
    x += 0.6 * band(len(t), 500, 6000) * np.exp(-t / 0.012)
    return fade(x, 0.0004, 0.05)


@sound("cork_push")
def cork_push(_v):
    t = t_axis(0.26)
    squeak = np.sin(2 * np.pi * np.cumsum(900 + 500 * t / 0.16) / SR) * np.exp(-((t - 0.07) / 0.05) ** 2) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 85 * t)))
    thunk = np.sin(2 * np.pi * 180 * t) * np.exp(-np.maximum(t - 0.16, 0) / 0.03) * (t > 0.16)
    return fade(0.35 * squeak + thunk + 0.3 * band(len(t), 300, 2500) * np.exp(-np.abs(t - 0.165) / 0.01), 0.002, 0.03)


@sound("wax_pour")
def wax_pour(_v):
    t = t_axis(0.95)
    env = np.minimum(t / 0.05, 1.0) * np.exp(-np.maximum(t - 0.35, 0) / 0.22)
    x = band(len(t), 3500, 12000) * env * (0.6 + 0.4 * np.abs(band(len(t), 8, 40)))
    x += 1.2 * clicks(0.95, 55, 2500, 9000, 0.0012, wrap=False) * env
    x += 0.35 * bubbles(0.95, 14, 500, 1400, 0.03, 0.06, wrap=False) * env
    return fade(x, 0.01, 0.1)


@sound("wax_crack")
def wax_crack(_v):
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for start in [0.0, 0.035, 0.06, 0.11, 0.17]:
        m = int(0.05 * SR)
        add_at(x, int(start * SR), band(m, 900, 5000) * np.exp(-np.arange(m) / (0.006 * SR)) * RNG.uniform(0.5, 1.0))
    x += 0.5 * clicks(0.4, 60, 2000, 8000, 0.0015, wrap=False) * np.exp(-t / 0.12)
    return fade(x, 0.0003, 0.05)


@sound("stamp")
def stamp(_v):
    t = t_axis(0.3)
    x = np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.04) + 0.5 * band(len(t), 200, 1800) * np.exp(-t / 0.015)
    x += 0.25 * modal(1900, [1.0, 2.7, 5.2], [0.1, 0.06, 0.03], [1.0, 0.5, 0.3], 0.3)  # the brass signet rings faintly
    return fade(x, 0.0005, 0.04)


# --- liquids ------------------------------------------------------------------

@sound("pour_loop")
def pour_loop(_v):
    n = int(2.4 * SR)
    x = bubbles(2.4, 150, 700, 4200, 0.012, 0.03)
    x += 0.25 * band(n, 1200, 7000) * slow(n, 9, 0.5, 1.0) * np.std(x)
    return x


@sound("pour_thick_loop")
def pour_thick_loop(_v):
    n = int(2.4 * SR)
    x = bubbles(2.4, 9, 140, 520, 0.07, 0.16, rise=0.5)
    x += 0.12 * band(n, 150, 900) * slow(n, 5, 0.3, 1.0) * np.std(x)
    return x


@sound("boil_loop")
def boil_loop(_v):
    n = int(3.0 * SR)
    x = bubbles(3.0, 48, 220, 1300, 0.03, 0.07)
    x += 0.5 * bubbles(3.0, 90, 1200, 3600, 0.01, 0.02)
    x += 0.35 * band(n, 60, 260) * slow(n, 7, 0.4, 1.0) * np.std(x)
    return x


@sound("fizz_loop")
def fizz_loop(_v):
    n = int(2.2 * SR)
    x = bubbles(2.2, 420, 3200, 10000, 0.003, 0.008)
    x += 0.35 * band(n, 5000, 14000) * slow(n, 8, 0.6, 1.0) * np.std(x)
    return x


@sound("swirl_loop")
def swirl_loop(_v):
    n = int(2.0 * SR)
    x = band(n, 180, 1100) * slow(n, 4, 0.35, 1.0)
    return x + 0.35 * bubbles(2.0, 14, 400, 1500, 0.02, 0.05) * 4.0


@sound("drip", 3)
def drip(v):
    f0 = [900, 1250, 1700][v]
    n = int(0.22 * SR)
    x = np.zeros(n)
    add_at(x, 0, 0.4 * band(int(0.01 * SR), 2000, 9000) * np.exp(-np.arange(int(0.01 * SR)) / (0.002 * SR)))
    add_at(x, int(0.012 * SR), bubble(f0, 0.09, 0.45))
    add_at(x, int(0.05 * SR), 0.35 * bubble(f0 * 1.9, 0.05, 0.3))
    return fade(x, 0.0005, 0.03)


@sound("splash", 2)
def splash(v):
    dur = 0.6
    t = t_axis(dur)
    x = band(len(t), 500, 7000) * np.exp(-t / 0.06) * 0.7
    x += bubbles(dur, 70, 400 + 150 * v, 3000, 0.02, 0.05, wrap=False) * np.exp(-t / 0.18) * 2.5
    return fade(x, 0.001, 0.08)


# --- fire and arcana ----------------------------------------------------------

@sound("fire_loop")
def fire_loop(_v):
    n = int(3.0 * SR)
    x = band(n, 50, 500, 1.5) * slow(n, 11, 0.45, 1.0)
    x += 0.3 * band(n, 500, 3000) * slow(n, 13, 0.2, 1.0)
    x += 2.2 * clicks(3.0, 9, 1200, 9000, 0.0016)
    return x


@sound("candle_loop")
def candle_loop(_v):
    n = int(4.0 * SR)
    x = 0.5 * band(n, 120, 900, 1.5) * slow(n, 9, 0.2, 1.0)
    x += 2.0 * clicks(4.0, 2.2, 1500, 9000, 0.0012, amp_pow=3.0)
    return x


@sound("ignite")
def ignite(_v):
    t = t_axis(0.75)
    env = np.minimum(t / 0.06, 1.0) * np.exp(-np.maximum(t - 0.06, 0) / 0.2)
    lo = band(len(t), 60, 500, 1.5)
    hi = band(len(t), 400, 4500)
    mixc = np.exp(-t / 0.12)
    return fade((lo * (1.0 - 0.6 * mixc) + hi * mixc) * env, 0.004, 0.1)


@sound("explosion")
def explosion(_v):
    t = t_axis(1.3)
    f = 38 + 70 * np.exp(-t / 0.08)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.3) * 1.2
    x += band(len(t), 40, 1500, 1.5) * np.exp(-t / 0.16)
    x += 0.4 * clicks(1.3, 40, 400, 3000, 0.004, wrap=False) * np.exp(-t / 0.35)
    return fade(np.tanh(x * 1.4), 0.0005, 0.2)


@sound("glass_shatter")
def glass_shatter(_v):
    dur = 1.1
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = band(n, 2500, 14000) * np.exp(-t / 0.04)
    for _ in range(26):  # shards landing and ringing
        s = modal(RNG.uniform(2200, 7500), [1.0, 2.3, 4.1], [0.06, 0.04, 0.02], [1.0, 0.5, 0.25], 0.2, click=0.4)
        add_at(x, int(RNG.uniform(0.0, 0.7) ** 1.6 * SR), s * RNG.uniform(0.15, 0.6))
    return fade(x, 0.0003, 0.1)


PENTA = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5, 1568.0, 1760.0]


@sound("arcane_loop")
def arcane_loop(_v):
    dur = 4.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for i, f in enumerate([PENTA[2], PENTA[4], PENTA[6], PENTA[7], PENTA[9]]):
        f = round(f * dur) / dur  # whole cycles per loop
        am = 0.5 + 0.5 * np.sin(2 * np.pi * (i + 1) * t / dur + RNG.random() * 6.28)
        vib = 1.0 + 0.0  # pure tones; the beating comes from the paired partial
        x += am * (np.sin(2 * np.pi * f * t * vib) + 0.5 * np.sin(2 * np.pi * (round(f * 1.004 * dur) / dur) * t)) / (i + 1.5)
    x += 0.08 * band(n, 6000, 13000) * slow(n, 6, 0.0, 1.0) * np.std(x)
    return x


@sound("arcane_chime", 2)
def arcane_chime(v):
    notes = [[PENTA[5], PENTA[7], PENTA[9]], [PENTA[4], PENTA[6], PENTA[8]]][v]
    n = int(1.4 * SR)
    x = np.zeros(n)
    for i, f in enumerate(notes):
        add_at(x, int(i * 0.07 * SR), bell(f, 1.1, 0.8) * (1.0 - 0.15 * i))
    return fade(reverb(x, 1.0, 0.3, 0.6)[:n], 0.001, 0.2)


@sound("spell_cast")
def spell_cast(_v):
    t = t_axis(1.0)
    f = 300 * (2.0 ** (t / 0.4 * 1.6))
    f = np.minimum(f, 2400)
    sweep = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-((t - 0.25) / 0.16) ** 2) * 0.5
    x = sweep + 0.25 * band(len(t), 2000, 10000) * np.exp(-((t - 0.3) / 0.14) ** 2)
    add_at(x, int(0.38 * SR), bell(PENTA[7], 0.6) * 0.8)
    add_at(x, int(0.42 * SR), bell(PENTA[9], 0.55) * 0.5)
    return fade(x, 0.01, 0.1)


# --- mineral lab --------------------------------------------------------------

@sound("hammer_swing")
def hammer_swing(_v):
    t = t_axis(0.28)
    env = np.exp(-((t - 0.16) / 0.06) ** 2)
    return fade((band(len(t), 250, 1300) * (1 - t / 0.28) + band(len(t), 700, 3200) * (t / 0.28)) * env, 0.01, 0.03)


@sound("rock_hit", 3)
def rock_hit(v):
    n = int(0.3 * SR)
    x = np.zeros(n)
    add_at(x, 0, impact_stone(v) * 1.0)
    add_at(x, 0, 0.3 * modal(620 + 90 * v, [1.0, 2.76, 5.4], [0.12, 0.08, 0.05], [1.0, 0.6, 0.4], 0.3, click=0.3))
    add_at(x, 0, 0.6 * impact_soft(0))
    return fade(x, 0.0003, 0.03)


@sound("rock_crack", 2)
def rock_crack(v):
    dur = 0.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for start in [0.0, 0.02, 0.05 + 0.02 * v, 0.1]:
        add_at(x, int(start * SR), impact_stone(int(RNG.integers(0, 3))) * RNG.uniform(0.6, 1.0))
    x += 0.4 * band(n, 80, 600) * np.exp(-t / 0.06)
    x += 1.6 * clicks(dur, 70, 900, 6000, 0.003, wrap=False) * np.exp(-t / 0.2)  # crumbling rubble
    return fade(x, 0.0003, 0.1)


@sound("gem_reveal")
def gem_reveal(_v):
    n = int(1.9 * SR)
    x = np.zeros(n)
    for i, f in enumerate([PENTA[5], PENTA[7], PENTA[8], PENTA[9], PENTA[9] * 1.5]):
        s = modal(f * 2, [1.0, 1.5, 2.67, 4.0], [0.6, 0.4, 0.25, 0.15], [1.0, 0.45, 0.35, 0.2], 1.0, detune=0.003, click=0.1)
        add_at(x, int(i * 0.085 * SR), s * (0.7 + 0.08 * i))
    t = np.arange(n) / SR
    x += 0.12 * band(n, 6000, 14000) * np.exp(-((t - 0.5) / 0.35) ** 2) * np.max(np.abs(x))
    return fade(reverb(x, 1.2, 0.3, 0.5)[:n], 0.001, 0.3)


@sound("crusher_loop")
def crusher_loop(_v):
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    am = 0.5 + 0.5 * np.sin(2 * np.pi * 6 * t) ** 2
    x = band(n, 70, 520, 1.5) * am
    x += 1.8 * clicks(dur, 45, 500, 4500, 0.004)
    x += 0.25 * np.sign(np.sin(2 * np.pi * 12 * t)) * band(n, 800, 2400) * 0.3  # ratchet chatter
    return x


@sound("sifter_loop")
def sifter_loop(_v):
    dur = 1.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    am = 0.35 + 0.65 * np.abs(np.sin(2 * np.pi * 4 * t))
    return (2.0 * clicks(dur, 160, 1800, 9000, 0.0012) + 0.4 * band(n, 2500, 9000)) * am


@sound("wheel_loop")
def wheel_loop(_v):
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, 9):
        x += np.sin(2 * np.pi * 96 * k * t + RNG.random() * 6.28) / k ** 1.3
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 8 * t)
    return x * 0.5 + 0.35 * band(n, 300, 1800) * np.std(x)


@sound("grind_loop")
def grind_loop(_v):
    n = int(1.8 * SR)
    rough = np.abs(band(n, 40, 220)) ** 1.2
    return (band(n, 2800, 9000) + 0.6 * band(n, 5200, 6100, 4)) * (0.3 + rough)


@sound("chalk_loop")
def chalk_loop(_v):
    n = int(1.6 * SR)
    rough = np.abs(band(n, 25, 160)) ** 2.0
    return (band(n, 1600, 5200) + 0.5 * band(n, 2600, 3100, 4)) * (0.12 + rough)


@sound("sand_pour")
def sand_pour(_v):
    t = t_axis(0.8)
    env = np.minimum(t / 0.1, 1.0) * np.exp(-np.maximum(t - 0.3, 0) / 0.2)
    return fade((band(len(t), 2500, 12000) + 1.2 * clicks(0.8, 200, 1500, 7000, 0.001, wrap=False)) * env, 0.01, 0.1)


# --- mechanisms ---------------------------------------------------------------

@sound("click", 2)
def click(v):
    t = t_axis(0.06)
    x = band(len(t), 1500, 9000) * np.exp(-t / 0.0025)
    x += 0.7 * np.sin(2 * np.pi * (2600 + 700 * v) * t) * np.exp(-t / 0.008)
    return fade(x, 0.0002, 0.01)


@sound("switch")
def switch(_v):
    n = int(0.16 * SR)
    x = np.zeros(n)
    add_at(x, 0, click(0) * 0.7)
    add_at(x, int(0.045 * SR), click(1))
    t = np.arange(n) / SR
    x += 0.6 * np.sin(2 * np.pi * 210 * t) * np.exp(-np.maximum(t - 0.045, 0) / 0.02) * (t > 0.045)
    return fade(x, 0.0002, 0.02)


@sound("ratchet")
def ratchet(_v):
    t = t_axis(0.09)
    x = band(len(t), 900, 6000) * np.exp(-t / 0.004) + 0.6 * np.sin(2 * np.pi * 760 * t) * np.exp(-t / 0.012)
    return fade(x, 0.0002, 0.015)


@sound("hotplate_loop")
def hotplate_loop(_v):
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 100 * t) + 0.45 * np.sin(2 * np.pi * 200 * t + 0.4) + 0.2 * np.sin(2 * np.pi * 300 * t + 1.1)
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * 1.5 * t)
    return x + 0.12 * band(n, 2000, 9000) * slow(n, 6, 0.4, 1.0)


# --- interface ----------------------------------------------------------------

@sound("ui_hover")
def ui_hover(_v):
    t = t_axis(0.05)
    return fade(np.sin(2 * np.pi * 1900 * t) * np.exp(-t / 0.012), 0.002, 0.01) * 0.5


@sound("ui_click")
def ui_click(_v):
    t = t_axis(0.11)
    x = np.sin(2 * np.pi * 880 * t) * np.exp(-t / 0.025) + 0.5 * np.sin(2 * np.pi * 1320 * t) * np.exp(-t / 0.018)
    return fade(x + 0.3 * band(len(t), 2000, 8000) * np.exp(-t / 0.003), 0.0005, 0.02)


def rustle(dur, lo, hi, grains):
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for _ in range(grains):
        c = RNG.uniform(0.05, dur - 0.08)
        env += RNG.uniform(0.4, 1.0) * np.exp(-((t - c) / RNG.uniform(0.012, 0.04)) ** 2)
    return band(n, lo, hi) * env


@sound("ui_open")
def ui_open(_v):
    x = rustle(0.36, 1800, 9000, 5)
    add_at(x, int(0.05 * SR), 0.25 * bell(PENTA[6], 0.3) * np.max(np.abs(x)))
    return fade(x, 0.005, 0.05)


@sound("ui_close")
def ui_close(_v):
    x = rustle(0.3, 1200, 7000, 4)
    t = t_axis(0.3)
    x += 0.5 * np.sin(2 * np.pi * 150 * t) * np.exp(-np.maximum(t - 0.2, 0) / 0.03) * (t > 0.2) * np.max(np.abs(x))
    return fade(x, 0.005, 0.04)


@sound("page_turn")
def page_turn(_v):
    t = t_axis(0.5)
    env = np.exp(-((t - 0.2) / 0.11) ** 2)
    x = (band(len(t), 900, 4000) * (1 - t / 0.5) + band(len(t), 2500, 11000) * (t / 0.5)) * env
    x += 0.8 * rustle(0.5, 2500, 10000, 3)
    return fade(x, 0.01, 0.06)


@sound("ui_toast")
def ui_toast(_v):
    n = int(0.55 * SR)
    x = np.zeros(n)
    add_at(x, 0, bell(PENTA[7], 0.4, 0.6))
    add_at(x, int(0.09 * SR), bell(PENTA[9], 0.45, 0.6) * 0.8)
    return fade(x, 0.001, 0.08)


@sound("ui_error")
def ui_error(_v):
    n = int(0.4 * SR)
    x = np.zeros(n)
    add_at(x, 0, modal(330, [1.0, 2.0, 3.0], [0.1, 0.06, 0.04], [1.0, 0.4, 0.2], 0.2))
    add_at(x, int(0.11 * SR), modal(262, [1.0, 2.0, 3.0], [0.14, 0.08, 0.05], [1.0, 0.4, 0.2], 0.28))
    return fade(x, 0.002, 0.05)


@sound("discover")
def discover(_v):
    n = int(2.2 * SR)
    x = np.zeros(n)
    for i, k in enumerate([0, 2, 4, 5, 7, 9]):
        add_at(x, int(i * 0.1 * SR), bell(PENTA[k], 1.3, 0.9) * (0.75 + 0.05 * i))
    add_at(x, int(0.62 * SR), 0.6 * bell(PENTA[9] * 2, 1.2, 0.5))
    t = np.arange(n) / SR
    x += 0.06 * band(n, 5000, 13000) * np.exp(-((t - 0.8) / 0.4) ** 2) * np.max(np.abs(x))
    return fade(reverb(x, 1.4, 0.35, 0.6)[:n], 0.001, 0.35)


@sound("coin")
def coin(_v):
    n = int(0.5 * SR)
    x = np.zeros(n)
    add_at(x, 0, modal(2500, [1.0, 2.41, 3.9, 5.6], [0.2, 0.14, 0.08, 0.05], [1.0, 0.6, 0.35, 0.2], 0.4, detune=0.004, click=0.3))
    add_at(x, int(0.07 * SR), 0.8 * modal(3350, [1.0, 2.41, 3.9], [0.25, 0.16, 0.09], [1.0, 0.5, 0.3], 0.42, detune=0.004))
    return fade(x, 0.0005, 0.06)


@sound("whoosh")
def whoosh(_v):
    t = t_axis(0.6)
    env = np.exp(-((t - 0.28) / 0.14) ** 2)
    return fade((band(len(t), 120, 700, 1.5) + 0.5 * band(len(t), 600, 2600) * (t / 0.6)) * env, 0.02, 0.08)


@sound("grab")
def grab(_v):
    t = t_axis(0.07)
    return fade(band(len(t), 500, 3500) * np.exp(-t / 0.008) + 0.5 * np.sin(2 * np.pi * 420 * t) * np.exp(-t / 0.015), 0.0005, 0.015)


# --- ambience -----------------------------------------------------------------

@sound("room_loop")
def room_loop(_v):
    n = int(9.0 * SR)
    x = band(n, 35, 160, 1.5) * slow(n, 5, 0.6, 1.0)
    x += 0.22 * band(n, 250, 1400, 1.2) * slow(n, 7, 0.3, 1.0)
    x += 0.05 * band(n, 2500, 8000, 1.2) * slow(n, 9, 0.2, 1.0)
    return x


@sound("wind_gust")
def wind_gust(_v):
    t = t_axis(3.6)
    env = np.exp(-((t - 1.5) / 0.9) ** 2)
    x = band(len(t), 150, 800, 1.5) * (0.6 + 0.4 * slow(len(t), 6))
    x += 0.2 * band(len(t), 900, 1200, 5) * slow(len(t), 5)  # a thin whistle through the casement
    return fade(x * env, 0.2, 0.4)


@sound("distant_drip")
def distant_drip(_v):
    x = np.concatenate([drip(0), np.zeros(int(0.3 * SR))])
    return fade(reverb(x, 1.6, 0.9, 1.3, 300, 4000), 0.001, 0.4)


@sound("wood_creak", 2)
def wood_creak(v):
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    rate = (26 + 14 * v) + 40 * (t / dur) ** 2 + 6 * np.sin(2 * np.pi * 3 * t)
    pulses = (np.diff(np.floor(np.cumsum(rate) / SR), prepend=0) > 0).astype(float)
    spec = np.fft.rfft(pulses)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    res = np.zeros_like(f)
    for fc, bw, g in [(310 + 60 * v, 60, 1.0), (760, 120, 0.6), (1450, 250, 0.3)]:
        res += g * np.exp(-((f - fc) / bw) ** 2)
    x = np.fft.irfft(spec * res, n) * np.exp(-((t - 0.5) / 0.3) ** 2)
    return fade(reverb(x, 0.8, 0.3, 0.5)[:n], 0.02, 0.15)


# --- output -------------------------------------------------------------------

def save(name, x):
    loop = name.endswith("_loop")
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    x = norm(x, 0.5 if loop else 0.9)
    if not loop:
        x = fade(x, 0.0002, 0.004)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return len(pcm) / SR


def main():
    os.makedirs(OUT, exist_ok=True)
    wanted = sys.argv[1:]
    total = 0.0
    for name, (fn, v) in SOUNDS.items():
        if wanted and not any(name.startswith(w) for w in wanted):
            continue
        total += save(name, fn(v))
    print("wrote %d sounds, %.1f s, to %s" % (len(SOUNDS) if not wanted else len(wanted), total, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
