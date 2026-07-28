#!/usr/bin/env python3
"""Generate and execute large valid Component Model workloads."""

from __future__ import annotations

import argparse
import json
import resource
import tempfile
import time
from pathlib import Path

from component_hardening_lib import (
    WASM_TOOLS_VERSION,
    compile_component_wat,
    invoke_wasmoon,
    outcome_to_json,
    process_to_json,
    require_tool_version,
    run_process,
    write_json,
)


def large_function_component(functions: int, depth: int) -> tuple[str, str]:
    core_functions = []
    lifted_functions = []
    exports = []
    for index in range(functions):
        core_functions.append(
            f'    (func (export "f{index}") (param i32) (result i32)\n'
            f"      local.get 0 i32.const {index} i32.add)"
        )
        lifted_functions.append(
            f'  (func $f{index} (param "value" u32) (result u32)\n'
            f'    (canon lift (core func $i "f{index}")))'
        )
        exports.append(f'  (export "f{index}" (func $f{index}))')
    instances = ['  (instance $level0 (export "calculate" (func $f0)))']
    for level in range(1, depth):
        instances.append(
            f'  (instance $level{level} (export "next" (instance $level{level - 1})))'
        )
    nested_export = f'  (export "nested" (instance $level{depth - 1}))'
    nested_path = "nested#" + ("next#" * (depth - 1)) + "calculate"
    wat = (
        "(component\n"
        "  (core module $m\n"
        + "\n".join(core_functions)
        + ")\n"
        "  (core instance $i (instantiate $m))\n"
        + "\n".join(lifted_functions)
        + "\n"
        + "\n".join(instances)
        + "\n"
        + "\n".join(exports)
        + "\n"
        + nested_export
        + ")\n"
    )
    return wat, nested_path


def wide_type_component(fields: int) -> str:
    declarations = " ".join(f'(field "f{index}" u32)' for index in range(fields))
    return (
        "(component\n"
        f"  (type $wide (record {declarations}))\n"
        '  (export "wide" (type $wide)))\n'
    )


def deep_type_component(depth: int) -> str:
    declarations = ['  (type $t0 (list u32))']
    for index in range(1, depth):
        declarations.append(f"  (type $t{index} (list $t{index - 1}))")
    declarations.append(f'  (export "deep" (type $t{depth - 1}))')
    return "(component\n" + "\n".join(declarations) + ")\n"


def validation_envelope(result, *, expected_valid: bool) -> bool:
    if result.timed_out or result.returncode < 0:
        return False
    try:
        value = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        return False
    if not isinstance(value, dict) or not isinstance(value.get("ok"), bool):
        return False
    if expected_valid:
        return result.returncode == 0 and value["ok"] is True
    return result.returncode == 1 and value["ok"] is False


