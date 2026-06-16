#!/usr/bin/env python3
"""Aggregate Claude Code token usage per day from the local logs.

Reads every ~/.claude/projects/**/*.jsonl transcript, sums the token counts on
each assistant message's `usage` block, and buckets them by local calendar day.
Emits a compact JSON summary on stdout for the Neovim dashboard to render.

Output shape:
  {
    "days":  [{"date": "YYYY-MM-DD", "tokens": N}, ...],  # oldest -> newest
    "today": N,            # tokens for the current local day
    "total": N,            # tokens across the whole window
    "ndays": 14
  }

Pure stdlib, read-only. Safe to run in the background.
"""

import glob
import json
import os
import sys
from datetime import datetime, timedelta

NDAYS = 14


def main() -> int:
    window = NDAYS
    if len(sys.argv) > 1:
        try:
            window = max(1, int(sys.argv[1]))
        except ValueError:
            pass

    home = os.path.expanduser("~")
    pattern = os.path.join(home, ".claude", "projects", "**", "*.jsonl")

    # local day -> token count
    per_day: dict[str, int] = {}

    for path in glob.iglob(pattern, recursive=True):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    line = line.strip()
                    if not line or '"usage"' not in line:
                        continue
                    try:
                        obj = json.loads(line)
                    except (ValueError, TypeError):
                        continue
                    msg = obj.get("message")
                    if not isinstance(msg, dict):
                        continue
                    usage = msg.get("usage")
                    ts = obj.get("timestamp")
                    if not isinstance(usage, dict) or not ts:
                        continue
                    tokens = (
                        int(usage.get("input_tokens", 0) or 0)
                        + int(usage.get("output_tokens", 0) or 0)
                        + int(usage.get("cache_creation_input_tokens", 0) or 0)
                        + int(usage.get("cache_read_input_tokens", 0) or 0)
                    )
                    if tokens <= 0:
                        continue
                    # timestamp is UTC ISO ("...Z"); convert to local calendar day.
                    try:
                        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                        day = dt.astimezone().strftime("%Y-%m-%d")
                    except ValueError:
                        continue
                    per_day[day] = per_day.get(day, 0) + tokens
        except OSError:
            continue

    today = datetime.now().astimezone()
    days = []
    total = 0
    for i in range(window - 1, -1, -1):
        d = (today - timedelta(days=i)).strftime("%Y-%m-%d")
        t = per_day.get(d, 0)
        total += t
        days.append({"date": d, "tokens": t})

    out = {
        "days": days,
        "today": per_day.get(today.strftime("%Y-%m-%d"), 0),
        "total": total,
        "ndays": window,
    }
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
