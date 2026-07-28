#!/usr/bin/env python3
"""Shared deterministic harness for Component Model hardening campaigns."""

from __future__ import annotations

import json
import os
import random
import signal
import subprocess
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence


WASMTIME_VERSION = "45.0.0"
WASM_TOOLS_VERSION = "1.254.0"


@dataclass(frozen=True)
class ProcessResult:
    command: list[str]
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool
    duration_sec: float


@dataclass(frozen=True)
class SemanticOutcome:
    kind: str
    value: Any
    detail: str
    process: ProcessResult


@dataclass(frozen=True)
class InvocationCase:
    name: str
    wat: str
    wasmoon_export: str
    wasmoon_args: list[str]
    wasmtime_invoke: str
    expected: list[Any] | None
    expected_kind: str = "success"
    seed: int | None = None


def run_process(
    command: Sequence[str],
    *,
    timeout_sec: float,
    cwd: Path | None = None,
    stdin: bytes | None = None,
) -> ProcessResult:
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            list(command),
            cwd=str(cwd) if cwd is not None else None,
            stdin=subprocess.PIPE if stdin is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except OSError as error:
        return ProcessResult(
            command=list(command),
            returncode=127,
            stdout="",
            stderr=str(error),
            timed_out=False,
            duration_sec=time.monotonic() - started,
        )
    try:
        stdout, stderr = process.communicate(input=stdin, timeout=timeout_sec)
        timed_out = False
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except OSError:
            process.kill()
        stdout, stderr = process.communicate()
    return ProcessResult(
        command=list(command),
        returncode=process.returncode,
        stdout=stdout.decode("utf-8", errors="replace"),
        stderr=stderr.decode("utf-8", errors="replace"),
        timed_out=timed_out,
        duration_sec=time.monotonic() - started,
    )


def process_to_json(result: ProcessResult) -> dict[str, Any]:
    return asdict(result)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def tool_version(binary: str, *, timeout_sec: float = 10) -> str:
    result = run_process([binary, "--version"], timeout_sec=timeout_sec)
    if result.timed_out or result.returncode != 0:
        raise RuntimeError(
            f"could not read version from {binary}: {result.stderr.strip()}"
        )
    return (result.stdout or result.stderr).strip()


def require_tool_version(binary: str, tool: str, version: str) -> str:
    actual = tool_version(binary)
    expected_prefix = f"{tool} {version}"
    if not actual.startswith(expected_prefix):
        raise RuntimeError(
            f"{tool} version mismatch: expected {version}, found {actual!r}"
        )
    return actual


def compile_component_wat(
    wasm_tools: str,
    wat: str,
    output: Path,
    *,
    timeout_sec: float,
) -> ProcessResult:
    output.parent.mkdir(parents=True, exist_ok=True)
    return run_process(
        [wasm_tools, "parse", "-o", str(output), "-"],
        timeout_sec=timeout_sec,
        stdin=wat.encode("utf-8"),
    )


def classify_wasmoon(result: ProcessResult) -> SemanticOutcome:
    if result.timed_out:
        return SemanticOutcome("timeout", None, "process timed out", result)
    if result.returncode < 0:
        return SemanticOutcome(
            "signal",
            None,
            f"signal {-result.returncode}",
            result,
        )
    text = result.stdout.strip()
    try:
        envelope = json.loads(text)
    except json.JSONDecodeError:
        return SemanticOutcome("malformed", None, text or result.stderr.strip(), result)
    if not isinstance(envelope, dict) or not isinstance(envelope.get("ok"), bool):
        return SemanticOutcome("malformed", None, text, result)
    if envelope["ok"]:
        if result.returncode != 0 or not isinstance(envelope.get("result"), list):
            return SemanticOutcome("malformed", None, text, result)
        return SemanticOutcome("success", envelope["result"], "", result)
    detail = str(envelope.get("detail", ""))
    if result.returncode == 0:
        return SemanticOutcome("malformed", None, detail, result)
    if "trap" in detail.lower():
        return SemanticOutcome("trap", None, detail, result)
    return SemanticOutcome("error", None, detail, result)


def parse_wasmtime_value(text: str) -> Any:
    stripped = text.strip()
    if not stripped:
        raise ValueError("empty Wasmtime result")
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        if stripped == "nan":
            return "nan"
        if stripped in {"inf", "+inf"}:
            return "inf"
        if stripped == "-inf":
            return "-inf"
        raise ValueError(f"unsupported Wasmtime WAVE result {stripped!r}") from None


