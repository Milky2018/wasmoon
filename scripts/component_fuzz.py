#!/usr/bin/env python3
"""Deterministic Component Model parser, validator, and invocation fuzzing."""

from __future__ import annotations

import argparse
import json
import random
import tempfile
import time
from pathlib import Path

from component_hardening_lib import (
    WASM_TOOLS_VERSION,
    arithmetic_case,
    compile_component_wat,
    invoke_wasmoon,
    outcome_to_json,
    process_to_json,
    require_tool_version,
    run_process,
    write_json,
)


DEFAULT_SEEDS = [
    Path("modules/wasmoon/testsuite/fixtures/minimal.component.wasm"),
    Path("modules/wasmoon/testsuite/fixtures/wasi-command-ok.component.wasm"),
    Path("modules/wasmoon/testsuite/fixtures/wasi-command-async-ok.component.wasm"),
]


def mutate(data: bytes, rng: random.Random, index: int) -> tuple[str, bytes]:
    mode = index % 5
    if mode == 0:
        end = rng.randrange(0, len(data) + 1)
        return "truncate", data[:end]
    if mode == 1:
        output = bytearray(data)
        if output:
            offset = rng.randrange(len(output))
            output[offset] ^= 1 << rng.randrange(8)
        return "bit-flip", bytes(output)
    if mode == 2:
        offset = rng.randrange(0, len(data) + 1)
        count = rng.randrange(1, 9)
        inserted = bytes(rng.randrange(256) for _ in range(count))
        return "insert", data[:offset] + inserted + data[offset:]
    if mode == 3:
        if not data:
            return "delete", data
        start = rng.randrange(len(data))
        end = min(len(data), start + rng.randrange(1, 9))
        return "delete", data[:start] + data[end:]
    output = bytearray(data)
    if len(output) > 9:
        offset = rng.randrange(9, len(output))
        output[offset] = 0xFF
    return "section-length", bytes(output)


def classify_validation(result) -> tuple[bool, str]:
    if result.timed_out:
        return False, "timeout"
    if result.returncode < 0:
        return False, "signal"
    if result.returncode not in {0, 1}:
        return False, "unexpected-exit"
    try:
        envelope = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        return False, "malformed-output"
    if not isinstance(envelope, dict) or not isinstance(envelope.get("ok"), bool):
        return False, "malformed-output"
    if result.returncode == 0 and not envelope["ok"]:
        return False, "inconsistent-success"
    if result.returncode == 1 and envelope["ok"]:
        return False, "inconsistent-error"
    return True, "accepted" if envelope["ok"] else "rejected"


def retain_binary_failure(
    root: Path,
    name: str,
    data: bytes,
    metadata: dict[str, object],
) -> None:
    destination = root / name
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "case.component.wasm").write_bytes(data)
    write_json(destination / "failure.json", metadata)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wasmoon", default="./wasmoon")
    parser.add_argument("--wasm-tools", default="wasm-tools")
    parser.add_argument("--seed", type=int, default=0xF0_22)
    parser.add_argument("--mutations", type=int, default=128)
    parser.add_argument("--valid-cases", type=int, default=32)
    parser.add_argument("--timeout-sec", type=float, default=10)
    parser.add_argument("--input", type=Path, action="append", dest="inputs")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("target/component-hardening/fuzz"),
    )
    args = parser.parse_args()
    if args.mutations < 0 or args.valid_cases < 0:
        parser.error("case counts cannot be negative")
    if args.mutations + args.valid_cases == 0:
        parser.error("fuzz campaign must execute at least one case")
    try:
        wasm_tools_version = require_tool_version(
            args.wasm_tools, "wasm-tools", WASM_TOOLS_VERSION
        )
    except RuntimeError as error:
        parser.error(str(error))
    inputs = args.inputs or DEFAULT_SEEDS
    missing = [str(path) for path in inputs if not path.is_file()]
    if missing:
        parser.error(f"missing fuzz seed inputs: {', '.join(missing)}")
    rng = random.Random(args.seed)
    failures = args.out_dir / "failures"
    mutation_reports: list[dict[str, object]] = []
    valid_reports: list[dict[str, object]] = []
    failed = 0
    started = time.time()
    with tempfile.TemporaryDirectory(prefix="component-fuzz-") as directory:
        temporary = Path(directory)
        for index in range(args.mutations):
            source = inputs[index % len(inputs)]
            mode, data = mutate(source.read_bytes(), rng, index)
            case_name = f"mutation-{index:05d}"
            component = temporary / f"{case_name}.component.wasm"
            component.write_bytes(data)
            result = run_process(
                [
                    args.wasmoon,
                    "component",
                    str(component),
                    "--validate",
                    "--error-format",
                    "json",
                ],
                timeout_sec=args.timeout_sec,
            )
            ok, outcome = classify_validation(result)
            report = {
                "name": case_name,
                "source": str(source),
                "mutation": mode,
                "input_size": len(data),
                "outcome": outcome,
                "process": process_to_json(result),
            }
            if not ok:
                failed += 1
                retain_binary_failure(failures, case_name, data, report)
            mutation_reports.append(report)
        for index in range(args.valid_cases):
            case = arithmetic_case(args.seed, index)
            component = temporary / f"{case.name}.component.wasm"
            compile_result = compile_component_wat(
                args.wasm_tools,
                case.wat,
                component,
                timeout_sec=args.timeout_sec,
            )
            report = {
                "name": case.name,
                "compile": process_to_json(compile_result),
                "expected": case.expected,
            }
            if compile_result.timed_out or compile_result.returncode != 0:
                report["status"] = "compile-failed"
                failed += 1
            else:
                outcome = invoke_wasmoon(
                    args.wasmoon,
                    component,
                    case.wasmoon_export,
                    case.wasmoon_args,
                    timeout_sec=args.timeout_sec,
                )
                report["invoke"] = outcome_to_json(outcome)
                report["status"] = (
                    "passed"
                    if outcome.kind == "success" and outcome.value == case.expected
                    else "failed"
                )
                if report["status"] != "passed":
                    failed += 1
            if report["status"] != "passed":
                destination = failures / case.name
                destination.mkdir(parents=True, exist_ok=True)
                (destination / "case.wat").write_text(case.wat, encoding="utf-8")
                if component.exists():
                    (destination / "case.component.wasm").write_bytes(
                        component.read_bytes()
                    )
                write_json(destination / "failure.json", report)
            valid_reports.append(report)
    summary = {
        "schema_version": 1,
        "seed": args.seed,
        "wasm_tools_version": wasm_tools_version,
        "mutation_cases": len(mutation_reports),
        "valid_cases": len(valid_reports),
        "executed_cases": len(mutation_reports) + len(valid_reports),
        "failed_cases": failed,
        "duration_sec": time.time() - started,
        "mutations": mutation_reports,
        "valid": valid_reports,
    }
    write_json(args.out_dir / "report.json", summary)
    print(
        f"component fuzz: {summary['executed_cases'] - failed}/"
        f"{summary['executed_cases']} passed"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
