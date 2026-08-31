#!/usr/bin/env python3
"""Run one cold-cache Wasmoon/Wasmtime pair per algorithm workload."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
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
    freshly_compiled: Optional[bool] = None
    cache_files_before: List[str] = field(default_factory=list)
    cache_files_after: List[str] = field(default_factory=list)


@dataclass(frozen=True)
class IsolatedCaches:
    root: Path
    wasmoon: Path
    wasmtime: Path
    wasmtime_config: Path


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


def ratio(numerator: Optional[float], denominator: Optional[float]) -> Optional[float]:
    if numerator is None or denominator is None:
        return None
    if denominator == 0.0:
        if numerator == 0.0:
            return 1.0
        return float("inf") if numerator > 0.0 else float("-inf")
    return numerator / denominator


def pair_engine_order(workload_index: int) -> List[str]:
    if workload_index % 2 == 0:
        return ["wasmoon", "wasmtime"]
    return ["wasmtime", "wasmoon"]


def sanitized_workload_name(workload: Path) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", workload.stem)


def prepare_isolated_caches(cache_root: Path, workload: Path) -> IsolatedCaches:
    root = cache_root / sanitized_workload_name(workload)
    if root.exists():
        shutil.rmtree(root)
    wasmoon = root / "wasmoon"
    wasmtime = root / "wasmtime"
    wasmoon.mkdir(parents=True)
    wasmtime.mkdir()
    wasmtime_config = root / "wasmtime-cache.toml"
    wasmtime_config.write_text(
        "[cache]\n" f"directory = {json.dumps(str(wasmtime.resolve()))}\n",
        encoding="utf-8",
    )
    return IsolatedCaches(
        root=root,
        wasmoon=wasmoon,
        wasmtime=wasmtime,
        wasmtime_config=wasmtime_config,
    )


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


def record_cache_run(
    command: List[str],
    timeout_sec: int,
    cache_dir: Path,
    *,
    extra_env: Optional[Dict[str, str]] = None,
) -> RunResult:
    before = cache_snapshot(cache_dir)
    result = run_one(command, timeout_sec, extra_env=extra_env)
    after = cache_snapshot(cache_dir)
    result.freshly_compiled = any(
        name not in before or before[name] != metadata
        for name, metadata in after.items()
    )
    result.cache_files_before = sorted(before)
    result.cache_files_after = sorted(after)
    return result


def run_engine(
    engine: str,
    workload: Path,
    *,
    wasmoon_bin: str,
    wasmtime_bin: str,
    timeout_sec: int,
    caches: IsolatedCaches,
) -> RunResult:
    if engine == "wasmoon":
        return record_cache_run(
            [wasmoon_bin, "run", str(workload)],
            timeout_sec,
            caches.wasmoon,
            extra_env={"WASMOON_JIT_CACHE_DIR": str(caches.wasmoon)},
        )
    return record_cache_run(
        [
            wasmtime_bin,
            "run",
            "-C",
            "cache=y",
            "-C",
            f"cache-config={caches.wasmtime_config.resolve()}",
            "-C",
            "parallel-compilation=n",
            str(workload),
        ],
        timeout_sec,
        caches.wasmtime,
    )


def run_payload(result: RunResult) -> Dict:
    return {
        "command": result.command,
        "exit_code": result.exit_code,
        "timeout": result.timeout,
        "duration_sec": result.duration_sec,
        "parsed_value": result.parsed_value,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        "freshly_compiled": result.freshly_compiled,
        "cache_files_before": result.cache_files_before,
        "cache_files_after": result.cache_files_after,
    }


def successful(result: RunResult) -> bool:
    return result.exit_code == 0 and not result.timeout


def run_pair(
    workload_index: int,
    workload: Path,
    *,
    wasmoon_bin: str,
    wasmtime_bin: str,
    timeout_sec: int,
    caches: IsolatedCaches,
) -> Dict:
    results: Dict[str, RunResult] = {}
    order = pair_engine_order(workload_index)
    for engine in order:
        results[engine] = run_engine(
            engine,
            workload,
            wasmoon_bin=wasmoon_bin,
            wasmtime_bin=wasmtime_bin,
            timeout_sec=timeout_sec,
            caches=caches,
        )
    wasmoon = results["wasmoon"]
    wasmtime = results["wasmtime"]
    pair_value_ratio = None
    pair_wall_ratio = None
    if successful(wasmoon) and successful(wasmtime):
        pair_value_ratio = ratio(wasmoon.parsed_value, wasmtime.parsed_value)
        pair_wall_ratio = ratio(wasmoon.duration_sec, wasmtime.duration_sec)
    return {
        "order": order,
        "wasmoon": run_payload(wasmoon),
        "wasmtime": run_payload(wasmtime),
        "value_ratio": pair_value_ratio,
        "wall_ratio": pair_wall_ratio,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run one cold-cache Wasmoon/Wasmtime pair for each "
            "examples/algorithms workload."
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
    parser.add_argument(
        "--value-ratio-threshold",
        type=float,
        default=1.05,
        help="Allowed one-sided paired output ratio.",
    )
    parser.add_argument(
        "--wall-ratio-threshold",
        type=float,
        default=2.0,
        help="Allowed one-sided paired wall-time ratio.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return non-zero when failures or performance gaps exist.",
    )
    args = parser.parse_args()

    workloads = list_workloads(Path(args.workloads_dir))
    if not workloads:
        raise SystemExit(f"No wasm workloads found in {args.workloads_dir}")

    summary_path = Path(args.summary_file)
    cache_root = summary_path.parent / "jit-cache"
    rows: List[Dict] = []
    failures: List[str] = []
    perf_gaps: List[str] = []

    for workload_index, workload in enumerate(workloads):
        workload_str = str(workload)
        print(
            f"[run] {workload_index + 1}/{len(workloads)} {workload_str}",
            file=sys.stderr,
            flush=True,
        )
        caches = prepare_isolated_caches(cache_root, workload)
        pair = run_pair(
            workload_index,
            workload,
            wasmoon_bin=args.wasmoon,
            wasmtime_bin=args.wasmtime,
            timeout_sec=args.timeout_sec,
            caches=caches,
        )

        status = "ok"
        if pair["value_ratio"] is None or pair["wall_ratio"] is None:
            status = "runtime_error"
            failures.append(f"{workload_str}: paired run failed")
        elif pair["value_ratio"] > args.value_ratio_threshold:
            status = "perf_gap"
            perf_gaps.append(
                f"{workload_str}: paired output ratio "
                f"{pair['value_ratio']:.4f} "
                f"(threshold {args.value_ratio_threshold:.4f})"
            )
        elif pair["wall_ratio"] > args.wall_ratio_threshold:
            status = "perf_gap"
            perf_gaps.append(
                f"{workload_str}: paired wall ratio "
                f"{pair['wall_ratio']:.4f} "
                f"(threshold {args.wall_ratio_threshold:.4f})"
            )

        rows.append(
            {
                "workload": workload_str,
                "status": status,
                "cache": {
                    "directory": str(caches.root),
                    "isolated": True,
                    "cold": True,
                    "wasmoon_directory": str(caches.wasmoon),
                    "wasmtime_directory": str(caches.wasmtime),
                },
                "pair": pair,
            }
        )
        print(
            f"[run] {workload_str} status={status} "
            f"value_ratio={pair['value_ratio']} "
            f"wall_ratio={pair['wall_ratio']}",
            file=sys.stderr,
            flush=True,
        )

    summary_payload = {
        "schema_version": 3,
        "generated_at_unix_sec": int(time.time()),
        "config": {
            "wasmoon": args.wasmoon,
            "wasmtime": args.wasmtime,
            "timeout_sec": args.timeout_sec,
            "runs_per_engine": 1,
            "cache_policy": "cold-isolated-per-workload",
            "wasmtime_parallel_compilation": False,
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
        f"- Cold isolated cache root: `{cache_root}`",
        "- Runs per engine and workload: `1`",
        "- Wasmtime parallel compilation: `disabled`",
        f"- Total workloads: `{summary_payload['stats']['total']}`",
        f"- OK: `{summary_payload['stats']['ok']}`",
        f"- Failures: `{summary_payload['stats']['failures']}`",
        f"- Perf gaps: `{summary_payload['stats']['perf_gaps']}`",
        "",
        "| Workload | Status | Value Ratio | Wall Ratio | Wasmoon Fresh Compile | Wasmtime Fresh Compile |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for row in rows:
        pair = row["pair"]
        md_lines.append(
            "| `{}` | {} | {} | {} | {} | {} |".format(
                row["workload"],
                row["status"],
                (
                    "n/a"
                    if pair["value_ratio"] is None
                    else f"{pair['value_ratio']:.4f}"
                ),
                (
                    "n/a"
                    if pair["wall_ratio"] is None
                    else f"{pair['wall_ratio']:.4f}"
                ),
                pair["wasmoon"]["freshly_compiled"],
                pair["wasmtime"]["freshly_compiled"],
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
