#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


CONSTRUCTOR_RE = re.compile(r"[A-Z][A-Za-z0-9]*\Z")
WIRE_NAME_RE = re.compile(r"[a-z][a-z0-9_]*\Z")
KIND_TO_TYPE = {"int": "Int", "bool": "Bool", "packed_width": "Int"}
KIND_TO_MOONBIT = {
    "int": "IntegerImmediate",
    "bool": "BooleanImmediate",
    "packed_width": "PackedWidthImmediate",
}
TYPE_PATTERN_TO_MOONBIT = {
    "i32": "ExactType(I32)",
    "i64": "ExactType(I64)",
    "int": "IntegerType",
    "ref": "ExactType(Ref)",
    "callable_ref": "ExactType(CallableRef)",
    "opaque_ref": "ExactType(OpaqueRef)",
    "ref_like": "ReferenceLike",
    "any": "ContextualType",
}


@dataclass(frozen=True)
class Opcode:
    constructor: str
    wire_name: str
    kinds: tuple[str, ...]
    operand_types: tuple[str, ...]
    result_types: tuple[str, ...]
    variadic_operands: bool
    variadic_results: bool


def parse_type_patterns(
    path: Path, line_number: int, encoded: str
) -> tuple[tuple[str, ...], bool]:
    if encoded == "-":
        return (), False
    patterns = encoded.split(",")
    variadic = patterns[-1] == "..."
    if "..." in patterns[:-1]:
        fail(path, line_number, "variadic marker must be the final type pattern")
    fixed = patterns[:-1] if variadic else patterns
    for pattern in fixed:
        if pattern not in TYPE_PATTERN_TO_MOONBIT:
            fail(path, line_number, f"invalid type pattern {pattern!r}")
    return tuple(fixed), variadic


def fail(path: Path, line_number: int, message: str) -> None:
    raise ValueError(f"{path}:{line_number}: {message}")


def parse_schema(path: Path) -> list[Opcode]:
    opcodes: list[Opcode] = []
    constructors: set[str] = set()
    wire_names: set[str] = set()
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) != 5:
            fail(
                path,
                line_number,
                "expected constructor|wire name|immediate kinds|operands|results",
            )
        constructor, wire_name, encoded_kinds, encoded_operands, encoded_results = fields
        if not CONSTRUCTOR_RE.fullmatch(constructor):
            fail(path, line_number, f"invalid constructor {constructor!r}")
        if constructor in constructors:
            fail(path, line_number, f"duplicate constructor {constructor!r}")
        if not WIRE_NAME_RE.fullmatch(wire_name):
            fail(path, line_number, f"invalid wire name {wire_name!r}")
        if wire_name in wire_names:
            fail(path, line_number, f"duplicate wire name {wire_name!r}")
        kinds = () if encoded_kinds == "-" else tuple(encoded_kinds.split(","))
        for kind in kinds:
            if kind not in KIND_TO_TYPE:
                fail(path, line_number, f"invalid immediate kind {kind!r}")
        operand_types, variadic_operands = parse_type_patterns(
            path, line_number, encoded_operands
        )
        result_types, variadic_results = parse_type_patterns(
            path, line_number, encoded_results
        )
        constructors.add(constructor)
        wire_names.add(wire_name)
        opcodes.append(
            Opcode(
                constructor,
                wire_name,
                kinds,
                operand_types,
                result_types,
                variadic_operands,
                variadic_results,
            )
        )
    if not opcodes:
        raise ValueError(f"{path}: schema contains no opcodes")
    return opcodes


def enum_variant(opcode: Opcode) -> str:
    if not opcode.kinds:
        return f"  {opcode.constructor}"
    fields = ", ".join(KIND_TO_TYPE[kind] for kind in opcode.kinds)
    return f"  {opcode.constructor}({fields})"


def immediate_kinds(opcode: Opcode) -> str:
    values = ", ".join(KIND_TO_MOONBIT[kind] for kind in opcode.kinds)
    return f"[{values}]"


def type_patterns(patterns: tuple[str, ...]) -> str:
    values = ", ".join(TYPE_PATTERN_TO_MOONBIT[pattern] for pattern in patterns)
    return f"[{values}]"


def payload_arm(opcode: Opcode, opcode_id: int) -> str:
    if not opcode.kinds:
        return f"    {opcode.constructor} => ({opcode_id}, imm([]))"
    variables = [f"imm{i}" for i in range(len(opcode.kinds))]
    pattern = f"{opcode.constructor}({', '.join(variables)})"
    encoded = [
        f"bool_imm({variable})" if kind == "bool" else variable
        for variable, kind in zip(variables, opcode.kinds, strict=True)
    ]
    return f"    {pattern} => ({opcode_id}, imm([{', '.join(encoded)}]))"


def decode_arm(opcode: Opcode, opcode_id: int) -> str:
    if not opcode.kinds:
        return f"    {opcode_id} => Some({opcode.constructor})"
    decoded = [
        f"imm_bool(imms[{index}])" if kind == "bool" else f"imms[{index}]"
        for index, kind in enumerate(opcode.kinds)
    ]
    return f"    {opcode_id} => Some({opcode.constructor}({', '.join(decoded)}))"


def spec_entry(opcode: Opcode, opcode_id: int) -> list[str]:
    return [
        "  {",
        f"    id: {opcode_id},",
        f'    typed_constructor: "{opcode.constructor}",',
        f'    wire_name: "{opcode.wire_name}",',
        f"    immediate_kinds: {immediate_kinds(opcode)},",
        f"    operand_types: {type_patterns(opcode.operand_types)},",
        f"    result_types: {type_patterns(opcode.result_types)},",
        f"    variadic_operands: {str(opcode.variadic_operands).lower()},",
        f"    variadic_results: {str(opcode.variadic_results).lower()},",
        "  },",
    ]


def generate(opcodes: list[Opcode], schema_name: str) -> str:
    lines = [
        f"// Generated by tools/generate_wasm_opcodes.py from {schema_name}.",
        "// DO NOT EDIT. Update the schema and run a Moon development command.",
        "",
        "///|",
        "pub(all) enum WasmOpcode {",
        *(enum_variant(opcode) for opcode in opcodes),
        "} derive(Debug, Eq, Hash)",
        "",
        "///|",
        "let wasm_opcode_specs : Array[WasmOpcodeSpec] = [",
    ]
    for opcode_id, opcode in enumerate(opcodes):
        lines.extend(spec_entry(opcode, opcode_id))
    lines.extend([
        "]",
        "",
        "///|",
        "fn opcode_payload(opcode : WasmOpcode) -> (Int, FixedArray[Int]) {",
        "  match opcode {",
        *(payload_arm(opcode, opcode_id) for opcode_id, opcode in enumerate(opcodes)),
        "  }",
        "}",
        "",
        "///|",
        "fn opcode_from_payload(",
        "  id : Int,",
        "  imms : FixedArray[Int],",
        ") -> WasmOpcode? {",
        "  match id {",
        *(decode_arm(opcode, opcode_id) for opcode_id, opcode in enumerate(opcodes)),
        "    _ => None",
        "  }",
        "}",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        generated = generate(parse_schema(args.input), args.input.name)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.check:
        try:
            current = args.output.read_text()
        except OSError as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        if current != generated:
            print(f"error: {args.output} is stale", file=sys.stderr)
            return 1
        return 0
    if not args.output.exists() or args.output.read_text() != generated:
        args.output.write_text(generated)
        print(f"generated {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
