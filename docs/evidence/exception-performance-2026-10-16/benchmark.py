#!/usr/bin/env python3
"""Compare exception execution separately from CLI startup, compilation and exit.

Run serially, with no concurrent builds or tests. Thread CPU clock support is
required: an unsupported WASIp1 clock traps rather than silently returning zero.
"""

import argparse
import hashlib
import json
import random
import statistics
import subprocess
import time
from pathlib import Path


WORKLOADS = [
    ("snapshots", 20_000),
    ("snapshots", 100_000),
    ("snapshots", 300_000),
    ("snapshots-word", 300_000),
    ("rethrow", 200_000),
    ("rethrow", 2_000_000),
    ("rethrow-many", 2_000_000),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rounds", type=int, default=11)
    parser.add_argument("binaries", nargs="+", metavar="NAME=PATH")
    parser.add_argument("--workload", choices=sorted({name for name, _ in WORKLOADS}))
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    binaries = {}
    for item in args.binaries:
        name, separator, value = item.partition("=")
        if not separator or not name or name in binaries:
            parser.error("binary arguments must have distinct names and NAME=PATH form")
        binaries[name] = Path(value).resolve(strict=True)
    report = {
        "method": "Serial paired rounds, seed637 shuffled order; two warmups discarded. "
                  "Guest thread CPU and monotonic clocks exclude startup, compilation "
                  "and teardown; CLI wall time includes them. Clock status and final "
                  "iteration count are checked by the guest. No concurrent builds/tests.",
        "measured_rounds": args.rounds,
        "binaries": {name: {"path": str(path), "sha256": digest(path)}
                     for name, path in binaries.items()},
        "results": [],
    }
    rng = random.Random(637)
    for workload, count in WORKLOADS:
        if args.workload is not None and workload != args.workload:
            continue
        fixture = Path(__file__).parent / (workload + ".wat")
        samples = {name: [] for name in binaries}
        row = {"workload": workload, "count": count,
               "fixture_sha256": digest(fixture), "samples": samples}
        for round_index in range(args.rounds + 2):
            order = list(binaries)
            rng.shuffle(order)
            for name in order:
                started = time.perf_counter()
                result = subprocess.run(
                    [str(binaries[name]), "run", str(fixture), "--invoke", "run",
                     "--arg", str(count)],
                    check=True, text=True, capture_output=True, timeout=60,
                )
                wall = time.perf_counter() - started
                elapsed, cpu = map(int, result.stdout.split())
                if elapsed <= 0 or cpu <= 0:
                    raise RuntimeError("Guest clocks returned a nonpositive interval")
                if round_index >= 2:
                    samples[name].append({"guest_ns": elapsed, "cpu_ns": cpu,
                                          "wall_s": wall})
        row["median"] = {
            name: {field: statistics.median(sample[field] for sample in values)
                   for field in ("guest_ns", "cpu_ns", "wall_s")}
            for name, values in samples.items()
        }
        report["results"].append(row)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(workload, count, row["median"], flush=True)


if __name__ == "__main__":
    main()
