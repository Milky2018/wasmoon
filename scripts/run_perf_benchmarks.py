#!/usr/bin/env python3
"""Run repeatable Wasmoon perf benchmarks and optional regression checks."""

from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple


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


def _parse_metrics(metrics_file: Path) -> Tuple[int | None, int | None]:
    if not metrics_file.exists():
        return None, None
    try:
        payload = json.loads(metrics_file.read_text(encoding="utf-8"))
    except Exception:
        return None, None
    module_compile_us = payload.get("module_compile_us")
    compile_us = int(module_compile_us) if module_compile_us is not None else None
    total_code_size = 0
    for func in payload.get("functions", []):
        total_code_size += int(func.get("code_size", 0))
    return compile_us, total_code_size


def _run_one(
    wasmoon_bin: str,
    subcommand: str,
    workload: str,
    out_dir: Path,
    timeout_sec: int,
    run_id: int,
    warmup: bool,
) -> Dict[str, Any]:
    stem = _sanitize_name(workload)
    suffix = f"warmup{run_id}" if warmup else f"run{run_id}"
    metrics_file = out_dir / "raw" / f"{stem}.{suffix}.metrics.json"
    stdout_file = out_dir / "raw" / f"{stem}.{suffix}.stdout.log"
    stderr_file = out_dir / "raw" / f"{stem}.{suffix}.stderr.log"
    metrics_file.parent.mkdir(parents=True, exist_ok=True)

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
    compile_us, total_code_size = _parse_metrics(metrics_file)

    return {
        "workload": workload,
        "run_id": run_id,
        "warmup": warmup,
        "exit_code": proc.returncode,
        "elapsed_ms": elapsed_ms,
        "module_compile_us": compile_us,
        "total_code_size": total_code_size,
        "metrics_file": str(metrics_file),
        "stdout_file": str(stdout_file),
        "stderr_file": str(stderr_file),
        "metrics_present": metrics_file.exists(),
    }


def _median(values: List[int]) -> int | None:
    if not values:
        return None
    return int(statistics.median(values))


def _aggregate_runs(runs: List[Dict[str, Any]]) -> Dict[str, int | None]:
    elapsed = [int(r["elapsed_ms"]) for r in runs]
    compile_us = [
        int(r["module_compile_us"])
        for r in runs
        if r.get("module_compile_us") is not None
    ]
    code_size = [
        int(r["total_code_size"])
        for r in runs
        if r.get("total_code_size") is not None
    ]
    return {
        "elapsed_ms_median": _median(elapsed),
        "module_compile_us_median": _median(compile_us),
        "total_code_size_median": _median(code_size),
    }


