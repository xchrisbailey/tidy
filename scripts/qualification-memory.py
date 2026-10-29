#!/usr/bin/env python3
"""Sample only this worktree's diagnostic processes; never emit process commands."""

import json
from pathlib import Path
import subprocess
import sys
import time


def main():
    root = Path(__file__).resolve().parent.parent
    if len(sys.argv) < 2:
        raise SystemExit("usage: python3 scripts/qualification-memory.py COMMAND [ARGS...]")
    # Sampling observes, rather than limits, memory. Short spikes can be missed.
    started = time.monotonic()
    child = subprocess.Popen(sys.argv[1:], cwd=root)
    peaks = {"model": 0, "parser": 0, "broker": 0}
    observations = dict.fromkeys(peaks, 0)
    maximum_sum = 0
    while child.poll() is None:
        listing = subprocess.run(
            ["ps", "-axo", "rss=,command="],
            check=True, capture_output=True, text=True,
        ).stdout
        total = 0
        for line in listing.splitlines():
            fields = line.strip().split(maxsplit=1)
            if len(fields) != 2 or not fields[1].startswith(str(root / ".build") + "/"):
                continue
            command = fields[1].split(maxsplit=1)[0]
            role = None
            if command.endswith("/Contents/MacOS/TidyModelSmoke"):
                role = "model"
            elif command.endswith("/Contents/Helpers/TidyInspectionHelper"):
                role = "parser"
            elif command.endswith("/Contents/MacOS/TidyInspectionService"):
                role = "broker"
            if role is not None:
                rss = int(fields[0]) * 1024
                peaks[role] = max(peaks[role], rss)
                observations[role] += 1
                total += rss
        maximum_sum = max(maximum_sum, total)
        time.sleep(0.05)
    print("QUAL sampledRSS " + json.dumps({
        "peakBytes": peaks,
        "observations": observations,
        "peakConcurrentSumBytes": maximum_sum,
        "seconds": round(time.monotonic() - started, 3),
        "commandExit": child.returncode,
        "nominalIntervalSeconds": 0.05,
        "limitations": "sampled RSS, not true peak/unified memory or a hard bound",
    }, sort_keys=True), flush=True)
    return child.returncode


if __name__ == "__main__":
    sys.exit(main())
