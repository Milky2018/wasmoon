#!/usr/bin/env python3
"""Record and validate machine-readable ISS-193 cutover evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def command_output(command: list[str]) -> str:
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        return f"unavailable: {error}"


def required_job(value: str) -> tuple[str, str]:
    name, separator, result = value.partition("=")
    if not separator or not name or not result:
        raise argparse.ArgumentTypeError(
            "required job must have the form NAME=RESULT"
        )
    return name, result


def init(args: argparse.Namespace) -> int:
    baseline = load(args.baseline)
    workload = Path(baseline["workload_manifest"])
    payload = {
        "schema_version": 1,
        "kind": args.kind,
        "target": args.target,
        "candidate_commit": command_output(["git", "rev-parse", "HEAD"]),
        "candidate_parent_commit": command_output(["git", "rev-parse", "HEAD^"]),
        "legacy_commit": baseline["legacy_commit"],
        "generated_at_unix_sec": int(time.time()),
        "host": {
            "system": platform.system(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "uname_m": command_output(["uname", "-m"]),
            "os_release": platform.release(),
        },
        "toolchain": {
            "moon": command_output(["moon", "version", "--all"]),
            "python": platform.python_version(),
        },
        "inputs": {
            "baseline": str(args.baseline),
            "baseline_sha256": sha256(args.baseline),
            "workloads": str(workload),
            "workloads_sha256": sha256(workload),
        },
        "commands": [],
        "artifacts": [],
        "failures": [],
        "decision": "incomplete",
    }
    write(args.manifest, payload)
    return 0


def run(args: argparse.Namespace) -> int:
    if not args.command:
        raise SystemExit("run requires a command after --")
    command = args.command[1:] if args.command[0] == "--" else args.command
    payload = load(args.manifest)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with args.log.open("w", encoding="utf-8") as output:
        process = subprocess.run(
            command,
            stdout=output,
            stderr=subprocess.STDOUT,
            check=False,
            text=True,
        )
    record = {
        "name": args.name,
        "argv": command,
        "shell": shlex.join(command),
        "started_at_unix_sec": started,
        "duration_sec": time.time() - started,
        "exit_status": process.returncode,
        "log": str(args.log),
        "log_sha256": sha256(args.log),
    }
    payload["commands"].append(record)
    payload["artifacts"].append(
        {"kind": "command-log", "path": str(args.log), "sha256": record["log_sha256"]}
    )
    if process.returncode != 0:
        payload["failures"].append(
            f"command {args.name!r} exited with {process.returncode}"
        )
    write(args.manifest, payload)
    sys.stdout.write(args.log.read_text(encoding="utf-8"))
    return process.returncode


def attach(args: argparse.Namespace) -> int:
    payload = load(args.manifest)
    if not args.path.exists():
        raise SystemExit(f"artifact does not exist: {args.path}")
    payload["artifacts"].append(
        {"kind": args.kind, "path": str(args.path), "sha256": sha256(args.path)}
    )
    write(args.manifest, payload)
    return 0


def finalize(args: argparse.Namespace) -> int:
    payload = load(args.manifest)
    required = set(filter(None, args.required.split(",")))
    records = {record["name"]: record for record in payload["commands"]}
    missing = sorted(required - records.keys())
    if missing:
        payload["failures"].append(f"missing required commands: {', '.join(missing)}")
    for name in sorted(required & records.keys()):
        if records[name]["exit_status"] != 0:
            failure = f"required command {name!r} failed"
            if failure not in payload["failures"]:
                payload["failures"].append(failure)

    if args.perf_report is not None:
        if not args.perf_report.exists():
            payload["failures"].append(f"missing performance report: {args.perf_report}")
        else:
            report = load(args.perf_report)
            payload["performance"] = {
                "path": str(args.perf_report),
                "sha256": sha256(args.perf_report),
                "decision": report.get("decision"),
                "aggregates": report.get("aggregates"),
                "thresholds": report.get("thresholds"),
            }
            payload["artifacts"].append(
                {
                    "kind": "paired-performance-report",
                    "path": str(args.perf_report),
                    "sha256": sha256(args.perf_report),
                }
            )
            if report.get("decision") != "pass":
                payload["failures"].append("performance report did not pass")

    payload["decision"] = "pass" if not payload["failures"] else "fail"
    payload["finalized_at_unix_sec"] = int(time.time())
    write(args.manifest, payload)
    print(json.dumps({"manifest": str(args.manifest), "decision": payload["decision"], "failures": payload["failures"]}, indent=2))
    return 0 if payload["decision"] == "pass" else 2


def combine(args: argparse.Namespace) -> int:
    manifests = [load(path) for path in args.inputs]
    failures: list[str] = []
    required_jobs = dict(args.required_job)
    for name, result in sorted(required_jobs.items()):
        if result != "success":
            failures.append(f"required job {name!r} result is {result!r}")
    commits = {manifest.get("candidate_commit") for manifest in manifests}
    if len(commits) != 1:
        failures.append(f"candidate commits disagree: {sorted(commits)}")
    for path, manifest in zip(args.inputs, manifests):
        if manifest.get("decision") != "pass":
            failures.append(f"{path} decision is {manifest.get('decision')!r}")
    payload = {
        "schema_version": 1,
        "kind": "machv-cutover-combined",
        "candidate_commit": next(iter(commits)) if len(commits) == 1 else None,
        "generated_at_unix_sec": int(time.time()),
        "required_jobs": required_jobs,
        "manifests": [
            {
                "path": str(path),
                "sha256": sha256(path),
                "kind": manifest.get("kind"),
                "target": manifest.get("target"),
                "decision": manifest.get("decision"),
            }
            for path, manifest in zip(args.inputs, manifests)
        ],
        "failures": failures,
        "decision": "pass" if not failures else "fail",
    }
    write(args.out, payload)
    return 0 if not failures else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    init_parser = subparsers.add_parser("init")
    init_parser.add_argument("--manifest", type=Path, required=True)
    init_parser.add_argument("--baseline", type=Path, required=True)
    init_parser.add_argument("--kind", required=True)
    init_parser.add_argument("--target", required=True)
    init_parser.set_defaults(function=init)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--manifest", type=Path, required=True)
    run_parser.add_argument("--name", required=True)
    run_parser.add_argument("--log", type=Path, required=True)
    run_parser.add_argument("command", nargs=argparse.REMAINDER)
    run_parser.set_defaults(function=run)

    attach_parser = subparsers.add_parser("attach")
    attach_parser.add_argument("--manifest", type=Path, required=True)
    attach_parser.add_argument("--kind", required=True)
    attach_parser.add_argument("--path", type=Path, required=True)
    attach_parser.set_defaults(function=attach)

    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("--manifest", type=Path, required=True)
    finalize_parser.add_argument("--required", required=True)
    finalize_parser.add_argument("--perf-report", type=Path)
    finalize_parser.set_defaults(function=finalize)

    combine_parser = subparsers.add_parser("combine")
    combine_parser.add_argument("--out", type=Path, required=True)
    combine_parser.add_argument(
        "--required-job", action="append", default=[], type=required_job
    )
    combine_parser.add_argument("inputs", nargs="+", type=Path)
    combine_parser.set_defaults(function=combine)

    args = parser.parse_args()
    return args.function(args)


if __name__ == "__main__":
    raise SystemExit(main())
