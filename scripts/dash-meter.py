#!/usr/bin/env python3
"""Measure what an idle Neovim dashboard costs the terminal.

Spawns `nvim` in a pseudo-terminal of a fixed size, waits for the dashboard to
settle (warm-up), then counts every byte Neovim writes during the measuring
window, plus the CPU time it burns. Kitty has to parse and draw those bytes
(and, on a blurred translucent window, WindowServer re-blurs each frame), so
bytes per second is the number that matters.

    python3 scripts/dash-meter.py                     # the dashboard as configured
    python3 scripts/dash-meter.py --piece phosphor    # force a header_art piece
    python3 scripts/dash-meter.py --cmd 'edit /etc/hosts'   # a file buffer, for comparison

Budget from issue #44: <= 1 KiB/s and ~0 % CPU on an idle, focused dashboard.
"""
import argparse
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


def cpu_seconds(pid):
    """Cumulative CPU time of a process, from `ps` (M:SS.cc or H:MM:SS)."""
    out = subprocess.run(["ps", "-o", "cputime=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    if not out:
        return 0.0
    total = 0.0
    for part in out.split(":"):
        total = total * 60 + float(part)
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cols", type=int, default=200)
    ap.add_argument("--rows", type=int, default=60)
    ap.add_argument("--warmup", type=float, default=6.0, help="seconds to wait before measuring")
    ap.add_argument("--seconds", type=float, default=5.0, help="length of the measuring window")
    ap.add_argument("--piece", help="header_art piece to force for this run (session only)")
    ap.add_argument("--cmd", action="append", default=[], help="extra Ex command to run at startup (repeatable)")
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--nvim", default="nvim")
    ap.add_argument("--max-bps", type=float, default=None, help="exit 1 when bytes/s exceed this")
    args = ap.parse_args()

    cmds = list(args.cmd)
    if args.piece:
        cmds.insert(0, f"HeaderArt piece {args.piece}")

    argv = [args.nvim]
    for c in cmds:
        argv += ["-c", c]

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0))
    env = dict(os.environ, TERM="xterm-kitty" if os.environ.get("TERM") == "xterm-kitty" else "xterm-256color")
    env.pop("NVIM", None)
    env.pop("NVIM_LISTEN_ADDRESS", None)
    proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, cwd=args.cwd, env=env, start_new_session=True)
    os.close(slave)

    total = 0
    counting = False
    t_start = time.monotonic()
    t_measure = t_start + args.warmup
    t_end = t_measure + args.seconds
    cpu0 = 0.0
    try:
        while True:
            now = time.monotonic()
            if now >= t_end:
                break
            if not counting and now >= t_measure:
                counting = True
                cpu0 = cpu_seconds(proc.pid)
            r, _, _ = select.select([master], [], [], 0.05)
            if r:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                if counting:
                    total += len(data)
        cpu1 = cpu_seconds(proc.pid)
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        os.close(master)

    elapsed = max(args.seconds, 1e-6)
    bps = total / elapsed
    cpu_pct = (cpu1 - cpu0) / elapsed * 100
    print(f"size        {args.cols}x{args.rows}")
    print(f"window      {args.seconds:g}s after {args.warmup:g}s warm-up")
    print(f"output      {total} bytes  =  {bps:,.0f} B/s  ({bps / 1024:,.1f} KiB/s)")
    print(f"nvim cpu    {cpu_pct:.1f} %")
    if args.max_bps is not None and bps > args.max_bps:
        print(f"FAIL: {bps:,.0f} B/s > {args.max_bps:,.0f} B/s")
        sys.exit(1)


if __name__ == "__main__":
    main()
