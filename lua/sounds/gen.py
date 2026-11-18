"""Synthesizes the editor's sound cues: the sci-fi terminal set (sounds/) and the serious
presets Ledger, Muted keys and Advisory (sounds/<preset>/, see SERIOUS below).

Usage:  python3 -I gen.py <outdir> [--candidates <dir>]

Stdlib only, dry, no reverb. Every sound is a gated beep, a low pulse or a
burst of filtered noise: tones switch on and off almost instantly (no decay,
no ring), the register is low, intervals are small, and there is no rising
arpeggio or pitch-bend "boop" (those read as a game, not a computer).

CANDIDATES holds three options (A, B, C) per event, the same 24 that are in the
browser mockup ("Workstation Cues"). PICKS chooses the one that is written to
<outdir>. To change an event, edit its letter in PICKS and run this again.
`--candidates <dir>` also writes every option to <dir>/<event>_<letter>.wav,
so alternates can be auditioned with `afplay` without touching PICKS.
"""
import math
import os
import struct
import sys
import json
import wave

SR = 44100
TAU = 2 * math.pi

# The active cue per event.
PICKS = {
    "save": "A",  # tick blip
    "commit": "B",  # pulse triple
    "pull": "C",  # carrier lock
    "push": "C",  # sent
    "claude_done": "C",  # descending pair
    "claude_input": "C",  # query pair
    "ok": "C",  # low blip
    "fail": "B",  # negative ack
    "checkout": "B",  # bus swap
    "claude_start": "C",  # engage
    "breakpoint": "B",  # halt tone
}

# Peak level of each event in dBFS (the balance heard in the mockup).
LEVELS = {
    "save": -25.0,
    "commit": -14.0,
    "pull": -15.3,
    "push": -15.3,
    "claude_done": -14.6,
    "claude_input": -14.6,
    "ok": -18.8,
    "fail": -14.0,
    "checkout": -22.0,  # a quiet tick: branch switches are frequent
    "claude_start": -24.0,  # quieter still: it plays on every prompt
    "breakpoint": -14.6,  # like claude_input: it needs you
}


def ms(x):
    return int(SR * x / 1000)


