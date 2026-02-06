#!/usr/bin/env python3
"""Collect compile-time performance baseline artifacts for wasmoon JIT."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from pathlib import Path
from typing import List


DEFAULT_RUN_WORKLOADS = [
    "examples/core3.wasm",
    "examples/benchmark.wasm",
    "examples/stream.wasm",
    "examples/box_easy2.wasm",
]

DEFAULT_TEST_WORKLOADS = [
    "spec/const.wast",
    "spec/int_exprs.wast",
    "spec/float_exprs.wast",
]


def _sanitize_name(path: str) -> str:
    return path.replace("/", "__").replace("\\", "__")


def _run_one(
    wasmoon_bin: str,
    subcommand: str,
    workload: str,
    out_dir: Path,
    timeout_sec: int,
) -> dict:
    metrics_file = out_dir / f"{_sanitize_name(workload)}.metrics.json"
    stdout_file = out_dir / f"{_sanitize_name(workload)}.stdout.log"
    stderr_file = out_dir / f"{_sanitize_name(workload)}.stderr.log"

    env = os.environ.copy()
    env["WASMOON_PERF_METRICS"] = "1"
    env["WASMOON_PERF_METRICS_FILE"] = str(metrics_file)

    cmd = [wasmoon_bin, subcommand, workload]
    started = time.time()
    with stdout_file.open("w", encoding="utf-8") as stdout, stderr_file.open(
        "w", encoding="utf-8"
    ) as stderr:
        proc = subprocess.run(
            cmd,
            env=env,
            stdout=stdout,
            stderr=stderr,
            timeout=timeout_sec,
            check=False,
        )
    elapsed_ms = int((time.time() - started) * 1000)

    return {
        "workload": workload,
        "command": cmd,
        "exit_code": proc.returncode,
        "elapsed_ms": elapsed_ms,
        "metrics_file": str(metrics_file),
        "stdout_file": str(stdout_file),
        "stderr_file": str(stderr_file),
        "metrics_present": metrics_file.exists(),
    }


def _write_markdown_summary(
    results: List[dict], summary_path: Path, subcommand: str
) -> None:
    lines = [
        "# Wasmoon Perf Baseline Summary",
        "",
        f"- Subcommand: `{subcommand}`",
        "",
        "| Workload | Exit | Elapsed (ms) | Metrics |",
        "|---|---:|---:|---|",
    ]
    for item in results:
        lines.append(
            f"| `{item['workload']}` | {item['exit_code']} | {item['elapsed_ms']} | "
            f"`{Path(item['metrics_file']).name}` ({'yes' if item['metrics_present'] else 'no'}) |"
        )
    lines.append("")
    summary_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect wasmoon JIT compile metrics baselines."
    )
    parser.add_argument(
        "--wasmoon",
        default="./wasmoon",
        help="Path to wasmoon binary (default: ./wasmoon)",
    )
    parser.add_argument(
        "--out-dir",
        default="docs/perf/baselines/latest",
        help="Output directory for metrics/logs",
    )
    parser.add_argument(
        "--timeout-sec",
        type=int,
        default=120,
        help="Timeout per workload command",
    )
    parser.add_argument(
        "--subcommand",
        choices=["run", "test"],
        default="run",
        help="wasmoon subcommand to execute per workload",
    )
    parser.add_argument(
        "--workload",
        action="append",
        dest="workloads",
        help="Workload path (repeatable). Default uses a small curated set.",
    )
    args = parser.parse_args()

    if args.workloads:
        workloads = args.workloads
    else:
        workloads = (
            DEFAULT_RUN_WORKLOADS
            if args.subcommand == "run"
            else DEFAULT_TEST_WORKLOADS
        )
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    results: List[dict] = []
    for workload in workloads:
        results.append(
            _run_one(
                wasmoon_bin=args.wasmoon,
                subcommand=args.subcommand,
                workload=workload,
                out_dir=out_dir,
                timeout_sec=args.timeout_sec,
            )
        )

    summary_json = {
        "schema_version": 1,
        "generated_at_unix_sec": int(time.time()),
        "wasmoon": args.wasmoon,
        "subcommand": args.subcommand,
        "workloads": workloads,
        "results": results,
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary_json, indent=2), encoding="utf-8"
    )
    _write_markdown_summary(results, out_dir / "summary.md", args.subcommand)

    has_failure = any(item["exit_code"] != 0 for item in results)
    has_missing_metrics = any(not item["metrics_present"] for item in results)
    if has_failure or has_missing_metrics:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
