#!/usr/bin/env python3
"""Run the blocking paired legacy/candidate MachV cutover comparison."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
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
WORKLOAD_SCHEMA_VERSION = 2
WORKLOAD_TIERS = {"micro_codegen", "real_module", "large_compile_stress"}
REQUIRED_WORKLOAD_FEATURES = {
    "scalar_integer",
    "scalar_float",
    "control_flow",
    "direct_call",
    "indirect_call",
    "tail_call",
    "stack_arguments",
    "multi_value",
    "simd",
    "memory64",
    "gc",
    "exceptions",
    "references",
    "large_function",
    "complex_cfg",
    "register_pressure",
    "dense_metadata",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_workload_manifest(payload: dict[str, Any]) -> list[dict[str, Any]]:
    if payload.get("schema_version") != WORKLOAD_SCHEMA_VERSION:
        raise RuntimeError(
            f"workload manifest schema must be {WORKLOAD_SCHEMA_VERSION}"
        )
    workloads = payload.get("workloads")
    if not isinstance(workloads, list) or not workloads:
        raise RuntimeError("workload manifest must contain workloads")

    required_fields = {
        "tier",
        "path",
        "sha256",
        "subcommand",
        "entry",
        "expected_output",
        "internal_iterations",
        "metrics",
        "features",
    }
    paths: set[str] = set()
    covered_features: set[str] = set()
    tier_counts = {tier: 0 for tier in WORKLOAD_TIERS}
    for index, workload in enumerate(workloads):
        if not isinstance(workload, dict):
            raise RuntimeError(f"workload {index} must be an object")
        missing_fields = sorted(required_fields - workload.keys())
        if missing_fields:
            raise RuntimeError(f"workload {index} missing fields: {missing_fields}")
        tier = workload["tier"]
        if tier not in WORKLOAD_TIERS:
            raise RuntimeError(f"workload {index} has unknown tier {tier!r}")
        tier_counts[tier] += 1
        path = workload["path"]
        if not isinstance(path, str) or not path or path in paths:
            raise RuntimeError(f"workload {index} has invalid or duplicate path {path!r}")
        paths.add(path)
        checksum = workload["sha256"]
        if not isinstance(checksum, str) or len(checksum) != 64:
            raise RuntimeError(f"workload {path} has invalid sha256")
        try:
            int(checksum, 16)
        except ValueError as error:
            raise RuntimeError(f"workload {path} has invalid sha256") from error
        if workload["subcommand"] not in ("run", "test"):
            raise RuntimeError(f"workload {path} has invalid subcommand")
        if not isinstance(workload["expected_output"], str) or not workload[
            "expected_output"
        ]:
            raise RuntimeError(f"workload {path} has no output oracle")
        if not isinstance(workload["internal_iterations"], int) or workload[
            "internal_iterations"
        ] <= 0:
            raise RuntimeError(f"workload {path} has invalid internal_iterations")
        metrics = workload["metrics"]
        if not isinstance(metrics, list) or not metrics:
            raise RuntimeError(f"workload {path} has no metrics")
        if tier == "real_module" and "runtime" not in metrics:
            raise RuntimeError(f"real workload {path} must measure runtime")
        features = workload["features"]
        if (
            not isinstance(features, list)
            or not features
            or any(not isinstance(feature, str) or not feature for feature in features)
        ):
            raise RuntimeError(f"workload {path} has invalid features")
        covered_features.update(features)

    missing_features = sorted(REQUIRED_WORKLOAD_FEATURES - covered_features)
    if missing_features:
        raise RuntimeError(f"workload manifest misses features: {missing_features}")
    if tier_counts["real_module"] < 3:
        raise RuntimeError("workload manifest requires at least three real modules")
    if tier_counts["large_compile_stress"] < 2:
        raise RuntimeError("workload manifest requires at least two compile-stress modules")
    return workloads


def validate_workload_files(repo: Path, workloads: list[dict[str, Any]]) -> None:
    for workload in workloads:
        path = repo / workload["path"]
        if not path.is_file():
            raise RuntimeError(f"workload file does not exist: {workload['path']}")
        actual = sha256(path)
        if actual != workload["sha256"]:
            raise RuntimeError(
                f"workload checksum mismatch for {workload['path']}: "
                f"expected {workload['sha256']}, got {actual}"
            )


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


def normalize_runtime_ns(
    elapsed_ns: int, startup_ns: int, internal_iterations: int
) -> float:
    execution_ns = elapsed_ns - startup_ns
    if execution_ns <= 0:
        raise RuntimeError(
            "cached runtime signal is not positive: "
            f"elapsed={elapsed_ns}ns startup={startup_ns}ns"
        )
    return execution_ns / internal_iterations


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


def prepare_workload(
    *,
    source: Path,
    candidate_tools: Path,
    repo: Path,
    out_dir: Path,
    label: str,
) -> Path:
    if source.suffix != ".wat":
        return source
    output = out_dir / f"{label}.wasm"
    run_logged(
        [str(candidate_tools), "wat2wasm", str(source), "-o", str(output)],
        cwd=repo,
        log=out_dir / f"{label}.wat2wasm.log",
    )
    if not output.is_file():
        raise RuntimeError(f"wat2wasm did not produce {output}")
    return output


def prime_runtime_cache(
    *,
    binary: Path,
    repo: Path,
    workload: dict[str, Any],
    out_dir: Path,
    label: str,
    timeout: int,
    cache_dir: Path,
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["WASMOON_JIT_CACHE_DIR"] = str(cache_dir)
    command = [str(binary), workload["subcommand"], workload["path"]]
    for suffix, debug in (("prime", False), ("check", True)):
        stdout_path = out_dir / f"cache-{suffix}-{label}.stdout.log"
        stderr_path = out_dir / f"cache-{suffix}-{label}.stderr.log"
        actual_command = [*command[:2], "-D", *command[2:]] if debug else command
        with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open(
            "w", encoding="utf-8"
        ) as stderr:
            process = subprocess.run(
                actual_command,
                cwd=repo,
                env=env,
                stdout=stdout,
                stderr=stderr,
                timeout=timeout,
                check=False,
                text=True,
            )
        stdout_text = stdout_path.read_text(encoding="utf-8")
        stderr_text = stderr_path.read_text(encoding="utf-8")
        if process.returncode != 0:
            raise RuntimeError(
                f"cache-{suffix}-{label} failed with exit {process.returncode}; "
                f"see {out_dir}"
            )
        if workload["expected_output"] not in stdout_text:
            raise RuntimeError(
                f"cache-{suffix}-{label} omitted expected output "
                f"{workload['expected_output']!r}"
            )
        if debug and "JIT: cache hit " not in stdout_text + stderr_text:
            raise RuntimeError(f"cache-check-{label} did not use the JIT cache")


def run_sample(
    *,
    binary: Path,
    repo: Path,
    workload: dict[str, Any],
    out_dir: Path,
    label: str,
    timeout: int,
    startup_ns: int,
    runtime_cache: Path | None,
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
    result = {
        "elapsed_ns": elapsed_ns,
        "startup_ns": startup_ns,
        "module_compile_us": compile_us,
        "code_size": code_size,
        "function_count": function_count,
        "metrics": str(metrics),
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
    }
    if runtime_cache is None:
        return result

    runtime_stdout_path = out_dir / f"{label}.runtime.stdout.log"
    runtime_stderr_path = out_dir / f"{label}.runtime.stderr.log"
    runtime_env = os.environ.copy()
    runtime_env["WASMOON_JIT_CACHE_DIR"] = str(runtime_cache)
    runtime_started = time.perf_counter_ns()
    with runtime_stdout_path.open(
        "w", encoding="utf-8"
    ) as runtime_stdout, runtime_stderr_path.open(
        "w", encoding="utf-8"
    ) as runtime_stderr:
        try:
            runtime_process = subprocess.run(
                command,
                cwd=repo,
                env=runtime_env,
                stdout=runtime_stdout,
                stderr=runtime_stderr,
                timeout=timeout,
                check=False,
                text=True,
            )
            runtime_exit_code = runtime_process.returncode
            runtime_timed_out = False
        except subprocess.TimeoutExpired:
            runtime_exit_code = 124
            runtime_timed_out = True
    runtime_elapsed_ns = time.perf_counter_ns() - runtime_started
    runtime_stdout_text = runtime_stdout_path.read_text(encoding="utf-8")
    if runtime_exit_code != 0 or runtime_timed_out:
        raise RuntimeError(
            f"{label} cached runtime failed with exit {runtime_exit_code}; "
            f"see {out_dir}"
        )
    if workload["expected_output"] not in runtime_stdout_text:
        raise RuntimeError(
            f"{label} cached runtime omitted expected output "
            f"{workload['expected_output']!r}"
        )
    result.update(
        {
            "runtime_elapsed_ns": runtime_elapsed_ns,
            "execution_ns": normalize_runtime_ns(
                runtime_elapsed_ns,
                startup_ns,
                int(workload["internal_iterations"]),
            ),
            "runtime_stdout": str(runtime_stdout_path),
            "runtime_stderr": str(runtime_stderr_path),
        }
    )
    return result


def two_sided_95_t_critical(degrees_of_freedom: float) -> float:
    # Selecting the next lower tabulated degree of freedom is conservative.
    # The cutover gate normally uses 9 or 21 pairs, but corpus aggregation can
    # produce fractional Welch-Satterthwaite degrees of freedom.
    critical_values = (
        (1, 12.706),
        (2, 4.303),
        (3, 3.182),
        (4, 2.776),
        (5, 2.571),
        (6, 2.447),
        (7, 2.365),
        (8, 2.306),
        (9, 2.262),
        (10, 2.228),
        (12, 2.179),
        (15, 2.131),
        (20, 2.086),
        (25, 2.060),
        (30, 2.042),
        (40, 2.021),
        (60, 2.000),
        (120, 1.980),
    )
    if degrees_of_freedom < 1:
        raise RuntimeError("confidence bound requires positive degrees of freedom")
    selected = critical_values[0][1]
    for tabulated_df, critical in critical_values:
        if tabulated_df > degrees_of_freedom:
            break
        selected = critical
    return selected if degrees_of_freedom < 120 else 1.980


def ratio_stats(values: list[float]) -> dict[str, float]:
    logs = [math.log(value) for value in values]
    mean = statistics.mean(logs)
    if len(logs) == 1:
        upper = mean
        cv = 0.0
    else:
        critical = two_sided_95_t_critical(len(logs) - 1)
        # Use the paired log-ratio confidence bound. A threshold-crossing upper
        # bound is deliberately treated as inconclusive rather than accepted.
        upper = mean + critical * statistics.stdev(logs) / math.sqrt(len(logs))
        cv = statistics.stdev(values) / statistics.mean(values)
    return {
        "geometric_mean_ratio": math.exp(mean),
        "upper_95_ratio": math.exp(upper),
        "coefficient_of_variation": cv,
    }


def workload_runtime_stats(
    workload: dict[str, Any], samples: list[dict[str, Any]]
) -> dict[str, float] | None:
    if "runtime" not in workload["metrics"]:
        return None
    return ratio_stats(
        [
            sample["candidate"]["execution_ns"]
            / sample["legacy"]["execution_ns"]
            for sample in samples
        ]
    )


def corpus_ratio_stats(groups: list[list[float]]) -> dict[str, float]:
    if not groups or any(len(group) < 2 for group in groups):
        raise RuntimeError("corpus confidence bound requires paired samples")
    if any(value <= 0 for group in groups for value in group):
        raise RuntimeError("corpus ratios must be positive")

    log_groups = [[math.log(value) for value in group] for group in groups]
    mean = statistics.mean(statistics.mean(group) for group in log_groups)
    mean_variances = [statistics.variance(group) / len(group) for group in log_groups]
    variance = sum(mean_variances) / len(log_groups) ** 2
    if variance == 0.0:
        upper = mean
        degrees_of_freedom = float(sum(len(group) - 1 for group in log_groups))
    else:
        numerator = sum(mean_variances) ** 2
        denominator = sum(
            component**2 / (len(group) - 1)
            for component, group in zip(mean_variances, log_groups)
        )
        degrees_of_freedom = numerator / denominator
        upper = mean + two_sided_95_t_critical(degrees_of_freedom) * math.sqrt(
            variance
        )
    return {
        "geometric_mean_ratio": math.exp(mean),
        "upper_95_ratio": math.exp(upper),
        "standard_error_log_ratio": math.sqrt(variance),
        "degrees_of_freedom": degrees_of_freedom,
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
    workloads = validate_workload_manifest(
        json.loads(workloads_path.read_text(encoding="utf-8"))
    )
    target = target_name(baseline)

    validate_workload_files(repo, workloads)

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

        candidate_tools = candidate_binary.with_name("wasmoon-tools")
        if not candidate_tools.is_file():
            raise RuntimeError(
                f"candidate wat2wasm tool does not exist: {candidate_tools}"
            )
        prepared_workloads = {
            workload["path"]: prepare_workload(
                source=repo / workload["path"],
                candidate_tools=candidate_tools,
                repo=repo,
                out_dir=out_dir / "prepared",
                label=workload["path"].replace("/", "__"),
            )
            for workload in workloads
        }

        startup = {
            "legacy": measure_startup(legacy_binary, legacy_repo),
            "candidate": measure_startup(candidate_binary, repo),
        }

        rows: list[dict[str, Any]] = []
        needs_expansion = False
        for workload in workloads:
            stem = workload["path"].replace("/", "__")
            prepared_path = prepared_workloads[workload["path"]]
            prepared_workload = {**workload, "path": str(prepared_path)}
            samples: list[dict[str, Any]] = []
            runtime_caches: dict[str, Path] = {}

            if "runtime" in workload["metrics"]:
                for side, binary, side_repo in (
                    ("legacy", legacy_binary, legacy_repo),
                    ("candidate", candidate_binary, repo),
                ):
                    cache_dir = out_dir / "runtime-cache" / stem / side
                    prime_runtime_cache(
                        binary=binary,
                        repo=side_repo,
                        workload=prepared_workload,
                        out_dir=out_dir / "raw" / stem,
                        label=side,
                        timeout=args.timeout_sec,
                        cache_dir=cache_dir,
                    )
                    runtime_caches[side] = cache_dir

            for side, binary, side_repo in (
                ("legacy", legacy_binary, legacy_repo),
                ("candidate", candidate_binary, repo),
            ):
                run_sample(
                    binary=binary,
                    repo=side_repo,
                    workload=prepared_workload,
                    out_dir=out_dir / "raw" / stem,
                    label=f"warmup-{side}",
                    timeout=args.timeout_sec,
                    startup_ns=startup[side]["median_ns"],
                    runtime_cache=runtime_caches.get(side),
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
                        workload=prepared_workload,
                        out_dir=out_dir / "raw" / stem,
                        label=f"pair-{pair:02d}-{side}",
                        timeout=args.timeout_sec,
                        startup_ns=startup[side]["median_ns"],
                        runtime_cache=runtime_caches.get(side),
                    )
                samples.append(result)
                pair += 1

                if pair == args.pairs:
                    compile_ratios = [
                        sample["candidate"]["module_compile_us"]
                        / sample["legacy"]["module_compile_us"]
                        for sample in samples
                    ]
                    runtime_stats = workload_runtime_stats(workload, samples)
                    runtime_noisy = (
                        runtime_stats is not None
                        and runtime_stats["coefficient_of_variation"] > 0.015
                    )
                    noisy = runtime_noisy or (
                        ratio_stats(compile_ratios)["coefficient_of_variation"]
                        > 0.025
                    )
                    if noisy and args.expanded_pairs > args.pairs:
                        target_pairs = args.expanded_pairs
                        needs_expansion = True

            runtime_stats = workload_runtime_stats(workload, samples)
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
                    "features": workload["features"],
                    "prepared_sha256": sha256(prepared_path),
                    "pairs": len(samples),
                    "runtime": runtime_stats,
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

        runtime_corpus = corpus_ratio_stats(
            [
                [
                    sample["candidate"]["execution_ns"]
                    / sample["legacy"]["execution_ns"]
                    for sample in row["samples"]
                ]
                for row in runtime_rows
            ]
        )
        compile_corpus = corpus_ratio_stats(
            [
                [
                    sample["candidate"]["module_compile_us"]
                    / sample["legacy"]["module_compile_us"]
                    for sample in row["samples"]
                ]
                for row in rows
            ]
        )
        legacy_total = sum(row["code_size"]["legacy_median"] for row in rows)
        candidate_total = sum(row["code_size"]["candidate_median"] for row in rows)
        size_total_ratio = candidate_total / legacy_total
        record_failure(
            failures, "runtime corpus", runtime_corpus, RUNTIME_CORPUS_LIMIT
        )
        record_failure(
            failures, "compile corpus", compile_corpus, COMPILE_CORPUS_LIMIT
        )
        if size_total_ratio > CODE_SIZE_TOTAL_LIMIT:
            failures.append(
                f"total code-size ratio {size_total_ratio:.6f} exceeds {CODE_SIZE_TOTAL_LIMIT:.6f}"
            )

        report = {
            "schema_version": 2,
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
            "runtime_measurement": {
                "mode": "jit-cache-hit-process-elapsed-minus-startup",
                "unit": "nanoseconds-per-internal-iteration",
                "wat_preparation": (
                    "candidate wasmoon-tools wat2wasm; identical wasm for both sides"
                ),
            },
            "startup_calibration": startup,
            "expanded_for_noise": needs_expansion,
            "aggregates": {
                "runtime_corpus_ratio": runtime_corpus["geometric_mean_ratio"],
                "runtime_corpus_upper_95_ratio": runtime_corpus["upper_95_ratio"],
                "runtime_corpus_standard_error_log_ratio": runtime_corpus[
                    "standard_error_log_ratio"
                ],
                "runtime_corpus_degrees_of_freedom": runtime_corpus[
                    "degrees_of_freedom"
                ],
                "compile_corpus_ratio": compile_corpus["geometric_mean_ratio"],
                "compile_corpus_upper_95_ratio": compile_corpus["upper_95_ratio"],
                "compile_corpus_standard_error_log_ratio": compile_corpus[
                    "standard_error_log_ratio"
                ],
                "compile_corpus_degrees_of_freedom": compile_corpus[
                    "degrees_of_freedom"
                ],
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
