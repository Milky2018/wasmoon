#!/usr/bin/env python3
"""Check Wasmoon runtime parity against Wasmtime on representative workloads."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import time
from pathlib import Path
from typing import Dict, List


DEFAULT_WORKLOADS = [
    "examples/aead_aegis128l.wasm",
    "examples/benchmark.wasm",
]

DEFAULT_THRESHOLDS = {
    "examples/aead_aegis128l.wasm": 6.0,
    "examples/benchmark.wasm": 1.5,
}


def run_once(binary: str, workload: str, timeout_sec: int) -> float:
    started = time.perf_counter()
    subprocess.run(
        [binary, "run", workload],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout_sec,
    )
    return time.perf_counter() - started


def median(values: List[float]) -> float:
    return float(statistics.median(values))


def parse_thresholds(raw: List[str]) -> Dict[str, float]:
    thresholds = DEFAULT_THRESHOLDS.copy()
    for item in raw:
        if "=" not in item:
            raise ValueError(f"invalid threshold override '{item}', expected path=value")
        workload, value = item.split("=", 1)
        thresholds[workload] = float(value)
    return thresholds


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check Wasmoon/Wasmtime runtime parity on fixed workloads.",
    )
    parser.add_argument("--wasmoon", default="./wasmoon", help="Path to wasmoon binary")
    parser.add_argument("--wasmtime", default="wasmtime", help="Path to wasmtime binary")
    parser.add_argument(
        "--workload",
        action="append",
        dest="workloads",
        help="Workload path (repeatable). Defaults to curated set.",
    )
    parser.add_argument(
        "--threshold",
        action="append",
        default=[],
        help="Override threshold with workload=ratio, e.g. examples/aead_aegis128l.wasm=5.5",
    )
    parser.add_argument("--iterations", type=int, default=5, help="Measured iterations")
    parser.add_argument("--warmup", type=int, default=1, help="Warmup iterations")
    parser.add_argument("--timeout-sec", type=int, default=300, help="Per-run timeout")
    parser.add_argument(
        "--out-dir",
        default="target/perf-benchmarks/parity",
        help="Output directory for parity report",
    )
    args = parser.parse_args()

    workloads = args.workloads if args.workloads else DEFAULT_WORKLOADS
    thresholds = parse_thresholds(args.threshold)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    summary = {
        "schema_version": 1,
        "generated_at_unix_sec": int(time.time()),
        "config": {
            "iterations": args.iterations,
            "warmup": args.warmup,
            "timeout_sec": args.timeout_sec,
            "wasmoon": args.wasmoon,
            "wasmtime": args.wasmtime,
        },
        "workloads": [],
    }

    failures: List[str] = []
    for workload in workloads:
        for _ in range(args.warmup):
            run_once(args.wasmoon, workload, args.timeout_sec)
            run_once(args.wasmtime, workload, args.timeout_sec)

        wasmoon_times = [
            run_once(args.wasmoon, workload, args.timeout_sec)
            for _ in range(args.iterations)
        ]
        wasmtime_times = [
            run_once(args.wasmtime, workload, args.timeout_sec)
            for _ in range(args.iterations)
        ]

        wasmoon_median = median(wasmoon_times)
        wasmtime_median = median(wasmtime_times)
        ratio = wasmoon_median / wasmtime_median if wasmtime_median > 0.0 else float("inf")
        threshold = thresholds.get(workload, 6.0)
        status = "ok" if ratio <= threshold else "regressed"
        if status != "ok":
            failures.append(
                f"{workload}: ratio {ratio:.4f}x exceeds threshold {threshold:.4f}x",
            )

        summary["workloads"].append(
            {
                "workload": workload,
                "wasmoon_times_sec": wasmoon_times,
                "wasmtime_times_sec": wasmtime_times,
                "wasmoon_median_sec": wasmoon_median,
                "wasmtime_median_sec": wasmtime_median,
                "ratio_vs_wasmtime": ratio,
                "threshold": threshold,
                "status": status,
            }
        )

    summary_path = out_dir / "wasmtime-parity-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    md_lines = [
        "# Wasmoon vs Wasmtime Parity",
        "",
        f"- Iterations: `{args.iterations}` (warmup `{args.warmup}`)",
        "",
        "| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for row in summary["workloads"]:
        md_lines.append(
            "| `{}` | {:.4f} | {:.4f} | {:.4f}x | {:.4f}x | {} |".format(
                row["workload"],
                row["wasmoon_median_sec"],
                row["wasmtime_median_sec"],
                row["ratio_vs_wasmtime"],
                row["threshold"],
                row["status"],
            )
        )
    if failures:
        md_lines.extend(["", "## Failures", ""])
        for failure in failures:
            md_lines.append(f"- {failure}")
    (out_dir / "wasmtime-parity-summary.md").write_text(
        "\n".join(md_lines),
        encoding="utf-8",
    )

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
