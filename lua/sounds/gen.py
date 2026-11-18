"""Synthesizes the editor's sound cues: the voice of a sci-fi computer terminal.

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
