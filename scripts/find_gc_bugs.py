#!/usr/bin/env python3
"""Differential GC bug finder across interpreter/JIT/stress modes."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_TIMEOUT_SECONDS = int(os.environ.get("WASMOON_GC_DIFF_TIMEOUT", "20"))


@dataclass(frozen=True)
class Mode:
    name: str
    no_jit: bool
    extra_env: dict[str, str]


MODES: tuple[Mode, ...] = (
    Mode(name="interp", no_jit=True, extra_env={}),
    Mode(name="jit", no_jit=False, extra_env={}),
    Mode(
        name="jit_stress_verify",
        no_jit=False,
        extra_env={"WASMOON_GC_STRESS": "1", "WASMOON_GC_VERIFY": "1"},
    ),
)


def parse_result(output: str, return_code: int) -> dict[str, Any]:
    passed = 0
    failed = 0
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Passed:"):
            passed = int(line.split(":", maxsplit=1)[1].strip())
        elif line.startswith("Failed:"):
            failed = int(line.split(":", maxsplit=1)[1].strip())

    if return_code != 0 and "Passed:" not in output:
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        tail = " | ".join(lines[-3:]) if lines else f"exit {return_code}"
        return {"status": "crash", "passed": 0, "failed": 0, "error": tail}
    if failed > 0:
        return {"status": "fail", "passed": passed, "failed": failed, "error": None}
    if return_code == 0:
        return {"status": "pass", "passed": passed, "failed": failed, "error": None}
    return {"status": "error", "passed": passed, "failed": failed, "error": f"exit {return_code}"}


def run_one(
    repo_root: Path,
    wasmoon_bin: Path,
    wast_file: Path,
    mode: Mode,
    timeout_seconds: int,
) -> dict[str, Any]:
    cmd = [str(wasmoon_bin), "test", str(wast_file)]
    if mode.no_jit:
        cmd.append("--no-jit")
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
        return {"status": "timeout", "passed": 0, "failed": 0, "error": "timeout"}
    except Exception as exc:  # noqa: BLE001
        return {"status": "error", "passed": 0, "failed": 0, "error": str(exc)}

    output = completed.stdout + completed.stderr
    result = parse_result(output, completed.returncode)
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
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    wasmoon_bin = repo_root / "wasmoon"
    if not wasmoon_bin.exists():
        print("Error: ./wasmoon not found. Run ./install.sh first.")
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
            "regressions": [],
            "issues": [],
        },
    }

    for wast in wast_files:
        rel = str(wast.relative_to(test_dir))
        file_results: dict[str, Any] = {}
        for mode in MODES:
            result = run_one(repo_root, wasmoon_bin, wast, mode, args.timeout)
            file_results[mode.name] = result
        report["files"][rel] = file_results

        interp_status = file_results["interp"]["status"]
        jit_status = file_results["jit"]["status"]
        stress_status = file_results["jit_stress_verify"]["status"]
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

        print(
            f"{rel:50} interp={interp_status:8} jit={jit_status:8} stress={stress_status:8}"
        )

    output_path = (repo_root / args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print("\nSummary:")
    print(f"  interp pass:  {report['summary']['interp_pass']}/{len(wast_files)}")
    print(f"  jit pass:     {report['summary']['jit_pass']}/{len(wast_files)}")
    print(f"  stress pass:  {report['summary']['stress_pass']}/{len(wast_files)}")
    print(f"  issues:       {len(report['summary']['issues'])}")
    print(f"  regressions:  {len(report['summary']['regressions'])}")
    print(f"  report json:  {output_path}")

    if report["summary"]["regressions"] or report["summary"]["issues"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
