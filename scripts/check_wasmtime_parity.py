#!/usr/bin/env python3
"""Check Wasmoon runtime parity against Wasmtime on representative workloads."""

from __future__ import annotations

import argparse
import json
import os
import signal
import statistics
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional


DEFAULT_WORKLOADS = [
    "examples/aead_aegis128l.wasm",
    "examples/benchmark.wasm",
]

DEFAULT_THRESHOLDS = {
    "examples/aead_aegis128l.wasm": 6.0,
    "examples/benchmark.wasm": 1.5,
}


def detect_qemu_tcg() -> bool:
    cpuinfo = Path("/proc/cpuinfo")
    if not cpuinfo.exists():
        return False
    try:
        text = cpuinfo.read_text(encoding="utf-8", errors="ignore").lower()
    except OSError:
        return False
    return "qemu tcg" in text or "qemu virtual cpu" in text


def resolve_workload_path(workload: str) -> str:
    path = Path(workload)
    if path.exists():
        return workload
    if workload.startswith("examples/"):
        alt = Path("examples/algorithms") / path.name
        if alt.exists():
            return str(alt)
    return workload


def run_once(binary: str, workload: str, timeout_sec: int) -> Optional[float]:
    started = time.perf_counter()
    proc: subprocess.Popen[bytes] | None = None
    try:
        proc = subprocess.Popen(
            [binary, "run", workload],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except FileNotFoundError:
        return None
    try:
        exit_code = proc.wait(timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            # Keep moving even if the kernel keeps the process in uninterruptible
            # sleep for a while (common under nested emulation).
            pass
        return None
    if exit_code != 0:
        return None
    return time.perf_counter() - started


def median(values: List[float]) -> Optional[float]:
    if not values:
        return None
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
    parser.add_argument(
        "--qemu-threshold-multiplier",
        type=float,
        default=3.0,
        help="Threshold multiplier when running under QEMU TCG outside CI",
    )
    parser.add_argument(
        "--no-qemu-relax",
        action="store_true",
        help="Disable automatic threshold relaxation on local QEMU TCG runs",
    )
    parser.add_argument(
        "--prime-wasmoon-cache",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Prime Wasmoon cache before warmup to avoid compile-time timeouts",
    )
    parser.add_argument(
        "--prime-timeout-sec",
        type=int,
        default=360,
        help="Timeout for cache priming runs",
    )
    args = parser.parse_args()

    workloads = args.workloads if args.workloads else DEFAULT_WORKLOADS
    thresholds = parse_thresholds(args.threshold)
    running_in_ci = os.getenv("CI", "").strip().lower() in {"1", "true", "yes"}
    running_on_qemu_tcg = detect_qemu_tcg()
    relax_thresholds = (
        running_on_qemu_tcg
        and not running_in_ci
        and not args.no_qemu_relax
        and args.qemu_threshold_multiplier > 1.0
    )
    effective_thresholds = thresholds.copy()
    if relax_thresholds:
        effective_thresholds = {
            workload: value * args.qemu_threshold_multiplier
            for workload, value in thresholds.items()
        }
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
            "running_in_ci": running_in_ci,
            "running_on_qemu_tcg": running_on_qemu_tcg,
            "qemu_relax_enabled": relax_thresholds,
            "qemu_threshold_multiplier": args.qemu_threshold_multiplier,
            "prime_wasmoon_cache": args.prime_wasmoon_cache,
            "prime_wasmoon_cache_effective": args.prime_wasmoon_cache and relax_thresholds,
            "prime_timeout_sec": args.prime_timeout_sec,
        },
        "workloads": [],
    }

    failures: List[str] = []
    for workload in workloads:
        resolved_workload = resolve_workload_path(workload)
        threshold = effective_thresholds.get(workload, 6.0)
        if not Path(resolved_workload).exists():
            failures.append(f"{workload}: workload file not found")
            summary["workloads"].append(
                {
                    "workload": workload,
                    "resolved_workload": resolved_workload,
                    "status": "missing-workload",
                    "threshold": threshold,
                }
            )
            continue
        should_prime = args.prime_wasmoon_cache and relax_thresholds
        if should_prime:
            # Compilation can dominate on large modules in emulated environments.
            # Prime once with a longer timeout so measured runs are execution-focused.
            _ = run_once(
                args.wasmoon,
                resolved_workload,
                max(args.timeout_sec, min(args.prime_timeout_sec, args.timeout_sec * 2)),
            )
        warmup_error = False
        for _ in range(args.warmup):
            warm_wasmoon = run_once(args.wasmoon, resolved_workload, args.timeout_sec)
            warm_wasmtime = run_once(args.wasmtime, resolved_workload, args.timeout_sec)
            if warm_wasmoon is None or warm_wasmtime is None:
                warmup_error = True
                break

        wasmoon_times: List[float] = []
        wasmtime_times: List[float] = []
        run_error: Optional[str] = None
        if not warmup_error:
            for _ in range(args.iterations):
                value = run_once(args.wasmoon, resolved_workload, args.timeout_sec)
                if value is None:
                    run_error = "wasmoon run timed out or failed"
                    break
                wasmoon_times.append(value)
        else:
            run_error = "warmup timed out or failed"

        if run_error is None:
            for _ in range(args.iterations):
                value = run_once(args.wasmtime, resolved_workload, args.timeout_sec)
                if value is None:
                    run_error = "wasmtime run timed out or failed"
                    break
                wasmtime_times.append(value)

        if run_error is not None:
            status = "error"
            if relax_thresholds and "timed out" in run_error:
                status = "qemu-timeout"
            else:
                failures.append(f"{workload}: {run_error}")
            summary["workloads"].append(
                {
                    "workload": workload,
                    "resolved_workload": resolved_workload,
                    "wasmoon_times_sec": wasmoon_times,
                    "wasmtime_times_sec": wasmtime_times,
                    "wasmoon_median_sec": median(wasmoon_times),
                    "wasmtime_median_sec": median(wasmtime_times),
                    "ratio_vs_wasmtime": None,
                    "threshold": threshold,
                    "status": status,
                }
            )
            continue

        wasmoon_median = median(wasmoon_times)
        wasmtime_median = median(wasmtime_times)
        if wasmoon_median is None or wasmtime_median is None:
            failures.append(f"{workload}: no successful measurement")
            summary["workloads"].append(
                {
                    "workload": workload,
                    "resolved_workload": resolved_workload,
                    "wasmoon_times_sec": wasmoon_times,
                    "wasmtime_times_sec": wasmtime_times,
                    "wasmoon_median_sec": wasmoon_median,
                    "wasmtime_median_sec": wasmtime_median,
                    "ratio_vs_wasmtime": None,
                    "threshold": threshold,
                    "status": "error",
                }
            )
            continue
        ratio = wasmoon_median / wasmtime_median if wasmtime_median > 0.0 else float("inf")
        status = "ok" if ratio <= threshold else "regressed"
        if status != "ok":
            failures.append(
                f"{workload}: ratio {ratio:.4f}x exceeds threshold {threshold:.4f}x",
            )

        summary["workloads"].append(
            {
                "workload": workload,
                "resolved_workload": resolved_workload,
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
        f"- QEMU relax: `{'on' if relax_thresholds else 'off'}`"
        + (
            f" (`x{args.qemu_threshold_multiplier:.2f}` multiplier)"
            if relax_thresholds
            else ""
        ),
        "",
        "| Workload | Wasmoon median (s) | Wasmtime median (s) | Ratio | Threshold | Status |",
        "|---|---:|---:|---:|---:|---|",
    ]
    def fmt_num(value: Optional[float]) -> str:
        return "-" if value is None else f"{value:.4f}"

    def fmt_ratio(value: Optional[float]) -> str:
        return "-" if value is None else f"{value:.4f}x"

    for row in summary["workloads"]:
        md_lines.append(
            "| `{}` | {} | {} | {} | {} | {} |".format(
                row["workload"],
                fmt_num(row.get("wasmoon_median_sec")),
                fmt_num(row.get("wasmtime_median_sec")),
                fmt_ratio(row.get("ratio_vs_wasmtime")),
                fmt_ratio(row.get("threshold")),
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