class Rng:
    """Deterministic white noise in [-1, 1] (same cues on every run)."""

    def __init__(self, seed):
        self.s = seed

    def __call__(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s / 0x3FFFFFFF - 1.0


def finish(x, fade_ms=1):
    """Unit peak + a tiny fade so no voice ends on a click."""
    n = min(len(x), ms(fade_ms))
    for i in range(n):
        x[len(x) - 1 - i] *= i / n
    peak = max(abs(v) for v in x) or 1.0
    return [v / peak for v in x]


def _envelope(i, n, env, atk, rel):
    a = max(1, ms(atk))
    if env == "gate":  # on/off: short attack, hold, exponential release
        r = max(1, ms(rel))
        if i < a:
            return i / a
        if i >= n - r:
            return 1e-4 ** ((i - (n - r)) / r)
        return 1.0
    # "exp": linear attack, then exponential decay to silence
    if i < a:
        return i / a
    return 1e-4 ** ((i - a) / max(1, n - a))


# ---- voices (each returns a unit-peak list of samples) ----------------------


def osc(f, dur, wave="sine", f2=None, lp=None, lp2=None, atk=3, rel=None, env="gate"):
    """An oscillator, optionally gliding f -> f2 and low-passed lp -> lp2 (2 poles)."""
    n = ms(dur)
    rel = min(20, dur / 3) if rel is None else rel
    out, ph, s1, s2 = [], 0.0, 0.0, 0.0
    for i in range(n):
        fr = f * (f2 / f) ** (i / n) if f2 else f
        ph = (ph + fr / SR) % 1.0
        if wave == "sine":
            w = math.sin(TAU * ph)
        elif wave == "triangle":
            w = 4 * abs(ph - 0.5) - 1
        elif wave == "square":
            w = 1.0 if ph < 0.5 else -1.0
        else:  # saw
            w = 2 * ph - 1
        if lp:
            c = lp * (lp2 / lp) ** (i / n) if lp2 else lp
            a = 1 - math.exp(-TAU * c / SR)
            s1 += a * (w - s1)
            s2 += a * (s1 - s2)
            w = s2
        out.append(w * _envelope(i, n, env, atk, rel))
    return finish(out)


def beep(f, dur, wave="square", lp=2400, f2=None):
    """A gated beep: the computer-terminal voice."""
    return osc(f, dur, wave, f2=f2, lp=lp, atk=3, rel=min(20, dur / 3), env="gate")


def nz(dur, kind="bandpass", f=1000, f2=None, q=1.0, atk=1.0):
    """Filtered noise (state-variable filter), centre/cutoff gliding f -> f2."""
    r = Rng(21)
    n = ms(dur)
    qq = 1 / q
    low = band = 0.0
    out = []
    for i in range(n):
        fc = f * (f2 / f) ** (i / n) if f2 else f
        k = 2 * math.sin(math.pi * min(fc, SR / 6) / SR)
        high = r() - low - qq * band
        low += k * band
        band += k * high
        y = {"bandpass": band, "highpass": high, "lowpass": low}[kind]
        out.append(y * _envelope(i, n, "exp", atk, 0))
    return finish(out)


def chatter(freqs, step, wave, gain, fade, lp):
    """Telemetry: a run of very short beeps from a fixed list of frequencies."""
    return [
        (i * step, beep(f, step * 0.8, wave, lp), gain * (1 - fade * i / len(freqs)))
        for i, f in enumerate(freqs)
    ]


# ---- candidates: event -> {letter: (name, [(offset ms, voice, gain)])} -------

CANDIDATES = {
    "save": {
        "A": ("Tick blip", [(0, beep(1800, 12, lp=4000), 0.8)]),
        "B": ("Data tick", [(0, beep(2400, 14, lp=4500), 0.7), (28, beep(1800, 14, lp=4500), 0.6)]),
        "C": (
            "Static tick",
            [(0, nz(14, "highpass", f=5000, q=0.7), 0.8), (0, beep(1200, 10, "sine"), 0.5)],
        ),
    },
    "commit": {
        "A": (
            "Ack pair",
            [(0, beep(196, 90, "triangle", 1200), 0.9), (130, beep(294, 140, "triangle", 1200), 0.9)],
        ),
        "B": (
            "Pulse triple",
            [(x, beep(110, 70, "square", 420), 0.9 - 0.15 * i) for i, x in enumerate((0, 110, 220))],
        ),
        "C": (
            "Seal sweep",
            [(0, beep(1300, 12, "sine"), 0.5), (20, osc(320, 200, "sine", f2=90, atk=4, env="exp"), 0.9)],
        ),
    },
    "pull": {
        "A": (
            "Downlink",
            chatter([1500, 1100, 1300, 900, 1100, 800, 950, 700], 35, "triangle", 0.7, 0.5, 3000),
        ),
        "B": (
            "Sweep in",
            [
                (0, osc(2200, 320, "saw", f2=260, lp=1800, lp2=300, atk=20, env="exp"), 0.5),
                (330, beep(600, 50, "triangle", 1500), 0.6),
            ],
        ),
        "C": (
            "Carrier lock",
            [
                (0, osc(640, 220, lp=2400, atk=10, rel=80), 0.5),
                (0, osc(960, 220, lp=2400, atk=10, rel=80), 0.5),
                (20, nz(140, f=2200, f2=900, q=1.0), 0.06),
            ],
        ),
    },
    "push": {
        "A": ("Uplink", chatter([900, 1500, 1100, 1700, 1300, 1900, 1500], 30, "square", 0.5, 0, 3200)),
        "B": (
            "Burst",
            [(0, nz(120, "highpass", f=800, f2=6000, q=0.7, atk=4), 0.8), (20, beep(1500, 60, lp=2800), 0.35)],
        ),
        "C": ("Sent", [(0, beep(1200, 60, lp=2600), 0.7), (80, beep(1800, 35, lp=3200), 0.6)]),
    },
    "claude_done": {
        "A": (
            "Terminal bell",
            [
                (0, osc(1000, 240, "triangle", lp=3200, atk=2, env="exp"), 0.8),
                (0, osc(2000, 140, atk=2, env="exp"), 0.2),
            ],
        ),
        "B": (
            "Ready tone",
            [
                (0, osc(330, 400, "triangle", lp=2000, atk=10, rel=150), 0.5),
                (0, osc(495, 400, "triangle", lp=2000, atk=10, rel=150), 0.5),
            ],
        ),
        "C": (
            "Descending pair",
            [(0, beep(523, 90, "triangle", 2000), 0.8), (130, beep(392, 160, "triangle", 2000), 0.8)],
        ),
    },
    "claude_input": {
        "A": ("Low pulse", [(x, beep(150, 110, "square", 520), 0.7) for x in (0, 180)]),
        "B": (
            "Triple pulse",
            [(x, beep(130, 80, "square", 480), 0.75 - 0.15 * i) for i, x in enumerate((0, 120, 240))],
        ),
        "C": (
            "Query pair",
            [(x, beep(400, 80, "square", 1200), 0.6) for x in (0, 200)]
            + [(x + 100, beep(480, 80, "square", 1200), 0.6) for x in (0, 200)],
        ),
    },
    "ok": {
        "A": ("Blip", [(0, beep(1400, 40, lp=3000), 0.8)]),
        "B": ("Double blip", [(0, beep(1000, 30, lp=2800), 0.7), (50, beep(1500, 30, lp=2800), 0.7)]),
        "C": ("Low blip", [(0, beep(440, 70, "triangle", 1600), 0.9)]),
    },
    "fail": {
        "A": (
            "Error buzz",
            [(0, beep(90, 240, "square", 500), 0.7), (0, beep(95, 240, "square", 500), 0.5)],
        ),
        "B": (
            "Negative ack",
            [(0, beep(330, 110, "square", 900), 0.8), (150, beep(220, 200, "square", 700), 0.8)],
        ),
        "C": ("Power drop", [(0, osc(150, 300, "saw", f2=60, lp=600, lp2=200, atk=5, rel=100), 0.7)]),
    },
    "checkout": {
        "A": (
            "Switch tick",
            [(0, beep(1500, 14, lp=3500), 0.8), (30, beep(1000, 14, lp=3500), 0.7)],
        ),
        "B": (
            "Bus swap",
            [
                (0, nz(70, f=3000, f2=800, q=1.5, atk=2), 0.5),
                (50, beep(700, 40, "triangle", 1500), 0.6),
            ],
        ),
        "C": (
            "Data jitter",
            [(x, beep(f, 12, lp=5000), 0.8 - 0.15 * i) for i, (x, f) in enumerate(((0, 3000), (22, 2200), (44, 2600)))],
        ),
    },
    "claude_start": {
        "A": (
            "Intake tick",
            [(0, nz(12, "highpass", f=5000, q=0.7), 0.6), (0, beep(900, 20, lp=2600), 0.6)],
        ),
        "B": ("Double tick", [(0, beep(1000, 15, lp=3000), 0.7), (40, beep(1000, 15, lp=3000), 0.5)]),
        "C": (
            "Engage",
            [(0, beep(260, 50, "triangle", 1200), 0.9), (0, nz(10, "highpass", f=4500, q=0.7), 0.5)],
        ),
    },
    "breakpoint": {
        "A": (
            "Query pair",
            [(x, beep(400, 80, "square", 1200), 0.6) for x in (0, 200)]
            + [(x + 100, beep(480, 80, "square", 1200), 0.6) for x in (0, 200)],
        ),
        "B": ("Halt tone", [(0, beep(300, 150, "square", 900), 0.8)]),
        "C": (
            "Tick, tick, pulse",
            [(x, beep(1200, 14, lp=3500), 0.7) for x in (0, 30, 60)]
            + [(130, beep(200, 90, "square", 600), 0.8)],
        ),
    },
}


# ---- chatter: the experimental "talking" cues (lua/sounds/chatter.lua) -------
# They play very often (a key, a line of output), so each is a few ms and very
# quiet, and every cue is rendered in several pitch variants (VARIANTS):
# chatter.lua plays one at random, so a stream doesn't sound like one sample on
# repeat. The candidates are the same 30 as the browser mockup "Chatter Cues"
# (A-C, then D-F: serial bits, chirps, dual tones, AM wobble, static pops).

VARIANTS = (0.92, 0.97, 1.03, 1.08)  # pitch factors -> sounds/chatter/<cue>_1..4.wav

CHATTER_PICKS = {
    "claude_line": "B",  # low pulse
    "claude_para": "B",  # settle tone (kept, but unused while claude.mode = "chunk")
    "term_key": "B",  # soft blip (was A, "tick": too sharp at the volume it plays at in the editor)
    "term_enter": "B",  # low confirm
    "term_out": "F",  # AM tick
}

# dBFS peaks. The mockup scale put these at -31..-23; they are nudged louder
# (about +4 dB) because they play at a fraction of the volume of the main cues.
CHATTER_LEVELS = {
    "claude_line": -27.0,
    "claude_para": -20.0,
    "term_key": -27.0,
    "term_enter": -21.0,
    "term_out": -29.0,
}


def tick(f, dur, wave="square", lp=2400):
    """A gated beep: 2 ms attack, short release."""
    return osc(f, dur, wave, lp=lp, atk=2, rel=min(12, dur / 3), env="gate")


def chirp(f0, f1, dur):
    """A very fast pitch glide (an interface chirp, not a slow boop)."""
    return osc(f0, dur, "triangle", f2=f1, lp=4000, atk=2, rel=min(8, dur / 3), env="gate")


def am(f, dur, rate):
    """A tone whose loudness wobbles at `rate` Hz (robotic, ring-modulated)."""
    n = ms(dur)
    r = max(1, ms(min(8, dur / 3)))
    a = max(1, ms(2))
    out, ph = [], 0.0
    for i in range(n):
        ph = (ph + f / SR) % 1.0
        lfo = 0.5 + 0.5 * math.sin(TAU * rate * i / SR)
        env = i / a if i < a else (1e-4 ** ((i - (n - r)) / r) if i >= n - r else 1.0)
        out.append(math.sin(TAU * ph) * lfo * env)
    return finish(out)


def dual(f1, f2, dur, gain):
    """Two sine pitches at once."""
    return [(0, tick(f1, dur, "sine", 6000), gain * 0.6), (0, tick(f2, dur, "sine", 6000), gain * 0.6)]


CHATTER = {
    "claude_line": {
        "A": ("Soft tick", lambda k: [(0, tick(1400 * k, 14, "triangle", 2500), 0.8)]),
        "B": ("Low pulse", lambda k: [(0, tick(180 * k, 20, "square", 500), 0.8)]),
        "C": ("Scan tick", lambda k: [(0, nz(7, f=2500 * k, q=3.0, atk=1), 0.8), (0, tick(600 * k, 10, "sine"), 0.5)]),
        "D": ("Serial bits", lambda k: [(x, tick(1800 * k, 4, lp=4000), 0.7) for x in (0, 7, 14)]),
        "E": ("Chirp", lambda k: [(0, chirp(1500 * k, 2100 * k, 12), 0.7)]),
        "F": ("AM blip", lambda k: [(0, am(900 * k, 16, 90), 0.9)]),
    },
    "claude_para": {
        "A": (
            "Double pulse",
            lambda k: [(0, tick(150 * k, 30, "square", 520), 0.8), (50, tick(150 * k, 30, "square", 520), 0.8)],
        ),
        "B": ("Settle tone", lambda k: [(0, tick(330 * k, 60, "triangle", 1500), 0.9)]),
        "C": ("Sweep down", lambda k: [(0, nz(80, "lowpass", f=3000 * k, f2=600 * k, q=0.8, atk=4), 0.8)]),
        "D": (
            "Data burst",
            lambda k: [(i * 11, tick(f * k, 8, lp=4000), 0.7) for i, f in enumerate((1200, 1800, 1500, 2100, 1650, 1350))],
        ),
        "E": ("Seal chirp", lambda k: [(0, chirp(900 * k, 500 * k, 50), 0.8)]),
        "F": ("Dual tone", lambda k: dual(600 * k, 900 * k, 50, 0.9)),
    },
    "term_key": {
        "A": ("Tick", lambda k: [(0, tick(2200 * k, 8, "square", 4500), 0.8)]),
        "B": ("Soft blip", lambda k: [(0, tick(1200 * k, 12, "triangle", 2500), 0.8)]),
        "C": (
            "Static click",
            lambda k: [(0, nz(6, "highpass", f=6000, q=0.7, atk=1), 0.8), (0, tick(900 * k, 5, "sine"), 0.5)],
        ),
        "D": ("Bit", lambda k: [(0, tick(3200 * k, 4, "square", 6000), 0.8)]),
        "E": ("Chirp tick", lambda k: [(0, chirp(2000 * k, 2800 * k, 6), 0.8)]),
        "F": ("Dual tick", lambda k: dual(1500 * k, 2300 * k, 6, 0.9)),
    },
    "term_enter": {
        "A": (
            "Double tick",
            lambda k: [(0, tick(1000 * k, 12, lp=3000), 0.8), (30, tick(1500 * k, 12, lp=3000), 0.8)],
        ),
        "B": ("Low confirm", lambda k: [(0, tick(220 * k, 40, "triangle", 900), 0.9)]),
        "C": ("Sweep", lambda k: [(0, nz(45, f=600 * k, f2=2500 * k, q=1.2, atk=3), 0.8)]),
        "D": ("Serial burst", lambda k: [(x, tick(1800 * k, 8, lp=4000), 0.8) for x in (0, 13, 26, 39)]),
        "E": ("Down chirp", lambda k: [(0, chirp(1400 * k, 700 * k, 40), 0.8)]),
        "F": (
            "Ack pair",
            lambda k: [(0, tick(880 * k, 20, "sine", 3000), 0.8), (30, tick(660 * k, 20, "sine", 3000), 0.8)],
        ),
    },
    "term_out": {
        "A": ("Data tick", lambda k: [(0, tick(3000 * k, 6, "square", 5000), 0.8)]),
        "B": ("Telemetry blip", lambda k: [(0, tick(1000 * k, 10, "triangle", 2500), 0.8)]),
        "C": (
            "Chatter pair",
            lambda k: [(0, tick(2200 * k, 8, lp=4500), 0.8), (14, tick(1700 * k, 8, lp=4500), 0.8)],
        ),
        "D": ("Static pop", lambda _k: [(0, nz(3, "highpass", f=5000, q=0.7, atk=0.5), 0.9)]),
        "E": ("Micro chirp", lambda k: [(0, chirp(2400 * k, 3000 * k, 5), 0.8)]),
        "F": ("AM tick", lambda k: [(0, am(1600 * k, 8, 120), 0.9)]),
    },
}


# ---- working: the sound that plays while Claude is thinking or running a command ------
# The mockup "Working Cues", candidate J: a mechanical watch beating 6 times a second.
# The player (lua/sounds/player.swift) runs the train: it picks a tick or tock file at
# random for each beat and schedules the beats on the audio clock. Every beat is two
# metallic clicks (lock, then a softer and lower drop) from a ringing plate over a faint
# case body, through one gentle low-pass. The other candidates (A-I) live in the mockup.

WORKING_LEVEL = -29.0  # dBFS; the tock is 1.4 dB softer, as in the mockup
WORKING_VARIANTS = (0.98, 1.0, 1.02)  # tiny pitch differences, one picked per beat
WORKING_LOW = 0.79  # played at this speed while a Bash command runs: lower, and stretched


def _biquad(x, kind, fc, q):
    w0 = 2 * math.pi * fc / SR
    alpha, c = math.sin(w0) / (2 * q), math.cos(w0)
    if kind == "bp":
        b0, b1, b2 = alpha, 0.0, -alpha
    else:
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for v in x:
        o = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        y.append(o)
        x2, x1, y2, y1 = x1, v, y1, o
    return y


def _decay(i, n, a, peak):
    """Linear attack over `a` samples, then exponential decay to silence at n."""
    if i < a:
        return peak * i / max(1, a)
    return peak * (1e-4 / peak) ** ((i - a) / max(1, n - a))


def _wclick(f, q, dur_ms, gain, atk_ms, rng):
    n = ms(dur_ms)
    x = _biquad([rng() for _ in range(n + 256)], "bp", f, q)[256:]
    a = max(1, ms(atk_ms))
    return [x[i] * _decay(i, n, a, gain) for i in range(n)]


def _wring(f, dur_ms, gain):
    n = ms(dur_ms)
    a = max(1, ms(0.5))
    return [math.sin(TAU * f * i / SR) * _decay(i, n, a, gain) for i in range(n)]


def watch_beat(k, gap_ms, low=False, seed=1):
    """One beat of the watch at pitch factor k, `gap_ms` between the lock and the drop click."""
    r = WORKING_LOW if low else 1.0  # slower playback lowers the pitch and stretches time, like the browser's rate
    t = 1.0 / r
    kk = k * r
    rng = Rng(seed)
    b = [0.0] * ms(130 * t)

    def add(start_ms, sig):
        o = ms(start_ms * t)
        for i, v in enumerate(sig):
            if o + i < len(b):
                b[o + i] += v

    add(0, _wclick(2800 * kk, 1.4, 4 * t, 0.55, 1.0 * t, rng))
    for f, g, d in ((2350, 0.455, 9), (3720, 0.26, 6), (5100, 0.104, 4)):
        add(0, _wring(f * kk, d * t, g))
    add(1, _wring(300 * kk, 16 * t, 0.10))
    add(0, _wring(620 * kk, 10 * t, 0.05))
    add(gap_ms, _wclick(2200 * kk, 1.4, 4 * t, 0.385, 1.0 * t, rng))
    for f, g, d in ((1900, 0.286, 7), (3000, 0.156, 5)):
        add(gap_ms, _wring(f * kk, d * t, g))
    add(gap_ms, _wring(280 * kk, 9.6 * t, 0.045))
    return finish(_biquad(b, "lp", 5200 * r, 0.7))


def render(peak_db, parts):
    end = max(ms(off) + len(x) for off, x, _ in parts)
    mix = [0.0] * end
    for off, x, g in parts:
        o = ms(off)
        for i, v in enumerate(x):
            mix[o + i] += v * g
    peak = max(abs(v) for v in mix) or 1.0
    k = 10 ** (peak_db / 20) / peak
    return [v * k for v in mix]


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))