def classify_wasmtime(result: ProcessResult) -> SemanticOutcome:
    if result.timed_out:
        return SemanticOutcome("timeout", None, "process timed out", result)
    if result.returncode < 0:
        return SemanticOutcome(
            "signal",
            None,
            f"signal {-result.returncode}",
            result,
        )
    if result.returncode == 0:
        try:
            value = parse_wasmtime_value(result.stdout)
        except ValueError as error:
            return SemanticOutcome("malformed", None, str(error), result)
        return SemanticOutcome("success", [value], "", result)
    detail = (result.stderr or result.stdout).strip()
    lowered = detail.lower()
    if "wasm trap" in lowered or "wasm backtrace" in lowered:
        return SemanticOutcome("trap", None, detail, result)
    return SemanticOutcome("error", None, detail, result)


def invoke_wasmoon(
    wasmoon: str,
    component: Path,
    export: str,
    args: Sequence[str],
    *,
    timeout_sec: float,
) -> SemanticOutcome:
    command = [
        wasmoon,
        "component",
        str(component),
        "--invoke",
        export,
        "--error-format",
        "json",
    ]
    for arg in args:
        command.extend(["--arg", arg])
    return classify_wasmoon(run_process(command, timeout_sec=timeout_sec))


def invoke_wasmtime(
    wasmtime: str,
    component: Path,
    invoke: str,
    *,
    timeout_sec: float,
) -> SemanticOutcome:
    return classify_wasmtime(
        run_process(
            [wasmtime, "run", "--invoke", invoke, str(component)],
            timeout_sec=timeout_sec,
        )
    )


def u32(value: int) -> int:
    return value & 0xFFFF_FFFF


def arithmetic_case(seed: int, index: int) -> InvocationCase:
    rng = random.Random((seed << 32) ^ index)
    operation = rng.choice(["i32.add", "i32.sub", "i32.mul", "i32.xor"])
    argument = rng.randrange(0, 1 << 32)
    constant = rng.randrange(0, 1 << 32)
    if operation == "i32.add":
        expected = u32(argument + constant)
    elif operation == "i32.sub":
        expected = u32(argument - constant)
    elif operation == "i32.mul":
        expected = u32(argument * constant)
    else:
        expected = u32(argument ^ constant)
    nested = index % 2 == 1
    nested_declaration = ""
    exports = '  (export "calculate" (func $calculate))'
    wasmoon_export = "calculate"
    wasmtime_export = "calculate"
    if nested:
        nested_declaration = (
            '  (instance $math (export "calculate" (func $calculate)))\n'
        )
        exports = (
            '  (export "oracle" (func $calculate))\n'
            '  (export "math" (instance $math))'
        )
        wasmoon_export = "math#calculate"
        wasmtime_export = "oracle"
    wat = f"""(component
  (core module $m
    (func (export "calculate") (param i32) (result i32)
      local.get 0
      i32.const {constant}
      {operation}))
  (core instance $i (instantiate $m))
  (func $calculate (param "value" u32) (result u32)
    (canon lift (core func $i "calculate")))
{nested_declaration}{exports})
"""
    return InvocationCase(
        name=f"arithmetic-{index:04d}",
        wat=wat,
        wasmoon_export=wasmoon_export,
        wasmoon_args=[str(argument)],
        wasmtime_invoke=f"{wasmtime_export}({argument})",
        expected=[expected],
        seed=seed,
    )


