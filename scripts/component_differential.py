#!/usr/bin/env python3
"""Compare typed component invocation with the pinned current Wasmtime."""

from __future__ import annotations

import argparse
import tempfile
import time
from pathlib import Path

from component_hardening_lib import (
    WASM_TOOLS_VERSION,
    WASMTIME_VERSION,
    arithmetic_case,
    compile_component_wat,
    curated_cases,
    invoke_wasmoon,
    invoke_wasmtime,
    outcome_to_json,
    process_to_json,
    require_tool_version,
    retain_failure,
    write_json,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wasmoon", default="./wasmoon")
    parser.add_argument("--wasmtime", required=True)
    parser.add_argument("--wasm-tools", default="wasm-tools")
    parser.add_argument("--seed", type=int, default=0xC0_4D_50)
    parser.add_argument("--cases", type=int, default=32)
    parser.add_argument("--timeout-sec", type=float, default=20)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("target/component-hardening/differential"),
    )
    args = parser.parse_args()
    if args.cases <= 0:
        parser.error("--cases must be positive")
    started = time.time()
    failures = args.out_dir / "failures"
    reports: list[dict[str, object]] = []
    failed = 0
    try:
        wasmtime_version = require_tool_version(
            args.wasmtime, "wasmtime", WASMTIME_VERSION
        )
        wasm_tools_version = require_tool_version(
            args.wasm_tools, "wasm-tools", WASM_TOOLS_VERSION
        )
    except RuntimeError as error:
        parser.error(str(error))
    cases = curated_cases()
    cases.extend(arithmetic_case(args.seed, i) for i in range(args.cases))
    with tempfile.TemporaryDirectory(prefix="component-differential-") as directory:
        temporary = Path(directory)
        for case in cases:
            component = temporary / f"{case.name}.component.wasm"
            compile_result = compile_component_wat(
                args.wasm_tools,
                case.wat,
                component,
                timeout_sec=args.timeout_sec,
            )
            entry: dict[str, object] = {
                "name": case.name,
                "seed": case.seed,
                "expected": case.expected,
                "expected_kind": case.expected_kind,
                "compile": process_to_json(compile_result),
            }
            if compile_result.timed_out or compile_result.returncode != 0:
                entry["status"] = "compile-failed"
                failed += 1
                retain_failure(failures, case, component, entry)
                reports.append(entry)
                continue
            wasmoon = invoke_wasmoon(
                args.wasmoon,
                component,
                case.wasmoon_export,
                case.wasmoon_args,
                timeout_sec=args.timeout_sec,
            )
            wasmtime = invoke_wasmtime(
                args.wasmtime,
                component,
                case.wasmtime_invoke,
                timeout_sec=args.timeout_sec,
            )
            entry["wasmoon"] = outcome_to_json(wasmoon)
            entry["wasmtime"] = outcome_to_json(wasmtime)
            matches = (
                wasmoon.kind == case.expected_kind
                and wasmtime.kind == case.expected_kind
                and (
                    case.expected_kind != "success"
                    or (
                        wasmoon.value == wasmtime.value
                        and wasmoon.value == case.expected
                    )
                )
            )
            entry["status"] = "passed" if matches else "mismatch"
            if not matches:
                failed += 1
                retain_failure(failures, case, component, entry)
            reports.append(entry)
    summary = {
        "schema_version": 1,
        "seed": args.seed,
        "generated_cases": args.cases,
        "curated_cases": len(curated_cases()),
        "executed_cases": len(reports),
        "failed_cases": failed,
        "wasmtime_version": wasmtime_version,
        "wasm_tools_version": wasm_tools_version,
        "duration_sec": time.time() - started,
        "cases": reports,
    }
    write_json(args.out_dir / "report.json", summary)
    print(
        f"component differential: {len(reports) - failed}/{len(reports)} passed "
        f"against Wasmtime {WASMTIME_VERSION}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