# ---- serious presets: Ledger, Muted keys, Advisory ---------------------------
#
# Three whole-set presets from the browser mockup "Serious Cues"
# (https://claude.ai/artifact/HvCdJMZnHbqfocVAZ8zdP4). Plain tones, still
# computer-like: dry, low-mid register, small intervals, no arpeggios. Each preset
# folder (sounds/<preset>/) has the layout of sounds/ and holds all three families
# as letters A (Ledger), B (Muted keys), C (Advisory); the preset's own letter is
# its pick, the others are alternatives for the menu.

FAMILIES = {
    "A": ("ledger", "Ledger", 220.0),  # pure sines, soft decay
    "B": ("muted_keys", "Muted keys", 293.66),  # sine + damped tine
    "C": ("advisory", "Advisory", 440.0),  # flat gated triangle
}

# event: (dBFS peak, {letter: (name, gap ms, [(semitones from root, length ms)])})
SERIOUS = {
    "save": (-23.0, {
        "A": ("Soft tick", 0, [(12, 50)]),
        "B": ("Tine tick", 0, [(12, 40)]),
        "C": ("Blip", 0, [(12, 28)])}),
    "commit": (-15.5, {
        "A": ("Settled fifth", 140, [(0, 160), (7, 330)]),
        "B": ("Major third close", 120, [(4, 110), (0, 320)]),
        "C": ("Two-tone chime", 110, [(0, 90), (7, 150)])}),
    "pull": (-15.5, {
        "A": ("Stepped descent", 110, [(9, 120), (5, 120), (2, 280)]),
        "B": ("Fourth down", 100, [(5, 100), (0, 280)]),
        "C": ("Two-tone down", 110, [(7, 90), (0, 150)])}),
    "push": (-15.5, {
        "A": ("Hand-off", 90, [(0, 100), (5, 250)]),
        "B": ("Fifth out", 100, [(0, 90), (7, 280)]),
        "C": ("Two-tone up", 110, [(0, 90), (5, 150)])}),
    "checkout": (-21.0, {
        "A": ("Double tick", 80, [(7, 55), (7, 90)]),
        "B": ("Step", 70, [(0, 50), (5, 80)]),
        "C": ("Pair", 75, [(0, 38), (0, 38)])}),
    "claude_start": (-20.0, {
        "A": ("Open line", 0, [(5, 200)]),
        "B": ("Wake", 60, [(0, 70), (7, 210)]),
        "C": ("Advisory", 0, [(5, 120)])}),
    "claude_done": (-15.0, {
        "A": ("Resolve", 150, [(7, 150), (0, 440)]),
        "B": ("Fall to root", 130, [(9, 130), (4, 130), (0, 420)]),
        "C": ("Long fall", 120, [(7, 90), (0, 320)])}),
    "claude_input": (-15.0, {
        "A": ("Query", 130, [(0, 120), (3, 380)]),
        "B": ("Open fifth", 120, [(0, 120), (7, 380)]),
        "C": ("Attention", 210, [(5, 100), (5, 100)])}),
    "breakpoint": (-16.0, {
        "A": ("Held low", 0, [(-12, 430)]),
        "B": ("Low pedal", 0, [(-5, 420)]),
        "C": ("Caution tone", 0, [(-12, 280)])}),
    "ok": (-17.0, {
        "A": ("Confirm", 0, [(7, 170)]),
        "B": ("Soft third", 0, [(4, 150)]),
        "C": ("Single beep", 0, [(7, 95)])}),
    "fail": (-14.5, {
        "A": ("Tritone drop", 120, [(0, 140), (-6, 380)]),
        "B": ("Minor second", 100, [(0, 120), (-1, 380)]),
        "C": ("Triple low", 105, [(-5, 85), (-5, 85), (-5, 210)])}),
}

