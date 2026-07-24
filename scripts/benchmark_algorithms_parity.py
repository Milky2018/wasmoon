#!/usr/bin/env python3
"""Run paired, cache-isolated Wasmoon/Wasmtime algorithm benchmarks."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence

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
    freshly_compiled: Optional[bool] = None
    cache_files_before: List[str] = field(default_factory=list)
    cache_files_after: List[str] = field(default_factory=list)


def parse_first_number(output: str) -> Optional[float]:
    match = NUMBER_RE.search(output)
    if match is None:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def run_one(
    command: List[str],
    timeout_sec: int,
    *,
    extra_env: Optional[Dict[str, str]] = None,
) -> RunResult:
    started = time.perf_counter()
    env = None
    if extra_env:
        env = os.environ.copy()
        env.update(extra_env)
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            env=env,
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


def save_json(path: Path, payload: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def list_workloads(root: Path) -> List[Path]:
    return sorted(root.glob("*.wasm"))


def median(values: Sequence[float]) -> Optional[float]:
    if not values:
        return None
    return float(statistics.median(values))


def geometric_mean(values: Sequence[float]) -> Optional[float]:
    if not values or any(value <= 0.0 for value in values):
        return None
    return math.exp(sum(math.log(value) for value in values) / len(values))


def ratio(numerator: Optional[float], denominator: Optional[float]) -> Optional[float]:
    if numerator is None or denominator is None:
        return None
    if denominator == 0.0:
        if numerator == 0.0:
            return 1.0
        return float("inf") if numerator > 0.0 else float("-inf")
    return numerator / denominator


def paired_ratio_summary(values: Sequence[float]) -> Dict[str, Optional[float]]:
    return {
        "count": len(values),
        "median": median(values),
        "geometric_mean": geometric_mean(values),
    }


def pair_engine_order(pair_index: int) -> List[str]:
    if pair_index % 2 == 0:
        return ["wasmoon", "wasmtime"]
    return ["wasmtime", "wasmoon"]


def sanitized_workload_name(workload: Path) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", workload.stem)


def prepare_isolated_cache(cache_root: Path, workload: Path) -> Path:
    cache_dir = cache_root / sanitized_workload_name(workload)
    if cache_dir.exists():
        shutil.rmtree(cache_dir)
    cache_dir.mkdir(parents=True)
    return cache_dir


def cache_snapshot(cache_dir: Path) -> Dict[str, tuple[int, int]]:
    snapshot: Dict[str, tuple[int, int]] = {}
    for path in sorted(cache_dir.glob("**/*")):
        if path.is_file():
            stat = path.stat()
            snapshot[str(path.relative_to(cache_dir))] = (
                stat.st_size,
                stat.st_mtime_ns,
            )
    return snapshot


def run_wasmoon(
    command: List[str],
    timeout_sec: int,
    cache_dir: Path,
) -> RunResult:
    before = cache_snapshot(cache_dir)
    result = run_one(
        command,
        timeout_sec,
        extra_env={"WASMOON_JIT_CACHE_DIR": str(cache_dir)},
    )
    after = cache_snapshot(cache_dir)
    result.freshly_compiled = any(
        name not in before or before[name] != metadata
        for name, metadata in after.items()
    )
    result.cache_files_before = sorted(before)
    result.cache_files_after = sorted(after)
    return result


def run_payload(result: RunResult) -> Dict:
    payload = {
        "command": result.command,
        "exit_code": result.exit_code,
        "timeout": result.timeout,
        "duration_sec": result.duration_sec,
        "parsed_value": result.parsed_value,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }
    if result.freshly_compiled is not None:
        payload.update(
            {
                "freshly_compiled": result.freshly_compiled,
                "cache_files_before": result.cache_files_before,
                "cache_files_after": result.cache_files_after,
            }
        )
    return payload


def successful(result: RunResult) -> bool:
    return result.exit_code == 0 and not result.timeout


def run_engine(
    engine: str,
    workload: Path,
    *,
    wasmoon_bin: str,
    wasmtime_bin: str,
    timeout_sec: int,
    cache_dir: Path,
) -> RunResult:
    if engine == "wasmoon":
        return run_wasmoon(
            [wasmoon_bin, "run", str(workload)],
            timeout_sec,
            cache_dir,
        )
    return run_one([wasmtime_bin, "run", str(workload)], timeout_sec)


def run_pair(
    pair_index: int,
    workload: Path,
    *,
    wasmoon_bin: str,
    wasmtime_bin: str,
    timeout_sec: int,
    cache_dir: Path,
) -> Dict:
    results: Dict[str, RunResult] = {}
    order = pair_engine_order(pair_index)
    for engine in order:
        results[engine] = run_engine(
            engine,
            workload,
            wasmoon_bin=wasmoon_bin,
            wasmtime_bin=wasmtime_bin,
            timeout_sec=timeout_sec,
            cache_dir=cache_dir,
        )
    wasmoon = results["wasmoon"]
    wasmtime = results["wasmtime"]
    pair_value_ratio = None
    pair_wall_ratio = None
    if successful(wasmoon) and successful(wasmtime):
        pair_value_ratio = ratio(wasmoon.parsed_value, wasmtime.parsed_value)
        pair_wall_ratio = ratio(wasmoon.duration_sec, wasmtime.duration_sec)
    return {
        "index": pair_index,
        "order": order,
        "wasmoon": run_payload(wasmoon),
        "wasmtime": run_payload(wasmtime),
        "value_ratio": pair_value_ratio,
        "wall_ratio": pair_wall_ratio,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run paired Wasmoon/Wasmtime samples for examples/algorithms."
        )
    )
    parser.add_argument("--wasmoon", default="./wasmoon")
    parser.add_argument("--wasmtime", default="wasmtime")
    parser.add_argument("--workloads-dir", default="examples/algorithms")
    parser.add_argument(
        "--summary-file",
        default="target/perf-benchmarks/algorithms/wasmoon-vs-wasmtime-summary.json",
    )
    parser.add_argument("--markdown-file", default="")
    parser.add_argument("--timeout-sec", type=int, default=300)
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--warmup", type=int, default=1)
    parser.add_argument(
        "--value-ratio-threshold",
        type=float,
        default=1.05,
        help="Allowed one-sided paired median output ratio.",
    )
    parser.add_argument(
        "--wall-ratio-threshold",
        type=float,
        default=2.0,
        help="Allowed one-sided paired median wall-time ratio.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return non-zero when failures or performance gaps exist.",
    )
    args = parser.parse_args()

    if args.iterations <= 0:
        raise SystemExit("--iterations must be positive")
    if args.warmup < 0:
        raise SystemExit("--warmup must be non-negative")

    workloads = list_workloads(Path(args.workloads_dir))
    if not workloads:
        raise SystemExit(f"No wasm workloads found in {args.workloads_dir}")

    summary_path = Path(args.summary_file)
    cache_root = summary_path.parent / "jit-cache"
    rows: List[Dict] = []
    failures: List[str] = []
    perf_gaps: List[str] = []

    for workload_index, workload in enumerate(workloads, start=1):
        workload_str = str(workload)
        print(
            f"[run] {workload_index}/{len(workloads)} {workload_str}",
            file=sys.stderr,
            flush=True,
        )
        cache_dir = prepare_isolated_cache(cache_root, workload)
        warmup_runs: List[Dict] = []
        for warmup_index in range(args.warmup):
            order = pair_engine_order(warmup_index)
            warmup_results = {}
            for engine in order:
                warmup_results[engine] = run_payload(
                    run_engine(
                        engine,
                        workload,
                        wasmoon_bin=args.wasmoon,
                        wasmtime_bin=args.wasmtime,
                        timeout_sec=args.timeout_sec,
                        cache_dir=cache_dir,
                    )
                )
            warmup_runs.append(
                {
                    "index": warmup_index,
                    "order": order,
                    "wasmoon": warmup_results["wasmoon"],
                    "wasmtime": warmup_results["wasmtime"],
                }
            )

        pairs = [
            run_pair(
                pair_index,
                workload,
                wasmoon_bin=args.wasmoon,
                wasmtime_bin=args.wasmtime,
                timeout_sec=args.timeout_sec,
                cache_dir=cache_dir,
            )
            for pair_index in range(args.iterations)
        ]
        valid_pairs = [
            pair
            for pair in pairs
            if pair["value_ratio"] is not None and pair["wall_ratio"] is not None
        ]
        value_ratios = [pair["value_ratio"] for pair in valid_pairs]
        wall_ratios = [pair["wall_ratio"] for pair in valid_pairs]
        value_summary = paired_ratio_summary(value_ratios)
        wall_summary = paired_ratio_summary(wall_ratios)

        status = "ok"
        if len(valid_pairs) != args.iterations:
            status = "runtime_error"
            failures.append(
                f"{workload_str}: {len(valid_pairs)}/{args.iterations} valid pairs"
            )
        elif (
            value_summary["median"] is not None
            and value_summary["median"] > args.value_ratio_threshold
        ):
            status = "perf_gap"
            perf_gaps.append(
                f"{workload_str}: paired output ratio "
                f"{value_summary['median']:.4f} "
                f"(threshold {args.value_ratio_threshold:.4f})"
            )
        elif (
            wall_summary["median"] is not None
            and wall_summary["median"] > args.wall_ratio_threshold
        ):
            status = "perf_gap"
            perf_gaps.append(
                f"{workload_str}: paired wall ratio "
                f"{wall_summary['median']:.4f} "
                f"(threshold {args.wall_ratio_threshold:.4f})"
            )

        wasmoon_runs = [pair["wasmoon"] for pair in pairs]
        wasmtime_runs = [pair["wasmtime"] for pair in pairs]
        row = {
            "workload": workload_str,
            "status": status,
            "cache": {
                "directory": str(cache_dir),
                "isolated": True,
                "warmup_fresh_compilations": sum(
                    1
                    for warmup_run in warmup_runs
                    if warmup_run["wasmoon"].get("freshly_compiled")
                ),
                "measured_fresh_compilations": sum(
                    1
                    for run in wasmoon_runs
                    if run.get("freshly_compiled")
                ),
                "final_files": sorted(cache_snapshot(cache_dir)),
            },
            "warmups": warmup_runs,
            "pairs": pairs,
            "paired_ratios": {
                "value": value_summary,
                "wall": wall_summary,
            },
            "engine_medians": {
                "wasmoon_value": median(
                    [
                        run["parsed_value"]
                        for run in wasmoon_runs
                        if run["parsed_value"] is not None
                    ]
                ),
                "wasmtime_value": median(
                    [
                        run["parsed_value"]
                        for run in wasmtime_runs
                        if run["parsed_value"] is not None
                    ]
                ),
                "wasmoon_wall_sec": median(
                    [run["duration_sec"] for run in wasmoon_runs]
                ),
                "wasmtime_wall_sec": median(
                    [run["duration_sec"] for run in wasmtime_runs]
                ),
            },
        }
        rows.append(row)
        print(
            f"[run] {workload_str} status={status} "
            f"value_ratio={value_summary['median']} "
            f"wall_ratio={wall_summary['median']}",
            file=sys.stderr,
            flush=True,
        )

    summary_payload = {
        "schema_version": 2,
        "generated_at_unix_sec": int(time.time()),
        "config": {
            "wasmoon": args.wasmoon,
            "wasmtime": args.wasmtime,
            "timeout_sec": args.timeout_sec,
            "iterations": args.iterations,
            "warmup": args.warmup,
            "value_ratio_threshold": args.value_ratio_threshold,
            "wall_ratio_threshold": args.wall_ratio_threshold,
            "cache_root": str(cache_root),
        },
        "stats": {
            "total": len(workloads),
            "failures": len(failures),
            "perf_gaps": len(perf_gaps),
            "ok": sum(row["status"] == "ok" for row in rows),
        },
        "failures": failures,
        "perf_gaps": perf_gaps,
        "rows": rows,
    }
    save_json(summary_path, summary_payload)

    markdown_path = (
        Path(args.markdown_file)
        if args.markdown_file
        else summary_path.with_suffix(".md")
    )
    md_lines = [
        "# Algorithms Benchmark: Wasmoon vs Wasmtime",
        "",
        f"- Summary file: `{summary_path}`",
        f"- Isolated cache root: `{cache_root}`",
        f"- Total workloads: `{summary_payload['stats']['total']}`",
        f"- OK: `{summary_payload['stats']['ok']}`",
        f"- Failures: `{summary_payload['stats']['failures']}`",
        f"- Perf gaps: `{summary_payload['stats']['perf_gaps']}`",
        "",
        "| Workload | Status | Value Median | Value Geomean | Wall Median | Wall Geomean | Fresh Measured Compiles |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        value = row["paired_ratios"]["value"]
        wall = row["paired_ratios"]["wall"]
        md_lines.append(
            "| `{}` | {} | {} | {} | {} | {} | {} |".format(
                row["workload"],
                row["status"],
                "n/a" if value["median"] is None else f"{value['median']:.4f}",
                (
                    "n/a"
                    if value["geometric_mean"] is None
                    else f"{value['geometric_mean']:.4f}"
                ),
                "n/a" if wall["median"] is None else f"{wall['median']:.4f}",
                (
                    "n/a"
                    if wall["geometric_mean"] is None
                    else f"{wall['geometric_mean']:.4f}"
                ),
                row["cache"]["measured_fresh_compilations"],
            )
        )
    if failures:
        md_lines.extend(["", "## Failures", ""])
        md_lines.extend(f"- {entry}" for entry in failures)
    if perf_gaps:
        md_lines.extend(["", "## Performance Gaps", ""])
        md_lines.extend(f"- {entry}" for entry in perf_gaps)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
    print(
        f"[done] summary={summary_path} failures={len(failures)} "
        f"perf_gaps={len(perf_gaps)}",
        file=sys.stderr,
        flush=True,
    )

    if args.strict and (failures or perf_gaps):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
