#!/usr/bin/env python3
"""Run the blocking paired legacy/candidate MachV cutover comparison."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


RUNTIME_CORPUS_LIMIT = 1.03
RUNTIME_WORKLOAD_LIMIT = 1.05
COMPILE_CORPUS_LIMIT = 1.05
COMPILE_WORKLOAD_LIMIT = 1.10
CODE_SIZE_TOTAL_LIMIT = 1.00
CODE_SIZE_WORKLOAD_LIMIT = 1.05


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_logged(
    command: list[str], *, cwd: Path, log: Path, timeout: int | None = None
) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.run(
            command,
            cwd=cwd,
            stdout=output,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
            text=True,
        )
    if process.returncode != 0:
        raise RuntimeError(
            f"command failed with exit {process.returncode}: {' '.join(command)}; "
            f"see {log}"
        )


def parse_metrics(path: Path) -> tuple[int, int, int]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    compile_us = int(payload["module_compile_us"])
    code_size = sum(int(function.get("code_size", 0)) for function in payload["functions"])
    expected_functions = int(payload["expected_functions"])
    observed_functions = len(payload["functions"])
    if observed_functions != expected_functions:
        raise RuntimeError(
            f"incomplete function metrics in {path}: expected "
            f"{expected_functions}, got {observed_functions}"
        )
    if compile_us <= 0 or code_size <= 0:
        raise RuntimeError(f"incomplete performance metrics in {path}")
    return compile_us, code_size, observed_functions


def measure_startup(binary: Path, repo: Path, samples: int = 5) -> dict[str, Any]:
    values: list[int] = []
    for _ in range(samples + 1):
        started = time.perf_counter_ns()
        process = subprocess.run(
            [str(binary), "settings"],
            cwd=repo,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        elapsed = time.perf_counter_ns() - started
        if process.returncode != 0:
            raise RuntimeError(f"startup calibration failed for {binary}")
        values.append(elapsed)
    measured = values[1:]
    return {"samples_ns": measured, "median_ns": int(statistics.median(measured))}


def run_sample(
    *,
    binary: Path,
    repo: Path,
    workload: dict[str, Any],
    out_dir: Path,
    label: str,
    timeout: int,
    startup_ns: int,
) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics = out_dir / f"{label}.metrics.json"
    stdout_path = out_dir / f"{label}.stdout.log"
    stderr_path = out_dir / f"{label}.stderr.log"
    env = os.environ.copy()
    env["WASMOON_PERF_METRICS"] = "1"
    env["WASMOON_PERF_METRICS_FILE"] = str(metrics)
    command = [str(binary), workload["subcommand"], str(repo / workload["path"])]
    started = time.perf_counter_ns()
    with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr:
        try:
            process = subprocess.run(
                command,
                cwd=repo,
                env=env,
                stdout=stdout,
                stderr=stderr,
                timeout=timeout,
                check=False,
                text=True,
            )
            exit_code = process.returncode
            timed_out = False
        except subprocess.TimeoutExpired:
            exit_code = 124
            timed_out = True
    elapsed_ns = time.perf_counter_ns() - started
    stdout_text = stdout_path.read_text(encoding="utf-8")
    if exit_code != 0 or timed_out:
        raise RuntimeError(f"{label} failed with exit {exit_code}; see {out_dir}")
    if workload["expected_output"] not in stdout_text:
        raise RuntimeError(
            f"{label} omitted expected output {workload['expected_output']!r}"
        )
    if not metrics.exists():
        raise RuntimeError(f"{label} did not produce {metrics}")
    compile_us, code_size, function_count = parse_metrics(metrics)
    execution_ns = max(1, elapsed_ns - compile_us * 1000 - startup_ns)
    return {
        "elapsed_ns": elapsed_ns,
        "startup_ns": startup_ns,
        "execution_ns": execution_ns // int(workload["internal_iterations"]),
        "module_compile_us": compile_us,
        "code_size": code_size,
        "function_count": function_count,
        "metrics": str(metrics),
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
    }


def geometric_mean(values: list[float]) -> float:
    if not values or any(value <= 0 for value in values):
        raise RuntimeError("geometric mean requires positive samples")
    return math.exp(sum(math.log(value) for value in values) / len(values))


def ratio_stats(values: list[float]) -> dict[str, float]:
    logs = [math.log(value) for value in values]
    mean = statistics.mean(logs)
    if len(logs) == 1:
        upper = mean
        cv = 0.0
    else:
        critical = 2.306 if len(logs) <= 9 else 2.086 if len(logs) <= 21 else 1.96
        # Use the paired log-ratio confidence bound. A threshold-crossing upper
        # bound is deliberately treated as inconclusive rather than accepted.
        upper = mean + critical * statistics.stdev(logs) / math.sqrt(len(logs))
        cv = statistics.stdev(values) / statistics.mean(values)
    return {
        "geometric_mean_ratio": math.exp(mean),
        "upper_95_ratio": math.exp(upper),
        "coefficient_of_variation": cv,
    }


def record_failure(
    failures: list[str], name: str, stats: dict[str, float], limit: float
) -> None:
    observed = stats["geometric_mean_ratio"]
    upper = stats["upper_95_ratio"]
    if observed > limit:
        failures.append(f"{name}: ratio {observed:.6f} exceeds {limit:.6f}")
    elif upper > limit:
        failures.append(
            f"{name}: inconclusive upper 95% ratio {upper:.6f} exceeds {limit:.6f}"
        )


def git_output(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=repo, text=True).strip()


def target_name(baseline: dict[str, Any]) -> str:
    system = platform.system()
    machine = platform.machine()
    name = (
        "darwin-arm64"
        if system == "Darwin" and machine in ("arm64", "aarch64")
        else "linux-amd64"
        if system == "Linux" and machine == "x86_64"
        else ""
    )
    if not name:
        raise RuntimeError(f"unsupported cutover runner identity: {system}/{machine}")
    target = next(item for item in baseline["targets"] if item["name"] == name)
    uname_m = subprocess.check_output(["uname", "-m"], text=True).strip()
    if uname_m not in target["required_uname_m"]:
        raise RuntimeError(
            f"{name} runner has unexpected uname -m {uname_m!r}; "
            f"expected {target['required_uname_m']}"
        )
    return name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--baseline", type=Path, default=Path("docs/perf/machv-migration/baseline.json")
    )
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--pairs", type=int, default=9)
    parser.add_argument("--expanded-pairs", type=int, default=21)
    parser.add_argument("--timeout-sec", type=int, default=240)
    parser.add_argument("--candidate-binary", type=Path)
    parser.add_argument("--legacy-binary", type=Path)
    parser.add_argument("--legacy-repo", type=Path)
    args = parser.parse_args()
    if args.pairs < 2 or args.expanded_pairs < args.pairs:
        raise SystemExit("invalid pair counts")

    repo = Path.cwd().resolve()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    workloads_path = repo / baseline["workload_manifest"]
    workloads = json.loads(workloads_path.read_text(encoding="utf-8"))["workloads"]
    target = target_name(baseline)

    for workload in workloads:
        path = repo / workload["path"]
        actual = sha256(path)
        if actual != workload["sha256"]:
            raise SystemExit(
                f"workload checksum mismatch for {workload['path']}: "
                f"expected {workload['sha256']}, got {actual}"
            )

    temporary: tempfile.TemporaryDirectory[str] | None = None
    legacy_repo = args.legacy_repo.resolve() if args.legacy_repo else None
    try:
        if legacy_repo is None:
            temporary = tempfile.TemporaryDirectory(prefix="wasmoon-legacy-")
            legacy_repo = Path(temporary.name) / "repo"
            run_logged(
                [
                    "git",
                    "worktree",
                    "add",
                    "--detach",
                    str(legacy_repo),
                    baseline["legacy_commit"],
                ],
                cwd=repo,
                log=out_dir / "build" / "legacy-worktree.log",
            )

        candidate_binary = args.candidate_binary.resolve() if args.candidate_binary else None
        if candidate_binary is None:
            run_logged(
                ["moon", "update"], cwd=repo, log=out_dir / "build" / "candidate-update.log"
            )
            run_logged(
                ["moon", "build", "--target", "native", "--release"],
                cwd=repo,
                log=out_dir / "build" / "candidate-build.log",
            )
            run_logged(
                ["./install.sh"], cwd=repo, log=out_dir / "build" / "candidate-install.log"
            )
            candidate_binary = (repo / "wasmoon").resolve()

        legacy_binary = args.legacy_binary.resolve() if args.legacy_binary else None
        if legacy_binary is None:
            run_logged(
                ["moon", "update"],
                cwd=legacy_repo,
                log=out_dir / "build" / "legacy-update.log",
            )
            run_logged(
                ["moon", "build", "--target", "native", "--release"],
                cwd=legacy_repo,
                log=out_dir / "build" / "legacy-build.log",
            )
            run_logged(
                ["./install.sh"],
                cwd=legacy_repo,
                log=out_dir / "build" / "legacy-install.log",
            )
            legacy_binary = (legacy_repo / "wasmoon").resolve()

        startup = {
            "legacy": measure_startup(legacy_binary, legacy_repo),
            "candidate": measure_startup(candidate_binary, repo),
        }

        rows: list[dict[str, Any]] = []
        needs_expansion = False
        for workload in workloads:
            stem = workload["path"].replace("/", "__")
            samples: list[dict[str, Any]] = []

            for side, binary, side_repo in (
                ("legacy", legacy_binary, legacy_repo),
                ("candidate", candidate_binary, repo),
            ):
                run_sample(
                    binary=binary,
                    repo=side_repo,
                    workload={**workload, "path": str(repo / workload["path"])},
                    out_dir=out_dir / "raw" / stem,
                    label=f"warmup-{side}",
                    timeout=args.timeout_sec,
                    startup_ns=startup[side]["median_ns"],
                )

            pair = 0
            target_pairs = args.pairs
            while pair < target_pairs:
                order = (
                    (("legacy", legacy_binary, legacy_repo), ("candidate", candidate_binary, repo))
                    if pair % 2 == 0
                    else (("candidate", candidate_binary, repo), ("legacy", legacy_binary, legacy_repo))
                )
                result: dict[str, Any] = {"pair": pair, "order": [item[0] for item in order]}
                for side, binary, side_repo in order:
                    result[side] = run_sample(
                        binary=binary,
                        repo=side_repo,
                        workload={**workload, "path": str(repo / workload["path"])},
                        out_dir=out_dir / "raw" / stem,
                        label=f"pair-{pair:02d}-{side}",
                        timeout=args.timeout_sec,
                        startup_ns=startup[side]["median_ns"],
                    )
                samples.append(result)
                pair += 1

                if pair == args.pairs:
                    runtime_ratios = [
                        sample["candidate"]["execution_ns"] / sample["legacy"]["execution_ns"]
                        for sample in samples
                    ]
                    compile_ratios = [
                        sample["candidate"]["module_compile_us"]
                        / sample["legacy"]["module_compile_us"]
                        for sample in samples
                    ]
                    noisy = (
                        "runtime" in workload["metrics"]
                        and ratio_stats(runtime_ratios)["coefficient_of_variation"] > 0.015
                    ) or ratio_stats(compile_ratios)["coefficient_of_variation"] > 0.025
                    if noisy and args.expanded_pairs > args.pairs:
                        target_pairs = args.expanded_pairs
                        needs_expansion = True

            runtime_ratios = [
                sample["candidate"]["execution_ns"] / sample["legacy"]["execution_ns"]
                for sample in samples
            ]
            compile_ratios = [
                sample["candidate"]["module_compile_us"]
                / sample["legacy"]["module_compile_us"]
                for sample in samples
            ]
            legacy_sizes = [sample["legacy"]["code_size"] for sample in samples]
            candidate_sizes = [sample["candidate"]["code_size"] for sample in samples]
            rows.append(
                {
                    "workload": workload["path"],
                    "tier": workload["tier"],
                    "metrics": workload["metrics"],
                    "pairs": len(samples),
                    "runtime": ratio_stats(runtime_ratios),
                    "compile": ratio_stats(compile_ratios),
                    "code_size": {
                        "legacy_median": statistics.median(legacy_sizes),
                        "candidate_median": statistics.median(candidate_sizes),
                        "ratio": statistics.median(candidate_sizes)
                        / statistics.median(legacy_sizes),
                    },
                    "samples": samples,
                }
            )

        failures: list[str] = []
        runtime_rows = [row for row in rows if "runtime" in row["metrics"]]
        for row in runtime_rows:
            record_failure(
                failures,
                f"runtime {row['workload']}",
                row["runtime"],
                RUNTIME_WORKLOAD_LIMIT,
            )
        for row in rows:
            record_failure(
                failures,
                f"compile {row['workload']}",
                row["compile"],
                COMPILE_WORKLOAD_LIMIT,
            )
            if row["code_size"]["ratio"] > CODE_SIZE_WORKLOAD_LIMIT:
                failures.append(
                    f"code size {row['workload']}: ratio "
                    f"{row['code_size']['ratio']:.6f} exceeds {CODE_SIZE_WORKLOAD_LIMIT:.6f}"
                )

        runtime_corpus = geometric_mean(
            [row["runtime"]["geometric_mean_ratio"] for row in runtime_rows]
        )
        compile_corpus = geometric_mean(
            [row["compile"]["geometric_mean_ratio"] for row in rows]
        )
        legacy_total = sum(row["code_size"]["legacy_median"] for row in rows)
        candidate_total = sum(row["code_size"]["candidate_median"] for row in rows)
        size_total_ratio = candidate_total / legacy_total
        if runtime_corpus > RUNTIME_CORPUS_LIMIT:
            failures.append(
                f"runtime corpus ratio {runtime_corpus:.6f} exceeds {RUNTIME_CORPUS_LIMIT:.6f}"
            )
        if compile_corpus > COMPILE_CORPUS_LIMIT:
            failures.append(
                f"compile corpus ratio {compile_corpus:.6f} exceeds {COMPILE_CORPUS_LIMIT:.6f}"
            )
        if size_total_ratio > CODE_SIZE_TOTAL_LIMIT:
            failures.append(
                f"total code-size ratio {size_total_ratio:.6f} exceeds {CODE_SIZE_TOTAL_LIMIT:.6f}"
            )

        report = {
            "schema_version": 1,
            "generated_at_unix_sec": int(time.time()),
            "candidate_commit": git_output(repo, "rev-parse", "HEAD"),
            "candidate_parent_commit": git_output(repo, "rev-parse", "HEAD^"),
            "legacy_commit": baseline["legacy_commit"],
            "target": target,
            "host": {
                "system": platform.system(),
                "machine": platform.machine(),
                "processor": platform.processor(),
                "uname_m": subprocess.check_output(["uname", "-m"], text=True).strip(),
            },
            "baseline_manifest_sha256": sha256(args.baseline),
            "workload_manifest_sha256": sha256(workloads_path),
            "thresholds": {
                "runtime_corpus": RUNTIME_CORPUS_LIMIT,
                "runtime_workload": RUNTIME_WORKLOAD_LIMIT,
                "compile_corpus": COMPILE_CORPUS_LIMIT,
                "compile_workload": COMPILE_WORKLOAD_LIMIT,
                "code_size_total": CODE_SIZE_TOTAL_LIMIT,
                "code_size_workload": CODE_SIZE_WORKLOAD_LIMIT,
            },
            "startup_calibration": startup,
            "expanded_for_noise": needs_expansion,
            "aggregates": {
                "runtime_corpus_ratio": runtime_corpus,
                "compile_corpus_ratio": compile_corpus,
                "legacy_code_size_total": legacy_total,
                "candidate_code_size_total": candidate_total,
                "code_size_total_ratio": size_total_ratio,
            },
            "workloads": rows,
            "failures": failures,
            "decision": "pass" if not failures else "fail",
        }
        report_path = out_dir / "perf-report.json"
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"report": str(report_path), "decision": report["decision"], "failures": failures}, indent=2))
        return 0 if not failures else 2
    finally:
        if temporary is not None:
            # Removing the worktree through Git avoids leaving administrative
            # entries behind when the temporary directory is deleted.
            if legacy_repo is not None:
                subprocess.run(
                    ["git", "worktree", "remove", "--force", str(legacy_repo)],
                    cwd=repo,
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            temporary.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