# chatter cues: the same shape, one short note each (played with the pitch variants)
SERIOUS_CHATTER = {
    "claude_line": (-26.0, {
        "A": ("Low pulse", 0, [(-7, 24)]),
        "B": ("Low tine", 0, [(-5, 22)]),
        "C": ("Low tick", 0, [(-12, 18)])}),
    "term_key": (-28.0, {
        "A": ("Soft tick", 0, [(19, 14)]),
        "B": ("Tine", 0, [(14, 14)]),
        "C": ("Click tone", 0, [(17, 9)])}),
    "term_enter": (-22.0, {
        "A": ("Low confirm", 0, [(-5, 60)]),
        "B": ("Soft thud", 0, [(-7, 60)]),
        "C": ("Low beep", 0, [(-12, 45)])}),
    "term_out": (-30.0, {
        "A": ("Faint tick", 0, [(24, 10)]),
        "B": ("Faint tine", 0, [(19, 10)]),
        "C": ("Faint pip", 0, [(22, 8)])}),
}


def _mix(layers):
    """Sum (offset ms, samples, gain) layers into one list (not normalised)."""
    n = max(ms(o) + len(v) for o, v, _ in layers)
    out = [0.0] * n
    for o, v, g in layers:
        base = ms(o)
        for i, x in enumerate(v):
            out[base + i] += x * g
    return out


