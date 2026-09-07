#!/usr/bin/env python3
"""Run the pinned Wasmtime misc_testsuite with explicit host-contract exclusions."""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

from run_wasmtime_p1 import digest, execute
from run_component_wast import iter_forms, first_symbol

ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "wasm-tests/wasmtime"
SUITE = "tests/misc_testsuite"
WASM_TOOLS_VERSION = "1.254.0"


def test_config(text: str) -> dict:
    lines = []
    for line in text.splitlines():
        if not line.startswith(";;!"):
            break
        lines.append(line[3:])
    config = tomllib.loads("\n".join(lines))
    if any(type(value) is not bool for value in config.values()):
        raise ValueError("upstream test configuration must contain boolean values")
    return config


def validate_snapshot(corpus: Path = CORPUS) -> tuple[dict, list[dict]]:
    snapshot = json.loads((corpus / "SNAPSHOT.json").read_text())
    if not re.fullmatch(r"[0-9a-f]{40}", snapshot["commit"]):
        raise ValueError("snapshot must pin a full upstream commit")
    entries = snapshot["files"]
    expected = {e["path"] for e in entries}
    actual = {p.relative_to(corpus / "upstream").as_posix()
              for p in (corpus / "upstream").rglob("*") if p.is_file()}
    if len(expected) != len(entries) or actual != expected:
        raise ValueError("upstream inventory differs from SNAPSHOT.json")
    cases = []
    for entry in entries:
        path = corpus / "upstream" / entry["path"]
        if digest(path) != entry["sha256"]:
            raise ValueError(f"upstream hash mismatch: {entry['path']}")
        if not entry["path"].startswith(SUITE + "/") or path.suffix != ".wast":
            continue
        text = path.read_text()
        name = path.relative_to(corpus / "upstream" / SUITE).as_posix()
        # Include components nested in assertion forms, not only standalone definitions.
        component = bool(re.search(r"\(component(?:\s|\))", text))
        forms = [first_symbol(form) for form in iter_forms(text)]
        cases.append({"commands": forms, "name": name, "path": str(path.resolve()), "sha256": entry["sha256"],
                      "lane": "component" if component else "core", "config": test_config(text)})
    contracts = json.loads((corpus / "HOST_CONTRACTS.json").read_text())
    if not set(contracts).issubset(c["name"] for c in cases):
        raise ValueError("stale host-contract exclusion")
    for case in cases:
        case["host_contract"] = contracts.get(case["name"])
    if not cases:
        raise ValueError("snapshot has no WAST scripts")
    return snapshot, sorted(cases, key=lambda c: c["name"])


def exclusion(case: dict, include_high_memory: bool) -> tuple[str, str] | None:
    if case["host_contract"]:
        return "unsupported", case["host_contract"]
    if case["config"].get("hogs_memory") and not include_high_memory:
        return "deferred", "Upstream marks this test hogs_memory; opt in with --include-high-memory."
    return None


def parse_core_result(result: dict, commands: list[str] | None = None) -> dict:
    if result["status"] in {"timeout", "harness_error"}:
        return result
    text = Path(result["stdout"]).read_text(errors="replace")
    matches = re.findall(r"(?m)^Results:\s*\n\s*Passed:\s*(\d+)\s*\n\s*Failed:\s*(\d+)\s*\n\s*Skipped:\s*(\d+)\s*$", text)
    if len(matches) != 1:
        return result | {"status": "fail", "detail": "Missing or ambiguous complete WAST result block"}
    passed, failed, skipped = map(int, matches[0])
    result.update(passed=passed, failed=failed, skipped=skipped)
    if result["returncode"] or failed or skipped:
        result.update(status="fail", detail=f"exit={result['returncode']}, passed={passed}, failed={failed}, skipped={skipped}")
    elif not passed:
        if commands and set(commands).issubset({"module", "register", "invoke"}):
            result.update(status="script_only", detail="Completed module/action script with no assertion commands")
        else:
            result.update(status="fail", detail="Zero passing assertions without a module/action-only script")
    trace = re.search(r"WAST JIT trace: attempts=(\d+) compiled_modules=(\d+) compiled_functions=(\d+)", text)
    if trace:
        result["jit_compilation"] = dict(zip(("attempts", "modules", "functions"), map(int, trace.groups())))
    return result


def component_worker(path: Path, binary: Path, moon_tools: Path, wasm_tools: Path, mode: str) -> int:
    from run_component_wast import run_file
    os.environ["WASMOON_COMPONENT_SHARED_PROCESS_GROUP"] = "1"
    temporary = Path.cwd() / "work"
    temporary.mkdir()
    tempfile.tempdir = str(temporary)
    result = run_file(path, binary, moon_tools, wasm_tools, no_jit=mode == "interp")
    print("MISC_COMPONENT_RESULT " + json.dumps(result), flush=True)
    return int(bool(result["failed"] or result["skipped"] or not result["passed"]))