def _load_baseline(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _regression_percent(current: int | None, baseline: int | None) -> float | None:
    if current is None or baseline is None or baseline <= 0:
        return None
    return ((current - baseline) / baseline) * 100.0


def _compare_with_baseline(
    summary: Dict[str, Any],
    baseline: Dict[str, Any],
    threshold_elapsed_pct: float,
    threshold_compile_pct: float,
    threshold_code_size_pct: float,
    require_arch_match: bool,
) -> Tuple[List[Dict[str, Any]], List[str]]:
    findings: List[Dict[str, Any]] = []
    failures: List[str] = []

    if require_arch_match:
        cur_arch = summary.get("host", {}).get("machine", "")
        base_arch = baseline.get("host", {}).get("machine", "")
        if cur_arch and base_arch and cur_arch != base_arch:
            failures.append(
                f"Baseline arch mismatch: current={cur_arch}, baseline={base_arch}"
            )
            return findings, failures

    baseline_rows = {
        row["workload"]: row for row in baseline.get("workloads", []) if "workload" in row
    }
    for row in summary.get("workloads", []):
        workload = row["workload"]
        if workload not in baseline_rows:
            findings.append(
                {
                    "workload": workload,
                    "status": "missing-baseline",
                    "message": "No baseline entry",
                }
            )
            continue
        current_agg = row.get("aggregates", {})
        baseline_agg = baseline_rows[workload].get("aggregates", {})

        elapsed_reg = _regression_percent(
            current_agg.get("elapsed_ms_median"),
            baseline_agg.get("elapsed_ms_median"),
        )
        compile_reg = _regression_percent(
            current_agg.get("module_compile_us_median"),
            baseline_agg.get("module_compile_us_median"),
        )
        code_size_reg = _regression_percent(
            current_agg.get("total_code_size_median"),
            baseline_agg.get("total_code_size_median"),
        )

        status = "ok"
        if elapsed_reg is not None and elapsed_reg > threshold_elapsed_pct:
            status = "regressed"
            failures.append(
                f"{workload}: elapsed regression {elapsed_reg:.2f}% > {threshold_elapsed_pct:.2f}%"
            )
        if compile_reg is not None and compile_reg > threshold_compile_pct:
            status = "regressed"
            failures.append(
                f"{workload}: compile regression {compile_reg:.2f}% > {threshold_compile_pct:.2f}%"
            )
        if code_size_reg is not None and code_size_reg > threshold_code_size_pct:
            status = "regressed"
            failures.append(
                f"{workload}: code-size regression {code_size_reg:.2f}% > {threshold_code_size_pct:.2f}%"
            )

        findings.append(
            {
                "workload": workload,
                "status": status,
                "elapsed_regression_pct": elapsed_reg,
                "compile_regression_pct": compile_reg,
                "code_size_regression_pct": code_size_reg,
            }
        )
    return findings, failures


def _write_markdown(summary: Dict[str, Any], out_path: Path) -> None:
    lines = [
        "# Wasmoon Perf Benchmark Summary",
        "",
        f"- Generated at: `{summary['generated_at_unix_sec']}`",
        f"- Host: `{summary['host']['system']} / {summary['host']['machine']}`",
        f"- Iterations: `{summary['config']['iterations']}` (warmup `{summary['config']['warmup']}`)",
        "",
        "| Workload | Exit Failures | Elapsed Median (ms) | Compile Median (us) | Code Size Median (bytes) |",
        "|---|---:|---:|---:|---:|",
    ]
    for row in summary["workloads"]:
        agg = row["aggregates"]
        lines.append(
            f"| `{row['workload']}` | {row['num_failed_runs']} | "
            f"{agg.get('elapsed_ms_median')} | {agg.get('module_compile_us_median')} | {agg.get('total_code_size_median')} |"
        )

    compare = summary.get("comparison")
    if compare:
        lines.extend(
            [
                "",
                "## Baseline Comparison",
                "",
                "| Workload | Status | Elapsed Δ% | Compile Δ% | Code Size Δ% |",
                "|---|---|---:|---:|---:|",
            ]
        )
        for item in compare["findings"]:
            if item["status"] == "missing-baseline":
                lines.append(
                    f"| `{item['workload']}` | missing-baseline | - | - | - |"
                )
            else:
                def fmt(v: float | None) -> str:
                    return "-" if v is None else f"{v:.2f}"

                lines.append(
                    f"| `{item['workload']}` | {item['status']} | "
                    f"{fmt(item.get('elapsed_regression_pct'))} | "
                    f"{fmt(item.get('compile_regression_pct'))} | "
                    f"{fmt(item.get('code_size_regression_pct'))} |"
                )
        if compare["failures"]:
            lines.extend(["", "### Regression Failures", ""])
            for failure in compare["failures"]:
                lines.append(f"- {failure}")

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run repeatable Wasmoon perf benchmarks and check thresholds."
    )
    parser.add_argument("--wasmoon", default="./wasmoon")
    parser.add_argument("--out-dir", default="target/perf-benchmarks/latest")
    parser.add_argument("--subcommand", choices=["run", "test"], default="run")
    parser.add_argument("--workload", action="append", dest="workloads")
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--timeout-sec", type=int, default=180)
    parser.add_argument("--baseline", help="Optional baseline summary.json path")
    parser.add_argument("--threshold-elapsed-pct", type=float, default=15.0)
    parser.add_argument("--threshold-compile-pct", type=float, default=15.0)
    parser.add_argument("--threshold-code-size-pct", type=float, default=5.0)
    parser.add_argument(
        "--allow-arch-mismatch",
        action="store_true",
        help="Allow baseline comparison across different host.machine values",
    )
    args = parser.parse_args()

    workloads = args.workloads or (
        DEFAULT_RUN_WORKLOADS
        if args.subcommand == "run"
        else DEFAULT_TEST_WORKLOADS
    )

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    workload_rows: List[Dict[str, Any]] = []
    collection_failures: List[str] = []
    for workload in workloads:
        raw_runs: List[Dict[str, Any]] = []
        for run_id in range(args.warmup):
            raw_runs.append(
                _run_one(
                    args.wasmoon,
                    args.subcommand,
                    workload,
                    out_dir,
                    args.timeout_sec,
                    run_id,
                    warmup=True,
                )
            )
        measured_runs: List[Dict[str, Any]] = []
        for run_id in range(args.iterations):
            run = _run_one(
                args.wasmoon,
                args.subcommand,
                workload,
                out_dir,
                args.timeout_sec,
                run_id,
                warmup=False,
            )
            raw_runs.append(run)
            measured_runs.append(run)
            if run["exit_code"] != 0 or not run["metrics_present"]:
                collection_failures.append(
                    f"{workload}: run {run_id} failed (exit={run['exit_code']}, metrics={run['metrics_present']})"
                )
        workload_rows.append(
            {
                "workload": workload,
                "num_runs": args.iterations,
                "num_failed_runs": sum(
                    1
                    for r in measured_runs
                    if r["exit_code"] != 0 or not r["metrics_present"]
                ),
                "aggregates": _aggregate_runs(measured_runs),
                "runs": raw_runs,
            }
        )

    summary: Dict[str, Any] = {
        "schema_version": 1,
        "generated_at_unix_sec": int(time.time()),
        "host": {
            "system": platform.system(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "config": {
            "wasmoon": args.wasmoon,
            "subcommand": args.subcommand,
            "iterations": args.iterations,
            "warmup": args.warmup,
            "timeout_sec": args.timeout_sec,
            "threshold_elapsed_pct": args.threshold_elapsed_pct,
            "threshold_compile_pct": args.threshold_compile_pct,
            "threshold_code_size_pct": args.threshold_code_size_pct,
        },
        "workloads": workload_rows,
    }

    if args.baseline:
        baseline_path = Path(args.baseline)
        if baseline_path.exists():
            baseline = _load_baseline(baseline_path)
            findings, failures = _compare_with_baseline(
                summary,
                baseline,
                args.threshold_elapsed_pct,
                args.threshold_compile_pct,
                args.threshold_code_size_pct,
                require_arch_match=not args.allow_arch_mismatch,
            )
            summary["comparison"] = {
                "baseline": str(baseline_path),
                "findings": findings,
                "failures": failures,
            }
        else:
            summary["comparison"] = {
                "baseline": str(baseline_path),
                "findings": [],
                "failures": [f"Baseline file not found: {baseline_path}"],
            }

    (out_dir / "summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    _write_markdown(summary, out_dir / "summary.md")

    if collection_failures:
        for failure in collection_failures:
            print(f"[collect-failure] {failure}")
        return 1
    if summary.get("comparison", {}).get("failures"):
        for failure in summary["comparison"]["failures"]:
            print(f"[regression-failure] {failure}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