def serious_note(letter, f, length):
    """One note of family A (sine, soft decay), B (sine + damped tine) or C (flat triangle)."""
    s = length
    if letter == "A":
        layers = [
            (0, osc(f, s * 1.35 + 70, "sine", lp=4000, atk=6, env="exp"), 1.0),
            (0, osc(f * 2, s * 0.7 + 40, "sine", lp=4000, atk=6, env="exp"), 0.07),
        ]
    elif letter == "B":
        layers = [
            (0, osc(f, s * 1.5 + 60, "sine", lp=5000, atk=3, env="exp"), 0.9),
            (0, osc(f * 2, s * 0.8 + 40, "sine", lp=5000, atk=2, env="exp"), 0.28),
            (0, osc(f * 4.02, 35, "sine", lp=7000, atk=1, env="exp"), 0.1),
        ]
    else:
        layers = [(0, osc(f, s + 30, "triangle", lp=2600, atk=6, rel=30, env="gate"), 0.8)]
    return finish(_mix(layers))


def serious_cue(letter, spec, level, k=1.0):
    """The samples of one cue: its notes, `gap` ms apart, the last one a little louder."""
    _, gap, notes = spec
    root = FAMILIES[letter][2] * k
    parts = []
    for i, (semi, length) in enumerate(notes):
        gain = 0.75 + 0.25 * (1.0 if i == len(notes) - 1 else 0.8)
        parts.append((gap * i, serious_note(letter, root * 2 ** (semi / 12), length), gain))
    return render(level, parts)


# ---- character presets: Cupertino, Mission Control, Sonar, Whisper -----------
#
# From the browser mockup "Character Cues" (https://claude.ai/artifact/4ATs2S5c1nRmUiHJZt6aE2).
# Each note is (voice, at ms, ...args); the voices below are Python ports of the
# mockup's Web Audio voices, left at their natural amplitudes so a cue keeps the
# mockup's balance between its layers (render() then sets the cue's peak).
# "working" is (name, beats a second, tick notes, tock notes): the Claude-working train.