def curated_cases() -> list[InvocationCase]:
    signed = InvocationCase(
        name="signed-negate",
        wat="""(component
  (core module $m
    (func (export "negate") (param i32) (result i32)
      i32.const 0 local.get 0 i32.sub))
  (core instance $i (instantiate $m))
  (func $negate (param "value" s32) (result s32)
    (canon lift (core func $i "negate")))
  (export "negate" (func $negate)))
""",
        wasmoon_export="negate",
        wasmoon_args=["37"],
        wasmtime_invoke="negate(37)",
        expected=[-37],
    )
    floating = InvocationCase(
        name="float-add",
        wat="""(component
  (core module $m
    (func (export "add") (param f64) (result f64)
      local.get 0 f64.const 0.5 f64.add))
  (core instance $i (instantiate $m))
  (func $add (param "value" f64) (result f64)
    (canon lift (core func $i "add")))
  (export "add" (func $add)))
""",
        wasmoon_export="add",
        wasmoon_args=["3.25"],
        wasmtime_invoke="add(3.25)",
        expected=[3.75],
    )
    string = InvocationCase(
        name="string-echo",
        wat="""(component
  (core module $m
    (memory (export "memory") 1)
    (global $heap (mut i32) (i32.const 64))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add global.set $heap
      local.get $p)
    (func (export "echo") (param i32 i32) (result i32)
      i32.const 0 local.get 0 i32.store
      i32.const 4 local.get 1 i32.store
      i32.const 0))
  (core instance $i (instantiate $m))
  (func $echo (param "value" string) (result string)
    (canon lift (core func $i "echo")
      (memory (core memory $i "memory"))
      (realloc (core func $i "realloc"))))
  (export "echo" (func $echo)))
""",
        wasmoon_export="echo",
        wasmoon_args=['"component differential"'],
        wasmtime_invoke='echo("component differential")',
        expected=["component differential"],
    )
    record = InvocationCase(
        name="record-sum",
        wat="""(component
  (core module $m
    (func (export "sum") (param i32 i32) (result i32)
      local.get 0 local.get 1 i32.add))
  (core instance $i (instantiate $m))
  (type $record (record (field "x" u32) (field "y" u32)))
  (export $record-export "record" (type $record))
  (func $sum (param "value" $record-export) (result u32)
    (canon lift (core func $i "sum")))
  (export "sum" (func $sum)))
""",
        wasmoon_export="sum",
        wasmoon_args=['{"x":17,"y":25}'],
        wasmtime_invoke="sum({x: 17, y: 25})",
        expected=[42],
    )
    optional = InvocationCase(
        name="option-some",
        wat="""(component
  (core module $m
    (func (export "unwrap") (param i32 i32) (result i32)
      local.get 0
      if (result i32) local.get 1 else i32.const 99 end))
  (core instance $i (instantiate $m))
  (func $unwrap (param "value" (option u32)) (result u32)
    (canon lift (core func $i "unwrap")))
  (export "unwrap" (func $unwrap)))
""",
        wasmoon_export="unwrap",
        wasmoon_args=['{"some":7}'],
        wasmtime_invoke="unwrap(some(7))",
        expected=[7],
    )
    trapping = InvocationCase(
        name="guest-trap",
        wat="""(component
  (core module $m
    (func (export "fail") (result i32)
      unreachable))
  (core instance $i (instantiate $m))
  (func $fail (result u32)
    (canon lift (core func $i "fail")))
  (export "fail" (func $fail)))
""",
        wasmoon_export="fail",
        wasmoon_args=[],
        wasmtime_invoke="fail()",
        expected=None,
        expected_kind="trap",
    )
    invalid_string_signature = InvocationCase(
        name="invalid-string-result-signature",
        wat="""(component
  (core module $m
    (memory (export "memory") 1)
    (global $heap (mut i32) (i32.const 64))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add global.set $heap
      local.get $p)
    (func (export "echo") (param i32 i32) (result i32 i32)
      local.get 0 local.get 1))
  (core instance $i (instantiate $m))
  (func $echo (param "value" string) (result string)
    (canon lift (core func $i "echo")
      (memory (core memory $i "memory"))
      (realloc (core func $i "realloc"))))
  (export "echo" (func $echo)))
""",
        wasmoon_export="echo",
        wasmoon_args=['"invalid"'],
        wasmtime_invoke='echo("invalid")',
        expected=None,
        expected_kind="error",
    )
    return [
        signed,
        floating,
        string,
        record,
        optional,
        trapping,
        invalid_string_signature,
    ]


def outcome_to_json(outcome: SemanticOutcome) -> dict[str, Any]:
    return {
        "kind": outcome.kind,
        "value": outcome.value,
        "detail": outcome.detail,
        "process": process_to_json(outcome.process),
    }


def retain_failure(
    root: Path,
    case: InvocationCase,
    component: Path | None,
    metadata: dict[str, Any],
) -> Path:
    destination = root / case.name
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "case.wat").write_text(case.wat, encoding="utf-8")
    if component is not None and component.exists():
        (destination / "case.component.wasm").write_bytes(component.read_bytes())
    write_json(destination / "failure.json", metadata)
    return destination
