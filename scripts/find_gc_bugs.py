#!/usr/bin/env python3
"""Differential GC bug finder across interpreter/JIT/stress modes."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_TIMEOUT_SECONDS = int(os.environ.get("WASMOON_GC_DIFF_TIMEOUT", "20"))


@dataclass(frozen=True)
class Mode:
    name: str
    runner: str
    no_jit: bool
    extra_env: dict[str, str]


MODES: tuple[Mode, ...] = (
    Mode(name="interp", runner="wasmoon", no_jit=True, extra_env={}),
    Mode(name="jit", runner="wasmoon", no_jit=False, extra_env={}),
    Mode(
        name="jit_stress_verify",
        runner="wasmoon",
        no_jit=False,
        extra_env={
            "WASMOON_GC_STRESS": "1",
            "WASMOON_GC_STRESS_EVERY": "1",
            "WASMOON_GC_VERIFY": "1",
            "WASMOON_GC_HEAP_CAPACITY": "4096",
        },
    ),
    Mode(
        name="jit_stress_small_heap",
        runner="wasmoon",
        no_jit=False,
        extra_env={
            "WASMOON_GC_STRESS": "1",
            "WASMOON_GC_STRESS_EVERY": "1",
            "WASMOON_GC_VERIFY": "1",
            "WASMOON_GC_HEAP_CAPACITY": "2048",
            "WASMOON_GC_ALLOC_DEBUG": "1",
        },
    ),
)

TRAP_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"JIT Trap:\s*(.+)"),
    re.compile(r"runtime error:\s*(.+)", re.IGNORECASE),
    re.compile(r"trap:\s*(.+)", re.IGNORECASE),
    re.compile(r"Error:\s*(.+)"),
)

GC_COLLECT_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(
        r"\[GC COLLECT\]\s+stack_roots=(\d+)\s+store_roots=(\d+)\s+table_roots=(\d+)\s+total=(\d+)\s+collected=(-?\d+)"
    ),
    re.compile(
        r"\[GC COLLECT\]\s+stack_roots=(\d+)\s+store_roots=(\d+)\s+total=(\d+)\s+collected=(-?\d+)"
    ),
    re.compile(
        r"\[GC COLLECT\]\s+roots=(\d+)\s+scratch=(\d+)\s+total=(\d+)\s+collected=(-?\d+)"
    ),
)
GC_ALLOC_PATTERN = re.compile(
    r"\[GC ALLOC\]\s+\S+\s+retries=(\d+)\s+collected=(-?\d+)"
)


def normalize_trap_signature(raw: str) -> str:
    stripped = raw.strip().lower()
    stripped = re.sub(r"0x[0-9a-f]+", "0x*", stripped)
    stripped = re.sub(r"\b\d+\b", "#", stripped)
    stripped = re.sub(r"\s+", " ", stripped)
    return stripped


def extract_trap_signature(output: str) -> str | None:
    for line in output.splitlines():
        for pattern in TRAP_PATTERNS:
            matched = pattern.search(line)
            if matched:
                return normalize_trap_signature(matched.group(1))
    return None


def extract_gc_metrics(output: str) -> dict[str, int]:
    max_root_count = 0
    collect_events = 0
    retry_count = 0

    for line in output.splitlines():
        for collect_pattern in GC_COLLECT_PATTERNS:
            collect_match = collect_pattern.search(line)
            if collect_match:
                collect_events += 1
                groups = collect_match.groups()
                if len(groups) >= 5:
                    total_roots = int(groups[3])
                else:
                    total_roots = int(groups[2])
                max_root_count = max(max_root_count, total_roots)
                break
        else:
            collect_match = None
        if collect_match:
            continue
        alloc_match = GC_ALLOC_PATTERN.search(line)
        if alloc_match:
            retry_count += int(alloc_match.group(1))

    return {
        "root_count": max_root_count,
        "gc_collect_events": collect_events,
        "gc_retry_count": retry_count,
    }


def parse_result(output: str, return_code: int, runner: str) -> dict[str, Any]:
    passed = 0
    failed = 0
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Passed:"):
            passed = int(line.split(":", maxsplit=1)[1].strip())
        elif line.startswith("Failed:"):
            failed = int(line.split(":", maxsplit=1)[1].strip())

    trap_signature = extract_trap_signature(output)
    metrics = extract_gc_metrics(output)

    if runner == "wasmtime":
        if return_code == 0:
            return {
                "status": "pass",
                "passed": 1,
                "failed": 0,
                "error": None,
                "trap_signature": None,
                **metrics,
            }
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        tail = " | ".join(lines[-3:]) if lines else f"exit {return_code}"
        return {
            "status": "crash",
            "passed": 0,
            "failed": 0,
            "error": tail,
            "trap_signature": trap_signature,
            **metrics,
        }

    if return_code != 0 and "Passed:" not in output:
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        tail = " | ".join(lines[-3:]) if lines else f"exit {return_code}"
        return {
            "status": "crash",
            "passed": 0,
            "failed": 0,
            "error": tail,
            "trap_signature": trap_signature,
            **metrics,
        }
    if failed > 0:
        return {
            "status": "fail",
            "passed": passed,
            "failed": failed,
            "error": None,
            "trap_signature": trap_signature,
            **metrics,
        }
    if return_code == 0:
        return {
            "status": "pass",
            "passed": passed,
            "failed": failed,
            "error": None,
            "trap_signature": None,
            **metrics,
        }
    return {
        "status": "error",
        "passed": passed,
        "failed": failed,
        "error": f"exit {return_code}",
        "trap_signature": trap_signature,
        **metrics,
    }


def run_one(
    repo_root: Path,
    wasmoon_bin: Path,
    wasmtime_bin: Path | None,
    wast_file: Path,
    mode: Mode,
    timeout_seconds: int,
) -> dict[str, Any]:
    if mode.runner == "wasmoon":
        cmd = [str(wasmoon_bin), "test", str(wast_file)]
        if mode.no_jit:
            cmd.append("--no-jit")
    elif mode.runner == "wasmtime":
        if wasmtime_bin is None:
            return {
                "status": "skip",
                "passed": 0,
                "failed": 0,
                "error": "wasmtime not found",
                "trap_signature": None,
            }
        if wast_file.suffix == ".wast":
            cmd = [str(wasmtime_bin), "wast", "-W", "gc", str(wast_file)]
        else:
            cmd = [str(wasmtime_bin), "run", "-W", "gc", str(wast_file)]
    else:
        return {
            "status": "error",
            "passed": 0,
            "failed": 0,
            "error": f"unknown runner: {mode.runner}",
            "trap_signature": None,
        }

    env = os.environ.copy()
    env.update(mode.extra_env)
    try:
        completed = subprocess.run(
            cmd,
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return {
            "status": "timeout",
            "passed": 0,
            "failed": 0,
            "error": "timeout",
            "trap_signature": None,
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "status": "error",
            "passed": 0,
            "failed": 0,
            "error": str(exc),
            "trap_signature": None,
        }

    output = completed.stdout + completed.stderr
    result = parse_result(output, completed.returncode, mode.runner)
    if result["status"] != "pass":
        result["stdout_tail"] = "\n".join(output.splitlines()[-20:])
    return result


def collect_wast_files(root: Path, recursive: bool) -> list[Path]:
    pattern = "**/*.wast" if recursive else "*.wast"
    return sorted(root.glob(pattern))


def main() -> None:
    parser = argparse.ArgumentParser(description="Differential GC bug finder")
    parser.add_argument("--dir", default="spec/gc", help="Directory containing .wast files")
    parser.add_argument("--rec", action="store_true", help="Recursively search subdirectories")
    parser.add_argument(
        "--match",
        default="",
        help="Only run files whose relative path contains this substring",
    )
    parser.add_argument(
        "--max-files",
        type=int,
        default=0,
        help="Run at most N files (0 means no limit)",
    )
    parser.add_argument(
        "--output",
        default="tmp/gc_diff_report.json",
        help="Path to write JSON report",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"Per-test timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS})",
    )
    parser.add_argument(
        "--with-wasmtime",
        action="store_true",
        help="Add wasmtime as an extra differential lane",
    )
    parser.add_argument(
        "--fault-alloc-at",
        type=int,
        default=0,
        help="Enable extra lane with allocation failure injected at Nth alloc",
    )
    parser.add_argument(
        "--fault-alloc-every",
        type=int,
        default=0,
        help="Enable extra lane with failure on every Kth allocation",
    )
    parser.add_argument(
        "--wasmtime-bin",
        default="wasmtime",
        help="Path to wasmtime binary (default: wasmtime on PATH)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    wasmoon_bin = repo_root / "wasmoon"
    if not wasmoon_bin.exists():
        print("Error: ./wasmoon not found. Run ./install.sh first.")
        sys.exit(1)
    wasmtime_bin: Path | None = None
    if args.with_wasmtime:
        candidate = Path(args.wasmtime_bin)
        if candidate.is_file():
            wasmtime_bin = candidate
        else:
            resolved = shutil.which(args.wasmtime_bin)
            if resolved:
                wasmtime_bin = Path(resolved)
        if wasmtime_bin is None:
            print(f"Error: wasmtime not found: {args.wasmtime_bin}")
            sys.exit(1)

    test_dir = repo_root / args.dir
    if not test_dir.exists():
        print(f"Error: directory does not exist: {test_dir}")
        sys.exit(1)

    wast_files = collect_wast_files(test_dir, args.rec)
    if args.match:
        wast_files = [
            path
            for path in wast_files
            if args.match in str(path.relative_to(test_dir))
        ]
    if args.max_files > 0:
        wast_files = wast_files[: args.max_files]
    if not wast_files:
        print(f"No .wast files found under {test_dir}")
        sys.exit(1)

    print(f"Running GC differential on {len(wast_files)} files from {test_dir}")

    report: dict[str, Any] = {
        "test_dir": str(test_dir),
        "files": {},
        "summary": {
            "total_files": len(wast_files),
            "interp_pass": 0,
            "jit_pass": 0,
            "stress_pass": 0,
            "small_heap_pass": 0,
            "regressions": [],
            "issues": [],
            "trap_mismatches": [],
            "fault_inject_non_pass": 0,
        },
    }

    modes: list[Mode] = list(MODES)
    if args.fault_alloc_at > 0 or args.fault_alloc_every > 0:
        fault_env: dict[str, str] = {}
        if args.fault_alloc_at > 0:
            fault_env["WASMOON_GC_FAIL_ALLOC_AT"] = str(args.fault_alloc_at)
        if args.fault_alloc_every > 0:
            fault_env["WASMOON_GC_FAIL_ALLOC_EVERY"] = str(args.fault_alloc_every)
        modes.append(
            Mode(
                name="jit_fault_inject",
                runner="wasmoon",
                no_jit=False,
                extra_env=fault_env,
            )
        )
    if args.with_wasmtime:
        modes.append(
            Mode(name="wasmtime", runner="wasmtime", no_jit=False, extra_env={})
        )

    for wast in wast_files:
        rel = str(wast.relative_to(test_dir))
        file_results: dict[str, Any] = {}
        for mode in modes:
            result = run_one(
                repo_root, wasmoon_bin, wasmtime_bin, wast, mode, args.timeout
            )
            file_results[mode.name] = result
        report["files"][rel] = file_results

        interp_status = file_results["interp"]["status"]
        jit_status = file_results["jit"]["status"]
        stress_status = file_results["jit_stress_verify"]["status"]
        small_heap_status = file_results["jit_stress_small_heap"]["status"]
        if interp_status == "pass":
            report["summary"]["interp_pass"] += 1
        else:
            report["summary"]["issues"].append(
                {"file": rel, "mode": "interp", "status": interp_status}
            )
        if jit_status == "pass":
            report["summary"]["jit_pass"] += 1
        else:
            report["summary"]["issues"].append(
                {"file": rel, "mode": "jit", "status": jit_status}
            )
        if stress_status == "pass":
            report["summary"]["stress_pass"] += 1
        else:
            report["summary"]["issues"].append(
                {"file": rel, "mode": "jit_stress_verify", "status": stress_status}
            )
        if small_heap_status == "pass":
            report["summary"]["small_heap_pass"] += 1
        else:
            report["summary"]["issues"].append(
                {"file": rel, "mode": "jit_stress_small_heap", "status": small_heap_status}
            )
        if "jit_fault_inject" in file_results:
            fault_status = file_results["jit_fault_inject"]["status"]
            if fault_status != "pass":
                report["summary"]["fault_inject_non_pass"] += 1

        if interp_status == "pass" and jit_status != "pass":
            report["summary"]["regressions"].append(
                {"file": rel, "kind": "interp_pass_jit_not_pass", "jit": jit_status}
            )
        if jit_status == "pass" and stress_status != "pass":
            report["summary"]["regressions"].append(
                {
                    "file": rel,
                    "kind": "jit_pass_stress_not_pass",
                    "stress": stress_status,
                }
            )
        if jit_status == "pass" and small_heap_status != "pass":
            report["summary"]["regressions"].append(
                {
                    "file": rel,
                    "kind": "jit_pass_small_heap_not_pass",
                    "small_heap": small_heap_status,
                }
            )

        if "wasmtime" in file_results:
            wasmtime_status = file_results["wasmtime"]["status"]
            if wasmtime_status == "pass" and jit_status != "pass":
                report["summary"]["regressions"].append(
                    {
                        "file": rel,
                        "kind": "wasmtime_pass_jit_not_pass",
                        "jit": jit_status,
                    }
                )
            jit_trap = file_results["jit"].get("trap_signature")
            wasmtime_trap = file_results["wasmtime"].get("trap_signature")
            if jit_status != "pass" and wasmtime_status != "pass":
                if jit_trap and wasmtime_trap and jit_trap != wasmtime_trap:
                    report["summary"]["trap_mismatches"].append(
                        {
                            "file": rel,
                            "jit_trap": jit_trap,
                            "wasmtime_trap": wasmtime_trap,
                        }
                    )

        mode_statuses = [
            f"interp={interp_status:8}",
            f"jit={jit_status:8}",
            f"stress={stress_status:8}",
            f"small={small_heap_status:8}",
        ]
        if "jit_fault_inject" in file_results:
            mode_statuses.append(
                f"fault={file_results['jit_fault_inject']['status']:8}"
            )
        if "wasmtime" in file_results:
            mode_statuses.append(
                f"wasmtime={file_results['wasmtime']['status']:8}"
            )
        print(f"{rel:50} {' '.join(mode_statuses)}")

    output_path = (repo_root / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print("\nSummary:")
    print(f"  interp pass:  {report['summary']['interp_pass']}/{len(wast_files)}")
    print(f"  jit pass:     {report['summary']['jit_pass']}/{len(wast_files)}")
    print(f"  stress pass:  {report['summary']['stress_pass']}/{len(wast_files)}")
    print(f"  small pass:   {report['summary']['small_heap_pass']}/{len(wast_files)}")
    print(f"  issues:       {len(report['summary']['issues'])}")
    print(f"  regressions:  {len(report['summary']['regressions'])}")
    print(f"  trap mismatch:{len(report['summary']['trap_mismatches'])}")
    if "jit_fault_inject" in [mode.name for mode in modes]:
        print(
            f"  fault non-pass:{report['summary']['fault_inject_non_pass']}/{len(wast_files)}"
        )
    print(f"  report json:  {output_path}")

    if (
        report["summary"]["regressions"]
        or report["summary"]["issues"]
        or report["summary"]["trap_mismatches"]
    ):
        sys.exit(1)


if __name__ == "__main__":
    main()