CHARACTER = {
    "cupertino": {
        "events": {
            "save": ("Tink", [("fm", 0, 1175, 80, 0.5, 2, 0.5)]),
            "commit": ("Soft pair", [("fm", 0, 587, 200, 0.55, 2, 0.4), ("fm", 110, 880, 420, 0.6, 2, 0.4)]),
            "pull": ("Swoosh in", [("sw", 0, 280, 0.4, "down")]),
            "push": ("Swoosh out + tink", [("sw", 0, 260, 0.4, "up"), ("fm", 230, 988, 160, 0.4, 2, 0.4)]),
            "checkout": ("Tock", [("tock", 0, 0.5)]),
            "claude_start": ("Pop", [("pop", 0, 440, 120, 150, 0.7)]),
            "claude_done": ("Falling notes", [("fm", 0, 784, 180, 0.5, 2, 0.35), ("fm", 130, 587, 180, 0.5, 2, 0.35), ("fm", 260, 392, 460, 0.6, 2, 0.35)]),
            "claude_input": ("Ping ping", [("fm", 0, 880, 160, 0.55, 2, 0.4), ("fm", 200, 880, 340, 0.6, 2, 0.4)]),
            "breakpoint": ("Low thud", [("fm", 0, 131, 450, 0.7, 1, 0.5)]),
            "ok": ("Soft tink", [("fm", 0, 988, 140, 0.5, 2, 0.4)]),
            "fail": ("Low pair", [("fm", 0, 174, 170, 0.6, 1, 0.5), ("fm", 130, 131, 440, 0.65, 1, 0.5)]),
        },
        "chatter": {
            "term_key": ("Soft tock", [("tock", 0, 0.3)]),
            "term_enter": ("Pop", [("pop", 0, 260, 100, 60, 0.6)]),
            "term_out": ("Soft dot", [("fm", 0, 1568, 14, 0.25, 2, 0.3)]),
            "claude_line": ("Soft pop", [("pop", 0, 330, 160, 35, 0.45)]),
        },
        "working": ("Soft tock pair", 4.0, [("fm", 0, 700, 28, 0.4, 2, 0.3)], [("fm", 0, 520, 30, 0.34, 2, 0.3)]),
    },
    "mission_control": {
        "events": {
            "save": ("Tick tone", [("q", 0, 1400, 22, 0.4)]),
            "commit": ("Telemetry lock", [("q", 0, 1000, 40, 0.55), ("q", 90, 1000, 40, 0.55), ("q", 180, 1000, 40, 0.55)]),
            "pull": ("Downlink", [("q", 0, 1500, 50, 0.5), ("q", 120, 1000, 90, 0.55, True)]),
            "push": ("Key-up, blip", [("q", 0, 2525, 70, 0.4), ("q", 120, 1000, 50, 0.5)]),
            "checkout": ("Single tick", [("q", 0, 1000, 28, 0.45)]),
            "claude_start": ("Key-up tone", [("q", 0, 2525, 70, 0.4, True)]),
            "claude_done": ("Over and out", [("q", 0, 2475, 70, 0.45), ("q", 130, 700, 60, 0.5, True)]),
            "claude_input": ("Callout", [("q", 0, 1500, 70, 0.5), ("q", 170, 1500, 70, 0.5)]),
            "breakpoint": ("Hold tone", [("q", 0, 440, 380, 0.55, True)]),
            "ok": ("Go", [("q", 0, 1000, 90, 0.5)]),
            "fail": ("No-go", [("q", 0, 800, 90, 0.55), ("q", 130, 500, 200, 0.55)]),
        },
        "chatter": {
            "term_key": ("Radio tick", [("q", 0, 1800, 6, 0.3)]),
            "term_enter": ("Key-up", [("q", 0, 900, 40, 0.5)]),
            "term_out": ("Data tick", [("q", 0, 1400, 5, 0.25)]),
            "claude_line": ("Carrier blip", [("q", 0, 1000, 12, 0.4)]),
        },
        "working": ("Telemetry pulse", 4.0, [("q", 0, 1000, 8, 0.4)], [("q", 0, 800, 8, 0.32)]),
    },
    "sonar": {
        "events": {
            "save": ("Small ping", [("ping", 0, 1300, 45, 0.4)]),
            "commit": ("Ping, near echo", [("ping", 0, 660, 420, 0.65), ("ping", 230, 660, 300, 0.22)]),
            "pull": ("Ping, close return", [("ping", 0, 880, 260, 0.5), ("ping", 140, 880, 300, 0.35)]),
            "push": ("Ping, far echo", [("ping", 0, 520, 300, 0.6), ("ping", 320, 520, 350, 0.2)]),
            "checkout": ("Short ping", [("ping", 0, 1000, 60, 0.4)]),
            "claude_start": ("Low ping", [("ping", 0, 330, 260, 0.55)]),
            "claude_done": ("Ping, fading echoes", [("ping", 0, 440, 360, 0.65), ("ping", 240, 440, 320, 0.28), ("ping", 480, 440, 300, 0.12)]),
            "claude_input": ("Two pings", [("ping", 0, 600, 200, 0.6), ("ping", 230, 600, 300, 0.6)]),
            "breakpoint": ("Deep ping", [("ping", 0, 165, 500, 0.7)]),
            "ok": ("Clear ping", [("ping", 0, 740, 240, 0.5)]),
            "fail": ("Dissonant return", [("ping", 0, 247, 320, 0.65), ("ping", 110, 233, 420, 0.5)]),
        },
        "chatter": {
            "term_key": ("Micro ping", [("ping", 0, 1600, 8, 0.25)]),
            "term_enter": ("Low ping", [("ping", 0, 300, 60, 0.5)]),
            "term_out": ("Sonar dot", [("ping", 0, 2000, 6, 0.2)]),
            "claude_line": ("Low ping", [("ping", 0, 520, 16, 0.3)]),
        },
        "working": ("Slow sweep", 0.8, [("ping", 0, 520, 380, 0.45), ("ping", 220, 520, 300, 0.14)], [("ping", 0, 520, 380, 0.45), ("ping", 220, 520, 300, 0.14)]),
    },
    "whisper": {
        "events": {
            "save": ("Tick", [("tick", 0, 3200, 10, 0.5)]),
            "commit": ("Double knock", [("thump", 0, 85, 70, 0.7), ("thump", 110, 110, 110, 0.65)]),
            "pull": ("Breath in", [("breath", 0, 230, 0.55, "up")]),
            "push": ("Breath out", [("breath", 0, 230, 0.55, "down")]),
            "checkout": ("Tick tick", [("tick", 0, 2600, 8, 0.5), ("tick", 70, 2600, 8, 0.5)]),
            "claude_start": ("Soft thump", [("thump", 0, 95, 80, 0.6)]),
            "claude_done": ("Heartbeat", [("thump", 0, 80, 70, 0.65), ("thump", 140, 70, 160, 0.65)]),
            "claude_input": ("Nudge", [("tick", 0, 3000, 8, 0.5), ("tick", 90, 3000, 8, 0.5), ("thump", 200, 100, 100, 0.65)]),
            "breakpoint": ("Long thump", [("thump", 0, 70, 260, 0.85)]),
            "ok": ("Tap", [("thump", 0, 120, 50, 0.5), ("tick", 0, 3400, 6, 0.35)]),
            "fail": ("Heavy double", [("thump", 0, 60, 90, 0.85), ("thump", 100, 52, 200, 0.85)]),
        },
        "chatter": {
            "term_key": ("Finger tick", [("tick", 0, 3500, 4, 0.35)]),
            "term_enter": ("Small thump", [("thump", 0, 110, 35, 0.6)]),
            "term_out": ("Grain", [("tick", 0, 5000, 3, 0.25)]),
            "claude_line": ("Soft thump", [("thump", 0, 90, 18, 0.5)]),
        },
        "working": ("Slow heartbeat", 1.3, [("thump", 0, 78, 80, 0.55)], [("thump", 0, 70, 90, 0.38)]),
    },
}

NOTE_ARGS = {
    "fm": ("at", "f", "ms", "g", "r", "i"),
    "pop": ("at", "f", "f1", "ms", "g"),
    "tock": ("at", "g"),
    "sw": ("at", "ms", "g", "dir"),
    "q": ("at", "f", "ms", "g", "sq"),
    "ping": ("at", "f", "ms", "g"),
    "thump": ("at", "f", "ms", "g"),
    "tick": ("at", "f", "ms", "g"),
    "breath": ("at", "ms", "g", "dir"),
}
NOTE_DEFAULTS = {"r": 3.01, "i": 1.4, "sq": False, "f": 190.0, "ms": 35.0, "dir": "up"}


def _note(t, pitch=1.0, stretch=1.0):
    """A note tuple as a dict, with pitch and time scaled (the "lower, slower" working sound)."""
    n = dict(NOTE_DEFAULTS)
    n["kind"] = t[0]
    n.update(zip(NOTE_ARGS[t[0]], t[1:]))
    for key in ("f", "f1"):
        if key in n:
            n[key] *= pitch
    n["at"] *= stretch
    if t[0] != "tock":
        n["ms"] *= stretch
    return n


def _exp_env(i, n, atk, peak=1.0):
    """Linear attack over `atk` samples, then an exponential fall to 1e-4 at sample n."""
    if i < atk:
        return peak * i / max(1, atk)
    return peak * (1e-4 / peak) ** ((i - atk) / max(1, n - atk))


def _lp(x, fc):
    """Two cascaded one-pole low-passes (as in osc)."""
    a = 1 - math.exp(-TAU * fc / SR)
    s1 = s2 = 0.0
    out = []
    for v in x:
        s1 += a * (v - s1)
        s2 += a * (s1 - s2)
        out.append(s2)
    return out


def _noise_raw(n, seed):
    r = Rng(seed)
    return [r() for _ in range(n)]


def _swept(x, kind, f0, f1, q):
    """A biquad (bandpass / lowpass) whose cutoff glides f0 -> f1 (exponentially) across x."""
    n = len(x)
    out = []
    x1 = x2 = y1 = y2 = 0.0
    c = (1.0, 0.0, 0.0, 0.0, 0.0)
    for i, v in enumerate(x):
        if i % 32 == 0:
            fc = f0 * (f1 / f0) ** (i / max(1, n - 1))
            w0 = TAU * min(fc, SR / 2.2) / SR
            alpha, cs = math.sin(w0) / (2 * q), math.cos(w0)
            if kind == "bp":
                b0, b1, b2 = alpha, 0.0, -alpha
            else:
                b0, b1, b2 = (1 - cs) / 2, 1 - cs, (1 - cs) / 2
            a0 = 1 + alpha
            c = (b0 / a0, b1 / a0, b2 / a0, -2 * cs / a0, (1 - alpha) / a0)
        o = c[0] * v + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
        out.append(o)
        x2, x1, y2, y1 = x1, v, y1, o
    return out


