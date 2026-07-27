#!/usr/bin/env python3
"""Generate component host contracts from the pinned WASI WIT snapshots."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


PRIMITIVES = {
    "bool": "Bool",
    "s8": "S8",
    "u8": "U8",
    "s16": "S16",
    "u16": "U16",
    "s32": "S32",
    "u32": "U32",
    "s64": "S64",
    "u64": "U64",
    "f32": "F32",
    "f64": "F64",
    "char": "Char",
    "string": "String",
    "error-context": "ErrorContext",
}


def moon_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def snapshot_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*.wit")):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(len(relative).to_bytes(4, "little"))
        digest.update(relative)
        contents = path.read_bytes()
        digest.update(len(contents).to_bytes(8, "little"))
        digest.update(contents)
    return digest.hexdigest()


def load_resolution(wasm_tools: str, root: Path, world: str) -> dict[str, Any]:
    command = [
        wasm_tools,
        "component",
        "wit",
        str(root),
        "--json",
        "--generate-nominal-type-ids",
        world,
    ]
    completed = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return json.loads(completed.stdout)


def val_type(value: Any) -> str:
    if isinstance(value, int):
        return f"TypeIdx({value})"
    if isinstance(value, str) and value in PRIMITIVES:
        return f"Prim({PRIMITIVES[value]})"
    raise ValueError(f"unsupported WIT value type: {value!r}")


def optional_val_type(value: Any) -> str:
    return "None" if value is None else f"Some({val_type(value)})"


def resource_key(resolution: dict[str, Any], type_id: int) -> str:
    type_def = resolution["types"][type_id]
    kind = type_def["kind"]
    if isinstance(kind, dict) and "type" in kind:
        target = kind["type"]
        if isinstance(target, int):
            return resource_key(resolution, target)
    if kind != "resource":
        raise ValueError(f"type {type_id} is not a resource")
    owner = type_def.get("owner")
    if not isinstance(owner, dict) or "interface" not in owner:
        raise ValueError(f"resource type {type_id} has no interface owner")
    interface = resolution["interfaces"][owner["interface"]]
    package = resolution["packages"][interface["package"]]["name"]
    return f"{package}/{interface['name']}.{type_def['name']}"


def type_def(resolution: dict[str, Any], type_id: int) -> str:
    definition = resolution["types"][type_id]
    kind = definition["kind"]
    if kind == "resource":
        return f"resolve_resource({moon_string(resource_key(resolution, type_id))})"
    if not isinstance(kind, dict) or len(kind) != 1:
        raise ValueError(f"unsupported WIT type {type_id}: {kind!r}")
    tag, payload = next(iter(kind.items()))
    if tag == "type":
        if isinstance(payload, str):
            return f"Some(DefValType({PRIMITIVES[payload]}))"
        return type_def(resolution, payload)
    if tag == "handle":
        handle_kind, resource = next(iter(payload.items()))
        constructor = "Own" if handle_kind == "own" else "Borrow"
        return f"Some({constructor}({resource}))"
    if tag == "list":
        return f"Some(List({val_type(payload)}))"
    if tag == "option":
        return f"Some(Option({val_type(payload)}))"
    if tag == "tuple":
        values = ", ".join(val_type(value) for value in payload["types"])
        return f"Some(Tuple([{values}]))"
    if tag == "record":
        fields = ", ".join(
            "{ label: "
            + moon_string(field["name"])
            + ", ty: "
            + val_type(field["type"])
            + " }"
            for field in payload["fields"]
        )
        return f"Some(Record([{fields}]))"
    if tag == "variant":
        cases = ", ".join(
            "{ label: "
            + moon_string(case["name"])
            + ", ty: "
            + optional_val_type(case.get("type"))
            + ", refines: None }"
            for case in payload["cases"]
        )
        return f"Some(Variant([{cases}]))"
    if tag == "flags":
        names = ", ".join(moon_string(flag["name"]) for flag in payload["flags"])
        return f"Some(Flags([{names}]))"
    if tag == "enum":
        names = ", ".join(moon_string(case["name"]) for case in payload["cases"])
        return f"Some(Enum([{names}]))"
    if tag == "result":
        return (
            "Some(Result("
            + optional_val_type(payload.get("ok"))
            + ", "
            + optional_val_type(payload.get("err"))
            + "))"
        )
    if tag == "stream":
        return f"Some(Stream({optional_val_type(payload)}))"
    if tag == "future":
        return f"Some(Future({optional_val_type(payload)}))"
    raise ValueError(f"unsupported WIT type kind {tag!r}")


def is_async(kind: Any) -> bool:
    if kind == "async-freestanding":
        return True
    return isinstance(kind, dict) and any(
        key.startswith("async-") for key in kind
    )


def func_type(function: dict[str, Any]) -> str:
    params = ", ".join(
        "{ label: "
        + moon_string(param["name"])
        + ", ty: "
        + val_type(param["type"])
        + " }"
        for param in function.get("params", [])
    )
    result = optional_val_type(function.get("result"))
    return (
        "Some({ is_async: "
        + str(is_async(function["kind"])).lower()
        + ", params: ["
        + params
        + "], result: "
        + result
        + " })"
    )


def interface_name(resolution: dict[str, Any], interface: dict[str, Any]) -> str:
    package = resolution["packages"][interface["package"]]["name"]
    return f"{package}/{interface['name']}"


def emit_snapshot(
    label: str,
    resolution: dict[str, Any],
    digest: str,
) -> list[str]:
    prefix = f"wasi_{label}"
    lines = [
        "///|",
        f"let {prefix}_wit_sha256 : String = {moon_string(digest)}",
        "",
        "///|",
        f"fn {prefix}_resource_names() -> Array[String] {{",
        "  [",
    ]
    resources = sorted(
        {
            resource_key(resolution, index)
            for index, definition in enumerate(resolution["types"])
            if definition["kind"] == "resource"
        }
    )
    lines.extend(f"    {moon_string(name)}," for name in resources)
    lines.extend(["  ]", "}", "", "///|"])
    lines.extend(
        [
            f"fn {prefix}_type_space(",
            "  resolve_resource : (String) -> @component.TypeDef?,",
            ") -> Array[@component.TypeDef?] {",
            "  [",
        ]
    )
    lines.extend(
        f"    {type_def(resolution, index)},"
        for index in range(len(resolution["types"]))
    )
    lines.extend(["  ]", "}", "", "///|"])
    lines.extend(
        [
            f"fn {prefix}_func_type(",
            "  interface : String,",
            "  function : String,",
            ") -> @component.FuncType? {",
            '  match "\\{interface}#\\{function}" {',
        ]
    )
    for interface in resolution["interfaces"]:
        full_name = interface_name(resolution, interface)
        if not full_name.startswith("wasi:"):
            continue
        for name, function in interface["functions"].items():
            key = f"{full_name}#{name}"
            lines.append(f"    {moon_string(key)} => {func_type(function)}")
    lines.extend(["    _ => None", "  }", "}", "", "///|"])
    lines.extend(
        [
            f"fn {prefix}_exported_types(",
            "  interface : String,",
            ") -> Array[(String, Int)] {",
            "  match interface {",
        ]
    )
    for interface in resolution["interfaces"]:
        full_name = interface_name(resolution, interface)
        if not full_name.startswith("wasi:"):
            continue
        exports = ", ".join(
            f"({moon_string(name)}, {index})"
            for name, index in interface["types"].items()
        )
        lines.append(f"    {moon_string(full_name)} => [{exports}]")
    lines.extend(["    _ => []", "  }", "}", ""])
    return lines


def generate(
    wit_root: Path,
    preview2: dict[str, Any],
    preview3: dict[str, Any],
) -> str:
    preview2_root = wit_root / "preview2"
    preview3_root = wit_root / "preview3"
    lines = [
        "// Generated from the pinned official WIT snapshots.",
        "// DO NOT EDIT. Update wit/ and run a Moon development command.",
        "",
    ]
    lines.extend(emit_snapshot("preview2", preview2, snapshot_hash(preview2_root)))
    lines.extend(emit_snapshot("preview3", preview3, snapshot_hash(preview3_root)))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("wit_root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--wasm-tools", default="wasm-tools")
    parser.add_argument("--refresh-json", action="store_true")
    parser.add_argument("--verify-wit", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        json_paths = [
            args.wit_root / "preview2.contracts.json",
            args.wit_root / "preview3.contracts.json",
        ]
        if args.refresh_json or args.verify_wit:
            resolved = [
                load_resolution(
                    args.wasm_tools,
                    args.wit_root / "preview2",
                    "host",
                ),
                load_resolution(
                    args.wasm_tools,
                    args.wit_root / "preview3",
                    "wasi:cli/command",
                ),
            ]
            normalized = [
                json.dumps(value, indent=2, ensure_ascii=False) + "\n"
                for value in resolved
            ]
            if args.verify_wit:
                for path, expected in zip(json_paths, normalized):
                    if not path.exists() or path.read_text() != expected:
                        print(
                            f"error: {path} does not match the pinned WIT",
                            file=sys.stderr,
                        )
                        return 1
            if args.refresh_json:
                for path, contents in zip(json_paths, normalized):
                    path.write_text(contents)
        preview2 = json.loads(json_paths[0].read_text())
        preview3 = json.loads(json_paths[1].read_text())
        generated = generate(args.wit_root, preview2, preview3)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.check:
        if not args.output.exists() or args.output.read_text() != generated:
            print(f"error: {args.output} is stale", file=sys.stderr)
            return 1
        return 0
    if not args.output.exists() or args.output.read_text() != generated:
        args.output.write_text(generated)
        print(f"generated {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