def run_case(case: dict, mode: str, binary: Path, output: Path, timeout: float,
             moon_tools: Path, wasm_tools: Path, include_high_memory: bool = False) -> dict:
    record = case | {"mode": mode}
    if omitted := exclusion(case, include_high_memory):
        return record | {"status": omitted[0], "detail": omitted[1]}
    directory = output / mode / case["name"]
    directory.mkdir(parents=True)
    if case["lane"] == "core":
        command = [str(binary), "test", case["path"]]
        if mode == "interp":
            command.append("--no-jit")
        result = parse_core_result(execute(command, directory, timeout), case["commands"])
    else:
        command = [sys.executable, str(Path(__file__).resolve()), "--component-worker", case["path"],
                   "--wasmoon", str(binary), "--wasmoon-tools", str(moon_tools),
                   "--wasm-tools", str(wasm_tools), "--mode", mode]
        result = execute(command, directory, timeout)
        if result["status"] not in {"timeout", "harness_error"}:
            text = Path(result["stdout"]).read_text(errors="replace")
            lines = [l.removeprefix("MISC_COMPONENT_RESULT ") for l in text.splitlines()
                     if l.startswith("MISC_COMPONENT_RESULT ")]
            if len(lines) != 1:
                result.update(status="fail", detail="Missing component adapter result")
            else:
                counts = json.loads(lines[0])
                result.update(counts)
                if result["returncode"] or counts["failed"] or counts["skipped"] or not counts["passed"]:
                    result.update(status="fail", detail="Component adapter reported failed, skipped or zero passing commands")
    return record | result


def verdict(results: list[dict]) -> int:
    if any(r["status"] == "harness_error" for r in results):
        return 2
    return int(any(r["status"] in {"fail", "timeout"} for r in results)
               or not any(r["status"] in {"pass", "script_only"} for r in results))


def executable(path: Path) -> Path:
    resolved = Path(shutil.which(str(path)) or path).resolve()
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise ValueError(f"missing executable: {path}")
    return resolved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["both", "interp", "jit"], default="both")
    parser.add_argument("--lane", choices=["all", "core", "component"], default="all")
    parser.add_argument("--filter", action="append", help="Repeatable glob over suite-relative WAST paths (default: *)")
    parser.add_argument("--wasmoon", type=Path, default=ROOT / "wasmoon")
    parser.add_argument("--wasmoon-tools", type=Path, default=ROOT / "wasmoon-tools")
    parser.add_argument("--wasm-tools", type=Path, default=Path("wasm-tools"))
    parser.add_argument("--timeout", type=float, default=30, help="Seconds per file and engine")
    parser.add_argument("--output", type=Path, help="New or empty evidence directory")
    parser.add_argument("--include-high-memory", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--component-worker", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.component_worker:
        return component_worker(args.component_worker, args.wasmoon, args.wasmoon_tools, args.wasm_tools, args.mode)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    try:
        snapshot, cases = validate_snapshot()
        filters = args.filter or ["*"]
        if args.check:
            print(f"Verified {len(cases)} WAST scripts at {snapshot['commit']}")
            return 0
        cases = [c for c in cases if any(fnmatch.fnmatchcase(c["name"], pattern) for pattern in filters)
                 and (args.lane == "all" or c["lane"] == args.lane)]
        if not cases:
            parser.error("selection matched no WAST scripts")
        if args.list:
            for case in cases:
                omitted = exclusion(case, args.include_high_memory)
                print(f"{case['lane']:9} {case['name']}" + (f" [{omitted[0]}: {omitted[1]}]" if omitted else ""))
            return 0
        binary = executable(args.wasmoon)
        moon_tools, wasm_tools = args.wasmoon_tools, args.wasm_tools
        component = any(c["lane"] == "component" and not exclusion(c, args.include_high_memory) for c in cases)
        tool_versions = {}
        if component:
            moon_tools, wasm_tools = executable(moon_tools), executable(wasm_tools)
            version = subprocess.check_output([str(wasm_tools), "--version"], text=True).strip()
            if version != f"wasm-tools {WASM_TOOLS_VERSION}":
                raise ValueError(f"component adapter requires wasm-tools {WASM_TOOLS_VERSION}, found {version}")
            tool_versions = {"wasm_tools": version, "wasmoon_tools_sha256": digest(moon_tools)}
        if args.output:
            output = args.output.resolve()
            output.mkdir(parents=True, exist_ok=True)
            if any(output.iterdir()):
                parser.error("--output must be empty; previous evidence is never overwritten")
        else:
            parent = ROOT / "target/wasmtime-misc-results"
            parent.mkdir(parents=True, exist_ok=True)
            output = Path(tempfile.mkdtemp(prefix="run-", dir=parent)).resolve()
        os.environ["WASMOON_WAST_JIT_TRACE"] = "1"
        os.environ["WASMOON_WAST_REGISTER_NAMED_MODULES"] = "1"
        results = []
        report = {"register_named_modules": True, "upstream_commit": snapshot["commit"], "snapshot_sha256": digest(CORPUS / "SNAPSHOT.json"),
                  "host_contracts_sha256": digest(CORPUS / "HOST_CONTRACTS.json"),
                  "host": platform.platform(), "engine": str(binary), "engine_sha256": digest(binary),
                  "engine_version": subprocess.check_output([str(binary), "--version"], text=True).strip(),
                  "tools": tool_versions, "filter": filters, "lane": args.lane,
                  "timeout": args.timeout, "include_high_memory": args.include_high_memory, "results": results}
        print(f"Results: {output}", flush=True)
        for case in cases:
            for mode in (["interp", "jit"] if args.mode == "both" else [args.mode]):
                result = run_case(case, mode, binary, output, args.timeout, moon_tools, wasm_tools, args.include_high_memory)
                results.append(result)
                report["counts"] = {status: sum(r["status"] == status for r in results)
                                    for status in ("pass", "script_only", "fail", "timeout", "unsupported", "deferred", "harness_error")}
                (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
                print(f"{mode:6} {result['status']:12} {case['name']} {result.get('detail', '')}", flush=True)
        print(json.dumps(report["counts"]), flush=True)
        return verdict(results)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Misc harness error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