def _bell(n, up_frac, peak):
    """Linear rise to `peak` at up_frac of n, then an exponential fall to 1e-4."""
    a = max(1, int(n * up_frac))
    return [(peak * i / a) if i < a else peak * (1e-4 / peak) ** ((i - a) / max(1, n - a)) for i in range(n)]


def _sweep_ph(n, f0, f1, over):
    """Phase of a tone gliding f0 -> f1 over `over` samples, then holding."""
    ph, out = 0.0, []
    for i in range(n):
        f = f0 * (f1 / f0) ** min(1.0, i / max(1, over))
        ph += f / SR
        out.append(ph)
    return out


def v_fm(n):
    f, d = n["f"], n["ms"] / 1000 * 1.1
    atk, tot = ms(5), ms(5) + int(SR * d) + ms(20)
    beta0 = n["i"] / n["r"]
    out, ph = [], 0.0
    for i in range(tot):
        t = i / SR
        env = (0.02 / n["i"]) ** min(1.0, t / (0.5 * d))
        ph += f / SR
        out.append(math.sin(TAU * ph + beta0 * env * math.sin(TAU * f * n["r"] * t)) * _exp_env(i, atk + int(SR * d), atk, n["g"]) if i < atk + int(SR * d) else 0.0)
    return _lp(out, 3000)


def v_pop(n):
    d = n["ms"] / 1000
    N = ms(3) + int(SR * d) + ms(20)
    ph = _sweep_ph(N, n["f"], n["f1"], int(SR * d * 0.6))
    return [math.sin(TAU * ph[i]) * (_exp_env(i, ms(3) + int(SR * d), ms(3), n["g"]) if i < ms(3) + int(SR * d) else 0.0) for i in range(N)]


def v_tock(n):
    g = n["g"]
    nz1 = _swept(_noise_raw(ms(20), 31), "bp", 1000, 1000, 0.9)
    a = [v * _exp_env(i, ms(18), ms(2), g * 1.3) if i < ms(18) else 0.0 for i, v in enumerate(nz1)]
    N = ms(60)
    b = [math.sin(TAU * n["f"] * 0.85 * i / SR) * (_exp_env(i, ms(43), ms(3), g * 0.9) if i < ms(43) else 0.0) for i in range(N)]
    return _mix([(0, a, 1.0), (0, b, 1.0)])


def v_sw(n):
    d = n["ms"] / 1000
    N = int(SR * d)
    up = n["dir"] == "up"
    x = _swept(_noise_raw(N, 41), "bp", 350 if up else 1800, 1800 if up else 350, 1.0)
    env = _bell(N, 0.45, n["g"] * 1.6)
    return [v * e for v, e in zip(x, env)]


def v_q(n):
    d, g = n["ms"] / 1000, n["g"]
    hold, rel, atk = int(SR * d), ms(12), ms(3)
    N = hold + rel
    x = []
    for i in range(N):
        a = g * i / atk if i < atk else g if i < hold else g * (1e-4 / g) ** ((i - hold) / rel)
        x.append(math.sin(TAU * n["f"] * i / SR) * a)
    x = _lp(x, 4500)
    if n["sq"]:
        sq = _swept(_noise_raw(ms(40), 51), "bp", 2800, 2800, 0.7)
        sq = [v * _exp_env(i, ms(40), ms(2), g * 0.5) for i, v in enumerate(sq)]
        return _mix([(0, x, 1.0), (n["ms"], sq, 1.0)])
    return x


def v_ping(n):
    d = n["ms"] / 1000 * 1.1
    N = ms(4) + int(SR * d) + ms(20)
    ph = _sweep_ph(N, n["f"] * 1.035, n["f"], ms(40))
    x = [math.sin(TAU * ph[i]) * (_exp_env(i, ms(4) + int(SR * d), ms(4), n["g"]) if i < ms(4) + int(SR * d) else 0.0) for i in range(N)]
    return _lp(x, 3000)


def v_thump(n):
    d = n["ms"] / 1000
    N = ms(2) + int(SR * d) + ms(20)
    ph = _sweep_ph(N, n["f"] * 1.5, n["f"], ms(30))
    return [
        (math.sin(TAU * ph[i]) + 0.5 * math.sin(TAU * n["f"] * 2 * i / SR)) * (_exp_env(i, ms(2) + int(SR * d), ms(2), n["g"]) if i < ms(2) + int(SR * d) else 0.0)
        for i in range(N)
    ]


def v_tick(n):
    d = n["ms"] / 1000
    N = int(SR * d) + ms(10)
    x = _swept(_noise_raw(N, 61), "bp", n["f"], n["f"], 1.2)
    return [v * (_exp_env(i, ms(1) + int(SR * d), ms(1), n["g"] * 2.2) if i < ms(1) + int(SR * d) else 0.0) for i, v in enumerate(x)]


def v_breath(n):
    d = n["ms"] / 1000
    N = int(SR * d)
    up = n["dir"] == "up"
    x = _swept(_noise_raw(N, 71), "lp", 250 if up else 1500, 1500 if up else 250, 0.7)
    env = _bell(N, 0.5, n["g"] * 1.5)
    return [v * e for v, e in zip(x, env)]


VOICES = {"fm": v_fm, "pop": v_pop, "tock": v_tock, "sw": v_sw, "q": v_q, "ping": v_ping, "thump": v_thump, "tick": v_tick, "breath": v_breath}


# steady sines (Mission Control) read louder than their peak says; thumps and noise quieter
FAMILY_TRIM_DB = {"mission_control": -3.0, "whisper": 1.0}


def character_cue(notes, level, pitch=1.0, stretch=1.0, trim=0.0):
    level += trim
    parts = []
    for t in notes:
        n = _note(t, pitch, stretch)
        parts.append((n["at"], VOICES[n["kind"]](n), 1.0))
    return render(level, parts)


# the library: every family, one folder each (sounds/library/<key>/), shared by all presets
LIBRARY = [
    ("ledger", "Ledger", "A"),
    ("muted_keys", "Muted keys", "B"),
    ("advisory", "Advisory", "C"),
    ("cupertino", "Cupertino", None),
    ("mission_control", "Mission Control", None),
    ("sonar", "Sonar", None),
    ("whisper", "Whisper", None),
]
WORKING_LOW_RATE = 0.8  # beats a second while a command runs, times the family's own rate


