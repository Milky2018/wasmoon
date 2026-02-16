#!/usr/bin/env python3
"""Benchmark examples/algorithms with cached Wasmtime baselines.

Perf-gap policy is one-sided by default: only regressions where Wasmoon is
slower than Wasmtime by more than threshold are flagged.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

NUMBER_RE = re.compile(r"[-+]?\d+(?:\.\d+)?")


@dataclass
class RunResult:
    command: List[str]
    exit_code: int
    duration_sec: float
    stdout: str
    stderr: str
    parsed_value: Optional[float]
    timeout: bool


def parse_first_number(output: str) -> Optional[float]:
    match = NUMBER_RE.search(output)
    if match is None:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def run_one(command: List[str], timeout_sec: int) -> RunResult:
    started = time.perf_counter()
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
    except subprocess.TimeoutExpired as exc:
        duration = time.perf_counter() - started
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        return RunResult(
            command=command,
            exit_code=124,
            duration_sec=duration,
            stdout=stdout,
            stderr=stderr,
            parsed_value=parse_first_number(stdout),
            timeout=True,
        )

    duration = time.perf_counter() - started
    return RunResult(
        command=command,
        exit_code=completed.returncode,
        duration_sec=duration,
        stdout=completed.stdout,
        stderr=completed.stderr,
        parsed_value=parse_first_number(completed.stdout),
        timeout=False,
    )


def load_json(path: Path) -> Dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def list_workloads(root: Path) -> List[Path]:
    return sorted(root.glob("*.wasm"))


def build_wasmtime_baseline(
    workloads: List[Path],
    wasmtime_bin: str,
    timeout_sec: int,
    iterations: int,
    warmup: int,
) -> Dict[str, Dict]:
    baseline: Dict[str, Dict] = {}
    for index, workload in enumerate(workloads, start=1):
        print(
            f"[baseline] {index}/{len(workloads)} {workload}",
            file=sys.stderr,
            flush=True,
        )
        cmd = [wasmtime_bin, "run", str(workload)]
        for _ in range(warmup):
            run_one(cmd, timeout_sec)
        runs = [run_one(cmd, timeout_sec) for _ in range(iterations)]
        ok_runs = [run for run in runs if run.exit_code == 0 and not run.timeout]
        durations = [run.duration_sec for run in ok_runs]
        parsed_values = [
            run.parsed_value for run in ok_runs if run.parsed_value is not None
        ]
        median_duration = median(durations)
        median_value = median(parsed_values)
        has_valid_median = median_duration is not None and median_value is not None
        baseline[str(workload)] = {
            "command": cmd,
            "iterations": iterations,
            "warmup": warmup,
            "ok_runs": len(ok_runs),
            "runs": [
                {
                    "exit_code": run.exit_code,
                    "timeout": run.timeout,
                    "duration_sec": run.duration_sec,
                    "parsed_value": run.parsed_value,
                    "stdout": run.stdout.strip(),
                    "stderr": run.stderr.strip(),
                }
                for run in runs
            ],
            "exit_code": 0 if has_valid_median else 1,
            "duration_sec": median_duration,
            "stdout": ok_runs[-1].stdout.strip() if ok_runs else "",
            "stderr": ok_runs[-1].stderr.strip() if ok_runs else "",
            "parsed_value": median_value,
            "timeout": all(run.timeout for run in runs),
            "generated_at_unix_sec": int(time.time()),
        }
    return baseline


def median(values: List[float]) -> Optional[float]:
    if not values:
        return None
    return float(statistics.median(values))


def pct_delta(observed: Optional[float], baseline: Optional[float]) -> Optional[float]:
    if observed is None or baseline is None:
        return None
    if baseline == 0.0:
        if observed == 0.0:
            return 0.0
        return float("inf") if observed > 0.0 else float("-inf")
    return ((observed - baseline) / baseline) * 100.0


def abs_delta(observed: Optional[float], baseline: Optional[float]) -> Optional[float]:
    if observed is None or baseline is None:
        return None
    return observed - baseline


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Benchmark wasmoon against cached wasmtime baselines for examples/algorithms."
        )
    )
    parser.add_argument("--wasmoon", default="./wasmoon")
    parser.add_argument("--wasmtime", default="wasmtime")
    parser.add_argument("--workloads-dir", default="examples/algorithms")
    parser.add_argument(
        "--baseline-file",
        default="target/perf-benchmarks/algorithms/wasmtime-baseline.json",
    )
    parser.add_argument(
        "--summary-file",
        default="target/perf-benchmarks/algorithms/wasmoon-vs-wasmtime-summary.json",
    )
    parser.add_argument("--markdown-file", default="")
    parser.add_argument("--timeout-sec", type=int, default=300)
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument("--baseline-iterations", type=int, default=3)
    parser.add_argument("--baseline-warmup", type=int, default=1)
    parser.add_argument(
        "--value-threshold-pct",
        type=float,
        default=5.0,
        help=(
            "Allowed positive delta percentage vs wasmtime parsed output value "
            "(one-sided: only slower-than-baseline is flagged)."
        ),
    )
    parser.add_argument(
        "--value-threshold-abs",
        type=float,
        default=50000.0,
        help=(
            "Allowed absolute positive delta vs wasmtime parsed output value; "
            "a perf gap is flagged only if both pct and abs thresholds are exceeded."
        ),
    )
    parser.add_argument(
        "--refresh-wasmtime-baseline",
        action="store_true",
        help="Rebuild baseline instead of reusing cached file.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return non-zero when failures or perf gaps exist.",
    )
    args = parser.parse_args()

    workloads = list_workloads(Path(args.workloads_dir))
    if not workloads:
        raise SystemExit(f"No wasm workloads found in {args.workloads_dir}")

    baseline_path = Path(args.baseline_file)
    if args.refresh_wasmtime_baseline or not baseline_path.exists():
        print(
            f"[baseline] building wasmtime cache for {len(workloads)} workloads",
            file=sys.stderr,
            flush=True,
        )
        baseline_payload = {
            "schema_version": 1,
            "generated_at_unix_sec": int(time.time()),
            "wasmtime": args.wasmtime,
            "workloads": build_wasmtime_baseline(
                workloads,
                args.wasmtime,
                args.timeout_sec,
                args.baseline_iterations,
                args.baseline_warmup,
            ),
        }
        save_json(baseline_path, baseline_payload)
        print(
            f"[baseline] wrote {baseline_path}",
            file=sys.stderr,
            flush=True,
        )
    else:
        baseline_payload = load_json(baseline_path)
        print(
            f"[baseline] using cached {baseline_path}",
            file=sys.stderr,
            flush=True,
        )

    baseline_workloads: Dict[str, Dict] = baseline_payload.get("workloads", {})
    rows: List[Dict] = []
    failures: List[str] = []
    perf_gaps: List[str] = []

    for index, workload in enumerate(workloads, start=1):
        workload_str = str(workload)
        print(
            f"[run] {index}/{len(workloads)} {workload_str}",
            file=sys.stderr,
            flush=True,
        )
        baseline_row = baseline_workloads.get(workload_str)
        if baseline_row is None:
            failures.append(f"{workload_str}: missing wasmtime baseline entry")
            continue

        baseline_ok = baseline_row.get("exit_code") == 0 and not baseline_row.get("timeout", False)
        if not baseline_ok:
            failures.append(f"{workload_str}: wasmtime baseline failed")
            rows.append(
                {
                    "workload": workload_str,
                    "status": "baseline_failed",
                    "baseline": baseline_row,
                }
            )
            continue

        for _ in range(args.warmup):
            run_one([args.wasmoon, "run", workload_str], args.timeout_sec)

        runs = [
            run_one([args.wasmoon, "run", workload_str], args.timeout_sec)
            for _ in range(args.iterations)
        ]

        ok_runs = [run for run in runs if run.exit_code == 0 and not run.timeout]
        durations = [run.duration_sec for run in ok_runs]
        parsed_values = [
            run.parsed_value for run in ok_runs if run.parsed_value is not None
        ]
        median_duration = median(durations)
        median_value = median(parsed_values)

        baseline_duration = baseline_row.get("duration_sec")
        baseline_value = baseline_row.get("parsed_value")
        value_delta_pct = pct_delta(median_value, baseline_value)
        value_delta_abs = abs_delta(median_value, baseline_value)
        wall_delta_pct = pct_delta(median_duration, baseline_duration)

        status = "ok"
        if not ok_runs:
            status = "runtime_error"
            failures.append(f"{workload_str}: wasmoon failed in all runs")
        elif value_delta_pct is None:
            status = "parse_error"
            failures.append(f"{workload_str}: unable to parse numeric output")
        elif (
            value_delta_pct > args.value_threshold_pct
            and value_delta_abs is not None
            and value_delta_abs > args.value_threshold_abs
        ):
            status = "perf_gap"
            perf_gaps.append(
                f"{workload_str}: value delta {value_delta_pct:.2f}% "
                f"(threshold {args.value_threshold_pct:.2f}%), "
                f"abs delta {value_delta_abs:.0f} "
                f"(threshold {args.value_threshold_abs:.0f})"
            )

        rows.append(
            {
                "workload": workload_str,
                "status": status,
                "wasmoon": {
                    "iterations": args.iterations,
                    "warmup": args.warmup,
                    "ok_runs": len(ok_runs),
                    "runs": [
                        {
                            "exit_code": run.exit_code,
                            "timeout": run.timeout,
                            "duration_sec": run.duration_sec,
                            "parsed_value": run.parsed_value,
                            "stdout": run.stdout.strip(),
                            "stderr": run.stderr.strip(),
                        }
                        for run in runs
                    ],
                    "median_duration_sec": median_duration,
                    "median_value": median_value,
                },
                "wasmtime_baseline": baseline_row,
                "value_delta_pct": value_delta_pct,
                "value_delta_abs": value_delta_abs,
                "wall_delta_pct": wall_delta_pct,
            }
        )
        print(
            f"[run] {workload_str} status={status} "
            f"value_delta_pct={'n/a' if value_delta_pct is None else f'{value_delta_pct:.2f}'}",
            file=sys.stderr,
            flush=True,
        )

    summary_payload = {
        "schema_version": 1,
        "generated_at_unix_sec": int(time.time()),
        "config": {
            "wasmoon": args.wasmoon,
            "wasmtime": args.wasmtime,
            "timeout_sec": args.timeout_sec,
            "iterations": args.iterations,
            "warmup": args.warmup,
            "value_threshold_pct": args.value_threshold_pct,
            "value_threshold_abs": args.value_threshold_abs,
            "baseline_file": str(baseline_path),
        },
        "stats": {
            "total": len(workloads),
            "failures": len(failures),
            "perf_gaps": len(perf_gaps),
            "ok": len([row for row in rows if row.get("status") == "ok"]),
        },
        "failures": failures,
        "perf_gaps": perf_gaps,
        "rows": rows,
    }

    summary_path = Path(args.summary_file)
    save_json(summary_path, summary_payload)

    markdown_path = Path(args.markdown_file) if args.markdown_file else summary_path.with_suffix(".md")
    md_lines = [
        "# Algorithms Benchmark: Wasmoon vs Wasmtime",
        "",
        f"- Baseline file: `{baseline_path}`",
        f"- Summary file: `{summary_path}`",
        f"- Total workloads: `{summary_payload['stats']['total']}`",
        f"- OK: `{summary_payload['stats']['ok']}`",
        f"- Failures: `{summary_payload['stats']['failures']}`",
        f"- Perf gaps: `{summary_payload['stats']['perf_gaps']}`",
        "",
        "| Workload | Status | Value Delta % | Value Delta Abs | Wall Delta % | Wasmoon Median Value | Wasmtime Value |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        value_delta = row.get("value_delta_pct")
        value_delta_abs = row.get("value_delta_abs")
        wall_delta = row.get("wall_delta_pct")
        wasmoon_median_value = row.get("wasmoon", {}).get("median_value")
        wasmtime_value = row.get("wasmtime_baseline", {}).get("parsed_value")
        md_lines.append(
            "| `{}` | {} | {} | {} | {} | {} | {} |".format(
                row.get("workload"),
                row.get("status"),
                "n/a" if value_delta is None else f"{value_delta:.2f}",
                "n/a" if value_delta_abs is None else f"{value_delta_abs:.0f}",
                "n/a" if wall_delta is None else f"{wall_delta:.2f}",
                "n/a" if wasmoon_median_value is None else f"{wasmoon_median_value:.2f}",
                "n/a" if wasmtime_value is None else f"{wasmtime_value:.2f}",
            )
        )
    if failures:
        md_lines.extend(["", "## Failures", ""])
        for entry in failures:
            md_lines.append(f"- {entry}")
    if perf_gaps:
        md_lines.extend(["", "## Perf Gaps", ""])
        for entry in perf_gaps:
            md_lines.append(f"- {entry}")
    markdown_path.write_text("\n".join(md_lines), encoding="utf-8")
    print(
        f"[done] summary={summary_path} failures={len(failures)} perf_gaps={len(perf_gaps)}",
        file=sys.stderr,
        flush=True,
    )

    if args.strict and (failures or perf_gaps):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