def retain_workload_failure(
    root: Path,
    name: str,
    wat: str,
    component: Path | None,
    metadata: dict[str, object],
) -> None:
    destination = root / "failures" / name
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "case.wat").write_text(wat, encoding="utf-8")
    if component is not None and component.exists():
        (destination / "case.component.wasm").write_bytes(component.read_bytes())
    write_json(destination / "failure.json", metadata)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wasmoon", default="./wasmoon")
    parser.add_argument("--wasm-tools", default="wasm-tools")
    parser.add_argument("--functions", type=int, default=512)
    parser.add_argument("--instance-depth", type=int, default=32)
    parser.add_argument("--type-width", type=int, default=512)
    parser.add_argument("--type-depth", type=int, default=64)
    parser.add_argument("--invocations", type=int, default=128)
    parser.add_argument("--timeout-sec", type=float, default=60)
    parser.add_argument("--max-wat-bytes", type=int, default=128 * 1024 * 1024)
    parser.add_argument("--max-component-bytes", type=int, default=64 * 1024 * 1024)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("target/component-hardening/stress"),
    )
    args = parser.parse_args()
    for name in (
        "functions",
        "instance_depth",
        "type_width",
        "type_depth",
        "invocations",
        "max_wat_bytes",
        "max_component_bytes",
    ):
        if getattr(args, name) <= 0:
            parser.error(f"--{name.replace('_', '-')} must be positive")
    try:
        wasm_tools_version = require_tool_version(
            args.wasm_tools, "wasm-tools", WASM_TOOLS_VERSION
        )
    except RuntimeError as error:
        parser.error(str(error))
    generation_started = time.monotonic()
    workloads = [
        (
            "large-functions",
            large_function_component(args.functions, args.instance_depth)[0],
            True,
        ),
        ("wide-type", wide_type_component(args.type_width), True),
        ("deep-type", deep_type_component(args.type_depth), True),
        ("over-limit-type-depth", deep_type_component(101), False),
    ]
    generation_duration = time.monotonic() - generation_started
    report: dict[str, object] = {
        "schema_version": 1,
        "wasm_tools_version": wasm_tools_version,
        "config": {
            "functions": args.functions,
            "instance_depth": args.instance_depth,
            "type_width": args.type_width,
            "type_depth": args.type_depth,
            "invocations": args.invocations,
            "timeout_sec": args.timeout_sec,
            "max_wat_bytes": args.max_wat_bytes,
            "max_component_bytes": args.max_component_bytes,
        },
        "generation_duration_sec": generation_duration,
        "workloads": [],
    }
    failures = 0
    started = time.time()
    with tempfile.TemporaryDirectory(prefix="component-stress-") as directory:
        temporary = Path(directory)
        for name, wat, expected_valid in workloads:
            component = temporary / f"{name}.component.wasm"
            wat_size = len(wat.encode("utf-8"))
            if wat_size > args.max_wat_bytes:
                entry = {
                    "name": name,
                    "wat_size_bytes": wat_size,
                    "expected_valid": expected_valid,
                    "status": "wat-size-limit-exceeded",
                }
                report["workloads"].append(entry)
                retain_workload_failure(args.out_dir, name, wat, None, entry)
                failures += 1
                continue
            compile_result = compile_component_wat(
                args.wasm_tools,
                wat,
                component,
                timeout_sec=args.timeout_sec,
            )
            entry: dict[str, object] = {
                "name": name,
                "wat_size_bytes": wat_size,
                "expected_valid": expected_valid,
                "compile": process_to_json(compile_result),
            }
            if compile_result.timed_out or compile_result.returncode != 0:
                entry["status"] = "compile-failed"
                failures += 1
            else:
                entry["component_size_bytes"] = component.stat().st_size
                if component.stat().st_size > args.max_component_bytes:
                    entry["status"] = "component-size-limit-exceeded"
                    failures += 1
                    report["workloads"].append(entry)
                    retain_workload_failure(
                        args.out_dir,
                        name,
                        wat,
                        component,
                        entry,
                    )
                    continue
                validation = run_process(
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
                entry["validation"] = process_to_json(validation)
                entry["status"] = (
                    "passed"
                    if validation_envelope(
                        validation,
                        expected_valid=expected_valid,
                    )
                    else "validation-failed"
                )
                if entry["status"] != "passed":
                    failures += 1
            report["workloads"].append(entry)
            if entry["status"] != "passed":
                retain_workload_failure(
                    args.out_dir,
                    name,
                    wat,
                    component,
                    entry,
                )
        function_wat, nested_path = large_function_component(
            args.functions, args.instance_depth
        )
        function_component = temporary / "large-functions.component.wasm"
        if function_component.exists():
            invocation_started = time.monotonic()
            invocation_failures = 0
            samples: list[dict[str, object]] = []
            paths = ["f0", f"f{args.functions - 1}", nested_path]
            for index in range(args.invocations):
                path = paths[index % len(paths)]
                value = index & 0xFFFF_FFFF
                expected = value if path in {"f0", nested_path} else (
                    value + args.functions - 1
                ) & 0xFFFF_FFFF
                outcome = invoke_wasmoon(
                    args.wasmoon,
                    function_component,
                    path,
                    [str(value)],
                    timeout_sec=args.timeout_sec,
                )
                if outcome.kind != "success" or outcome.value != [expected]:
                    invocation_failures += 1
                    if len(samples) < 16:
                        samples.append(
                            {
                                "index": index,
                                "path": path,
                                "expected": [expected],
                                "outcome": outcome_to_json(outcome),
                            }
                        )
            report["invocation"] = {
                "executed": args.invocations,
                "failed": invocation_failures,
                "duration_sec": time.monotonic() - invocation_started,
                "failure_samples": samples,
            }
            if invocation_failures:
                retain_workload_failure(
                    args.out_dir,
                    "large-functions-invocation",
                    function_wat,
                    function_component,
                    report["invocation"],
                )
            failures += invocation_failures
    report["failed_cases"] = failures
    report["duration_sec"] = time.time() - started
    report["max_child_rss"] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    write_json(args.out_dir / "report.json", report)
    print(
        f"component stress: {len(workloads)} workloads, "
        f"{args.invocations} invocations, {failures} failures"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