def write_library(outdir):
    """sounds/library/<family>/: <event>.wav, chatter/<cue>_<1..4>.wav (+ working beats), and
    sounds/library/catalog.json. A preset is then only a choice of family per cue (menu.lua)."""
    lib = f"{outdir}/library"
    catalog = {"families": [{"key": k, "label": l} for k, l, _ in LIBRARY], "events": {}, "chatter": {}, "working": {}}
    for key, label, letter in LIBRARY:
        root = f"{lib}/{key}"
        os.makedirs(f"{root}/chatter", exist_ok=True)
        if letter:  # one of the serious families, written as semitone phrases
            for event, (level, options) in SERIOUS.items():
                write(f"{root}/{event}.wav", serious_cue(letter, options[letter], level))
                catalog["events"].setdefault(event, {})[key] = options[letter][0]
            for cue, (level, options) in SERIOUS_CHATTER.items():
                for n, k in enumerate(VARIANTS, 1):
                    write(f"{root}/chatter/{cue}_{n}.wav", serious_cue(letter, options[letter], level, k))
                catalog["chatter"].setdefault(cue, {})[key] = options[letter][0]
        else:
            data = CHARACTER[key]
            for event, (name, notes) in data["events"].items():
                write(f"{root}/{event}.wav", character_cue(notes, SERIOUS[event][0], trim=FAMILY_TRIM_DB.get(key, 0.0)))
                catalog["events"].setdefault(event, {})[key] = name
            for cue, (name, notes) in data["chatter"].items():
                for n, k in enumerate(VARIANTS, 1):
                    write(f"{root}/chatter/{cue}_{n}.wav", character_cue(notes, SERIOUS_CHATTER[cue][0], k, trim=FAMILY_TRIM_DB.get(key, 0.0)))
                catalog["chatter"].setdefault(cue, {})[key] = name
            wname, rate, tick, tock = data["working"]
            for low in (False, True):
                for n, v in enumerate(WORKING_VARIANTS, 1):
                    for beat, notes, db in (("tick", tick, 0.0), ("tock", tock, -1.4)):
                        pitch, stretch = (v * WORKING_LOW, 1 / WORKING_LOW) if low else (v, 1.0)
                        name = f"working_{'low_' if low else ''}{beat}_{n}.wav"
                        write(f"{root}/chatter/{name}", character_cue(notes, WORKING_LEVEL + db, pitch, stretch, FAMILY_TRIM_DB.get(key, 0.0)))
            catalog["working"][key] = {"name": wname, "rate": rate, "rate_low": round(rate * WORKING_LOW_RATE, 3)}
        print(f"library {label} -> {root}/")
    with open(f"{lib}/catalog.json", "w") as f:
        json.dump(catalog, f, indent=1, ensure_ascii=False)
        f.write("\n")


def main():
    args = sys.argv[1:]
    cand_dir = None
    if "--candidates" in args:
        i = args.index("--candidates")
        cand_dir = args[i + 1].rstrip("/") if i + 1 < len(args) else None
        args = args[:i] + args[i + 2 :]
    if len(args) != 1 or ("--candidates" in sys.argv and not cand_dir):
        sys.exit(__doc__)
    outdir = args[0].rstrip("/")
    for event, letter in PICKS.items():
        _, parts = CANDIDATES[event][letter]
        path = f"{outdir}/{event}.wav"
        write(path, render(LEVELS[event], parts))
        print(path)
    chatter_dir = f"{outdir}/chatter"
    os.makedirs(chatter_dir, exist_ok=True)
    for cue, letter in CHATTER_PICKS.items():
        _, build = CHATTER[cue][letter]
        for n, k in enumerate(VARIANTS, 1):
            write(f"{chatter_dir}/{cue}_{n}.wav", render(CHATTER_LEVELS[cue], build(k)))
    # the working sound: working[_low]_{tick,tock}_{1..3}.wav (low = while a command runs)
    for low in (False, True):
        for n, v in enumerate(WORKING_VARIANTS, 1):
            for beat, base, gap, db in (("tick", 1.0, 17, 0.0), ("tock", 0.9, 19, -1.4)):
                voice = watch_beat(base * v, gap, low, seed=10 * n + (3 if beat == "tock" else 1))
                name = f"working_{'low_' if low else ''}{beat}_{n}.wav"
                write(f"{chatter_dir}/{name}", render(WORKING_LEVEL + db, [(0, voice, 1.0)]))
    # every candidate (one file each), so `:Chatter test <cue> <A-F>` can audition them
    # through the real player, at the real level
    os.makedirs(f"{chatter_dir}/candidates", exist_ok=True)
    for cue, options in CHATTER.items():
        for letter, (_, build) in options.items():
            write(f"{chatter_dir}/candidates/{cue}_{letter}.wav", render(CHATTER_LEVELS[cue], build(1.0)))
    print(f"chatter -> {chatter_dir}/ ({len(CHATTER_PICKS) * len(VARIANTS)} files + 30 candidates)")
    # Alternatives the sound menu (lua/sounds/menu.lua) can switch to at runtime:
    #   candidates/<event>_<letter>.wav          every letter of every event
    #   chatter/alt/<cue>_<letter>_<1..4>.wav    every letter of every chatter cue, with pitch variants
    os.makedirs(f"{outdir}/candidates", exist_ok=True)
    for event, options in CANDIDATES.items():
        for letter, (_, parts) in options.items():
            write(f"{outdir}/candidates/{event}_{letter}.wav", render(LEVELS[event], parts))
    os.makedirs(f"{chatter_dir}/alt", exist_ok=True)
    for cue, options in CHATTER.items():
        for letter, (_, build) in options.items():
            for n, k in enumerate(VARIANTS, 1):
                write(f"{chatter_dir}/alt/{cue}_{letter}_{n}.wav", render(CHATTER_LEVELS[cue], build(k)))
    # catalog.json: names and active letters, read by the menu (one source of truth)
    catalog = {
        "events": {e: {l: n for l, (n, _) in o.items()} for e, o in CANDIDATES.items()},
        "picks": PICKS,
        "chatter": {c: {l: n for l, (n, _) in o.items()} for c, o in CHATTER.items()},
        "chatter_picks": CHATTER_PICKS,
    }
    with open(f"{outdir}/catalog.json", "w") as f:
        json.dump(catalog, f, indent=1, ensure_ascii=False)
        f.write("\n")
    write_library(outdir)
    if cand_dir:
        for event, options in CANDIDATES.items():
            for letter, (_, parts) in options.items():
                write(f"{cand_dir}/{event}_{letter}.wav", render(LEVELS[event], parts))
        for cue, options in CHATTER.items():
            for letter, (_, build) in options.items():
                write(f"{cand_dir}/chatter_{cue}_{letter}.wav", render(CHATTER_LEVELS[cue], build(1.0)))
        print(f"candidates -> {cand_dir}/")


if __name__ == "__main__":
    main()
