#!/usr/bin/env python3
"""Run component-model .wast tests with wasmoon validation harness."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple


def skip_line_comment(text: str, i: int) -> int:
    while i < len(text) and text[i] != "\n":
        i += 1
    return i


def skip_block_comment(text: str, i: int) -> int:
    depth = 1
    i += 2
    while i < len(text) and depth > 0:
        if text[i] == "(" and i + 1 < len(text) and text[i + 1] == ";":
            depth += 1
            i += 2
            continue
        if text[i] == ";" and i + 1 < len(text) and text[i + 1] == ")":
            depth -= 1
            i += 2
            continue
        i += 1
    return i


def skip_ws_and_comments(text: str, i: int) -> int:
    while i < len(text):
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if c == ";" and i + 1 < len(text) and text[i + 1] == ";":
            i = skip_line_comment(text, i + 2)
            continue
        if c == "(" and i + 1 < len(text) and text[i + 1] == ";":
            i = skip_block_comment(text, i)
            continue
        break
    return i


@dataclass(frozen=True)
class StringToken:
    value: str


def parse_string(text: str, i: int) -> Tuple[Optional[StringToken], int]:
    if i >= len(text) or text[i] != "\"":
        return None, i
    i += 1
    out: list[str] = []
    while i < len(text):
        c = text[i]
        if c == "\"":
            return StringToken("".join(out)), i + 1
        if c == "\\":
            i += 1
            if i >= len(text):
                break
            esc = text[i]
            if esc == "n":
                out.append("\n")
            elif esc == "t":
                out.append("\t")
            elif esc == "r":
                out.append("\r")
            elif esc == "\"":
                out.append("\"")
            elif esc == "\\":
                out.append("\\")
            elif esc == "u" and i + 1 < len(text) and text[i + 1] == "{":
                j = i + 2
                while j < len(text) and text[j] != "}":
                    j += 1
                if j < len(text):
                    hex_digits = text[i + 2 : j]
                    try:
                        out.append(chr(int(hex_digits, 16)))
                        i = j
                    except ValueError:
                        out.append("u")
                else:
                    out.append("u")
            else:
                out.append(esc)
            i += 1
            continue
        out.append(c)
        i += 1
    return None, i


def parse_atom(text: str, i: int) -> Tuple[Optional[str], int]:
    i = skip_ws_and_comments(text, i)
    start = i
    while i < len(text) and not text[i].isspace() and text[i] not in ("(", ")"):
        i += 1
    if start == i:
        return None, i
    return text[start:i], i


def parse_sexpr(text: str, i: int = 0):
    i = skip_ws_and_comments(text, i)
    if i >= len(text):
        return None, i
    if text[i] == "(":
        i += 1
        items: list[object] = []
        while i < len(text):
            i = skip_ws_and_comments(text, i)
            if i < len(text) and text[i] == ")":
                return items, i + 1
            item, i = parse_sexpr(text, i)
            if item is None:
                break
            items.append(item)
        return items, i
    if text[i] == "\"":
        return parse_string(text, i)
    atom, i = parse_atom(text, i)
    return atom, i


def parse_form(form: str):
    node, _ = parse_sexpr(form, 0)
    return node


def extract_expected_message(node, idx: int = 2) -> Optional[str]:
    if isinstance(node, list) and len(node) > idx:
        msg = node[idx]
        if isinstance(msg, StringToken):
            return msg.value
    return None


def read_symbol(text: str, i: int) -> Tuple[Optional[str], int]:
    i = skip_ws_and_comments(text, i)
    if i >= len(text):
        return None, i
    start = i
    while i < len(text) and not text[i].isspace() and text[i] not in ("(", ")"):
        i += 1
    if start == i:
        return None, i
    return text[start:i], i


def iter_forms(text: str):
    i = 0
    depth = 0
    start = None
    in_string = False
    escape = False
    block_depth = 0
    while i < len(text):
        c = text[i]
        if block_depth > 0:
            if c == "(" and i + 1 < len(text) and text[i + 1] == ";":
                block_depth += 1
                i += 2
                continue
            if c == ";" and i + 1 < len(text) and text[i + 1] == ")":
                block_depth -= 1
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if escape:
                escape = False
                i += 1
                continue
            if c == "\\":
                escape = True
                i += 1
                continue
            if c == "\"":
                in_string = False
            i += 1
            continue
        if c == ";" and i + 1 < len(text) and text[i + 1] == ";":
            i = skip_line_comment(text, i + 2)
            continue
        if c == "(" and i + 1 < len(text) and text[i + 1] == ";":
            block_depth = 1
            i += 2
            continue
        if c == "\"":
            in_string = True
            i += 1
            continue
        if c == "(":
            if depth == 0:
                start = i
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0 and start is not None:
                yield text[start : i + 1]
                start = None
        i += 1


def first_symbol(form: str) -> Optional[str]:
    sym, _ = read_symbol(form, 1)
    return sym


def extract_form(text: str, start: int) -> Optional[str]:
    i = start
    depth = 0
    in_string = False
    escape = False
    block_depth = 0
    while i < len(text):
        c = text[i]
        if block_depth > 0:
            if c == "(" and i + 1 < len(text) and text[i + 1] == ";":
                block_depth += 1
                i += 2
                continue
            if c == ";" and i + 1 < len(text) and text[i + 1] == ")":
                block_depth -= 1
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if escape:
                escape = False
                i += 1
                continue
            if c == "\\":
                escape = True
                i += 1
                continue
            if c == "\"":
                in_string = False
            i += 1
            continue
        if c == ";" and i + 1 < len(text) and text[i + 1] == ";":
            i = skip_line_comment(text, i + 2)
            continue
        if c == "(" and i + 1 < len(text) and text[i + 1] == ";":
            block_depth = 1
            i += 2
            continue
        if c == "\"":
            in_string = True
            i += 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
        i += 1
    return None


def find_component_form(form: str) -> Optional[str]:
    i = 0
    in_string = False
    escape = False
    block_depth = 0
    while i < len(form):
        c = form[i]
        if block_depth > 0:
            if c == "(" and i + 1 < len(form) and form[i + 1] == ";":
                block_depth += 1
                i += 2
                continue
            if c == ";" and i + 1 < len(form) and form[i + 1] == ")":
                block_depth -= 1
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if escape:
                escape = False
                i += 1
                continue
            if c == "\\":
                escape = True
                i += 1
                continue
            if c == "\"":
                in_string = False
            i += 1
            continue
        if c == ";" and i + 1 < len(form) and form[i + 1] == ";":
            i = skip_line_comment(form, i + 2)
            continue
        if c == "(" and i + 1 < len(form) and form[i + 1] == ";":
            block_depth = 1
            i += 2
            continue
        if c == "\"":
            in_string = True
            i += 1
            continue
        if c == "(":
            sym, _ = read_symbol(form, i + 1)
            if sym == "component":
                return extract_form(form, i)
        i += 1
    return None


def normalize_component_form(form: str) -> Tuple[Optional[str], str]:
    sym1, i = read_symbol(form, 1)
    if sym1 != "component":
        return None, "unknown"
    sym2, j = read_symbol(form, i)
    if sym2 == "definition":
        sym3, k = read_symbol(form, j)
        if sym3 and sym3.startswith("$"):
            rest = form[k:]
            return "(component " + sym3 + rest, "definition"
        rest = form[j:]
        return "(component" + rest, "definition"
    if sym2 == "instance":
        return None, "instance"
    return form, "component"


SUPPORTED_VALUE_TYPES = {
    "bool",
    "u8",
    "s8",
    "u16",
    "s16",
    "u32",
    "s32",
    "u64",
    "s64",
    "char",
    "str",
    "string",
}

UNSUPPORTED_ERROR_SUBSTRINGS = [
    "unsupported component type opcode",
    "unsupported canon opcode",
    "unsupported component preamble",
    "unsupported string encoding",
    "unsupportedstringencoding",
    "unsupportedcomponent",
]


def parse_component_name(node) -> Optional[str]:
    if isinstance(node, list) and len(node) > 1:
        name = node[1]
        if isinstance(name, str) and name.startswith("$"):
            return name
    return None


def parse_component_definition_name(node) -> Optional[str]:
    if isinstance(node, list) and len(node) > 2:
        if node[1] == "definition":
            name = node[2]
            if isinstance(name, str) and name.startswith("$"):
                return name
    return None


def parse_component_instance(node) -> Optional[Tuple[str, str]]:
    if (
        isinstance(node, list)
        and len(node) > 3
        and node[0] == "component"
        and node[1] == "instance"
    ):
        inst = node[2]
        comp = node[3]
        if isinstance(inst, str) and isinstance(comp, str):
            return inst, comp
    return None


def parse_const(node) -> Optional[dict]:
    if not isinstance(node, list) or not node:
        return None
    head = node[0]
    if not isinstance(head, str) or not head.endswith(".const"):
        return None
    type_name = head[: -len(".const")]
    if type_name not in SUPPORTED_VALUE_TYPES:
        return None
    if type_name in ("str", "string", "char"):
        if len(node) < 2 or not isinstance(node[1], StringToken):
            return None
        return {"type": type_name, "value": node[1].value}
    if len(node) < 2 or not isinstance(node[1], str):
        return None
    return {"type": type_name, "value": node[1]}


def parse_invoke(node) -> Optional[dict]:
    if not isinstance(node, list) or not node or node[0] != "invoke":
        return None
    idx = 1
    instance = None
    if idx < len(node) and isinstance(node[idx], str) and node[idx].startswith("$"):
        instance = node[idx]
        idx += 1
    if idx >= len(node) or not isinstance(node[idx], StringToken):
        return None
    field = node[idx].value
    idx += 1
    args: list[dict] = []
    for arg in node[idx:]:
        val = parse_const(arg)
        if val is None:
            return None
        args.append(val)
    return {"instance": instance, "field": field, "args": args}


def has_unsupported_string_encoding(form: str) -> bool:
    return "string-encoding=utf16" in form or "string-encoding=latin1+utf16" in form


def has_root_imports(node: object) -> bool:
    if not isinstance(node, list) or not node:
        return False
    if node[0] != "component":
        return False
    for child in node[1:]:
        if isinstance(child, list) and child and child[0] == "import":
            return True
    return False


def should_instantiate_component(node: object) -> bool:
    # Only root imports require host bindings; nested component imports can be
    # satisfied by internal instantiation wiring.
    return not has_root_imports(node)


def compile_component(
    text: str, tmp: Path, idx: int
) -> Tuple[Optional[Path], Optional[str]]:
    src = tmp / f"component_{idx}.wat"
    out = tmp / f"component_{idx}.wasm"
    src.write_text(text, encoding="utf-8")
    result = subprocess.run(
        ["wasm-tools", "parse", str(src), "-o", str(out)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip()
        return None, err or "wasm-tools parse failed"
    return out, None


def validate_component(
    component_bin: Path, wasmoon: Path, *, wit_names: bool
) -> Tuple[bool, str]:
    cmd = [str(wasmoon), "component", "--validate", str(component_bin)]
    if not wit_names:
        cmd.insert(2, "--no-wit-names")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
    )
    out = (result.stdout or "") + (result.stderr or "")
    if "validate component error" in out or "parse component error" in out:
        return False, out.strip()
    if "component validated ok" in out:
        return True, out.strip()
    return False, out.strip() or "unknown validation result"


def wit_names_for_path(wast_file: Path) -> bool:
    # wasm-tools' suite validates the WIT component encoding, which imposes
    # kebab-case/package-name name rules. wasmtime's suite uses arbitrary names.
    return "wasmtime" not in wast_file.parts


def is_unsupported_error(msg: str) -> bool:
    lower = msg.lower()
    return any(token in lower for token in UNSUPPORTED_ERROR_SUBSTRINGS)


def run_component_script(
    script: dict, wasmoon: Path, tmp: Path
) -> Tuple[int, int, int, list[str], str, bool]:
    script_path = tmp / "component_script.json"
    script_path.write_text(
        json.dumps(script, ensure_ascii=True, indent=2),
        encoding="utf-8",
    )
    result = subprocess.run(
        [str(wasmoon), "component-test", str(script_path)],
        capture_output=True,
        text=True,
    )
    out = (result.stdout or "") + (result.stderr or "")
    passed = failed = skipped = 0
    failures: list[str] = []
    saw_result = False
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("RESULT "):
            saw_result = True
            parts = line[len("RESULT ") :].split()
            for part in parts:
                if part.startswith("passed="):
                    passed = int(part.split("=", 1)[1])
                elif part.startswith("failed="):
                    failed = int(part.split("=", 1)[1])
                elif part.startswith("skipped="):
                    skipped = int(part.split("=", 1)[1])
        elif line.startswith("FAIL "):
            failures.append(line[len("FAIL ") :])
    return passed, failed, skipped, failures, out.strip(), saw_result


def should_skip_file(path: Path) -> bool:
    parts = set(path.parts)
    if {"async", "resources"} & parts:
        return True
    if path.name == "resources.wast":
        return True
    if path.name == "trap-in-post-return.wast":
        return True
    return False


def run_file(path: Path, wasmoon: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    passed = failed = skipped = 0
    failures: list[str] = []
    defined_components: set[str] = set()
    anon_def_count = 0
    wit_names = wit_names_for_path(path)
    if should_skip_file(path):
        for _ in iter_forms(text):
            skipped += 1
        return {
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "failures": failures,
        }
    commands: list[dict] = []
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        comp_idx = 0
        for form in iter_forms(text):
            cmd = first_symbol(form)
            if cmd == "component":
                node = parse_form(form)
                normalized, kind = normalize_component_form(form)
                if has_unsupported_string_encoding(form):
                    skipped += 1
                    continue
                if kind == "instance":
                    inst = parse_component_instance(node)
                    if inst is None:
                        skipped += 1
                        continue
                    inst_name, comp_name = inst
                    if comp_name not in defined_components:
                        skipped += 1
                        continue
                    commands.append(
                        {
                            "type": "component_instance",
                            "name": inst_name,
                            "component": comp_name,
                        }
                    )
                    continue
                if normalized is None:
                    skipped += 1
                    continue
                comp_bin, err = compile_component(normalized, tmp_path, comp_idx)
                comp_idx += 1
                if comp_bin is None:
                    failed += 1
                    failures.append(f"component parse failed: {err}")
                    continue
                ok, msg = validate_component(comp_bin, wasmoon, wit_names=wit_names)
                if not ok:
                    if is_unsupported_error(msg):
                        skipped += 1
                        continue
                    failed += 1
                    failures.append(f"component validate failed: {msg}")
                    continue
                if kind == "definition":
                    name = parse_component_definition_name(node)
                    if not name:
                        anon_def_count += 1
                        name = f"$anon_def_{anon_def_count}"
                    commands.append(
                        {
                            "type": "component_definition",
                            "name": name,
                            "path": str(comp_bin),
                        }
                    )
                    if name:
                        defined_components.add(name)
                else:
                    name = parse_component_name(node)
                    commands.append(
                        {
                            "type": "component",
                            "name": name,
                            "path": str(comp_bin),
                            "instantiate": should_instantiate_component(node),
                        }
                    )
                    if name:
                        defined_components.add(name)
            elif cmd == "assert_invalid":
                node = parse_form(form)
                expected_msg = extract_expected_message(node)
                component_form = find_component_form(form)
                if not component_form:
                    skipped += 1
                    continue
                normalized, kind = normalize_component_form(component_form)
                if component_form and has_unsupported_string_encoding(component_form):
                    skipped += 1
                    continue
                if kind == "instance" or normalized is None:
                    skipped += 1
                    continue
                comp_bin, err = compile_component(normalized, tmp_path, comp_idx)
                comp_idx += 1
                if comp_bin is None:
                    failed += 1
                    if expected_msg:
                        failures.append(f"assert_invalid parse failed: {expected_msg}: {err}")
                    else:
                        failures.append(f"assert_invalid parse failed: {err}")
                    continue
                ok, msg = validate_component(comp_bin, wasmoon, wit_names=wit_names)
                if ok:
                    failed += 1
                    if expected_msg:
                        failures.append(
                            f"assert_invalid unexpectedly validated: {expected_msg}"
                        )
                    else:
                        failures.append("assert_invalid unexpectedly validated")
                elif is_unsupported_error(msg):
                    skipped += 1
                else:
                    passed += 1
            elif cmd == "assert_malformed":
                node = parse_form(form)
                expected_msg = extract_expected_message(node)
                component_form = find_component_form(form)
                if not component_form:
                    skipped += 1
                    continue
                normalized, kind = normalize_component_form(component_form)
                if component_form and has_unsupported_string_encoding(component_form):
                    skipped += 1
                    continue
                if kind == "instance" or normalized is None:
                    skipped += 1
                    continue
                comp_bin, _err = compile_component(normalized, tmp_path, comp_idx)
                comp_idx += 1
                if comp_bin is None:
                    passed += 1
                else:
                    ok, msg = validate_component(comp_bin, wasmoon, wit_names=wit_names)
                    if is_unsupported_error(msg):
                        skipped += 1
                    else:
                        failed += 1
                        if expected_msg:
                            failures.append(
                                f"assert_malformed unexpectedly parsed: {expected_msg}"
                            )
                        else:
                            failures.append("assert_malformed unexpectedly parsed")
            elif cmd == "assert_unlinkable":
                node = parse_form(form)
                expected_msg = extract_expected_message(node)
                component_form = find_component_form(form)
                if not component_form:
                    skipped += 1
                    continue
                normalized, kind = normalize_component_form(component_form)
                if component_form and has_unsupported_string_encoding(component_form):
                    skipped += 1
                    continue
                if kind == "instance" or normalized is None:
                    skipped += 1
                    continue
                comp_bin, err = compile_component(normalized, tmp_path, comp_idx)
                comp_idx += 1
                if comp_bin is None:
                    failed += 1
                    failures.append(f"assert_unlinkable parse failed: {err}")
                    continue
                ok, msg = validate_component(comp_bin, wasmoon, wit_names=wit_names)
                if not ok:
                    if is_unsupported_error(msg):
                        skipped += 1
                        continue
                    failed += 1
                    failures.append(f"assert_unlinkable validate failed: {msg}")
                    continue
                node = parse_form(form)
                text_msg = None
                if (
                    isinstance(node, list)
                    and len(node) > 2
                    and isinstance(node[2], StringToken)
                ):
                    text_msg = node[2].value
                commands.append(
                    {
                        "type": "assert_unlinkable",
                        "path": str(comp_bin),
                        "text": text_msg,
                    }
                )
            elif cmd == "assert_return":
                node = parse_form(form)
                if not isinstance(node, list) or len(node) < 2:
                    skipped += 1
                    continue
                action = parse_invoke(node[1])
                if action is None:
                    skipped += 1
                    continue
                expected: list[dict] = []
                ok = True
                for exp in node[2:]:
                    val = parse_const(exp)
                    if val is None:
                        ok = False
                        break
                    expected.append(val)
                if not ok:
                    skipped += 1
                    continue
                commands.append(
                    {
                        "type": "assert_return",
                        "instance": action["instance"],
                        "field": action["field"],
                        "args": action["args"],
                        "expected": expected,
                    }
                )
            elif cmd == "assert_trap":
                node = parse_form(form)
                if not isinstance(node, list) or len(node) < 2:
                    skipped += 1
                    continue
                action = parse_invoke(node[1])
                if action is None:
                    skipped += 1
                    continue
                msg = None
                if len(node) > 2 and isinstance(node[2], StringToken):
                    msg = node[2].value
                commands.append(
                    {
                        "type": "assert_trap",
                        "instance": action["instance"],
                        "field": action["field"],
                        "args": action["args"],
                        "text": msg,
                    }
                )
            elif cmd == "invoke":
                node = parse_form(form)
                action = parse_invoke(node)
                if action is None:
                    skipped += 1
                    continue
                commands.append(
                    {
                        "type": "invoke",
                        "instance": action["instance"],
                        "field": action["field"],
                        "args": action["args"],
                    }
                )
            else:
                skipped += 1
        if commands:
            compact = [
                {k: v for k, v in cmd.items() if v is not None}
                for cmd in commands
            ]
            script = {"commands": compact}
            (
                spassed,
                sfailed,
                sskipped,
                sfailures,
                raw,
                saw_result,
            ) = run_component_script(script, wasmoon, tmp_path)
            passed += spassed
            failed += sfailed
            skipped += sskipped
            failures.extend(sfailures)
            if not saw_result:
                failed += 1
                failures.append(f"component-test failed: {raw or 'no output'}")
    return {
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run component-model .wast tests",
    )
    parser.add_argument(
        "--dir",
        type=str,
        default="component-spec",
        help="Directory containing .wast files (default: component-spec)",
    )
    parser.add_argument(
        "--rec",
        action="store_true",
        help="Recursively search subdirectories for .wast files",
    )
    parser.add_argument(
        "--dump-failures",
        action="store_true",
        help="Print per-file failure details",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    wasmoon = repo_root / "wasmoon"
    if not wasmoon.exists():
        print("Error: wasmoon binary not found. Run moon build && ./install.sh first.")
        return 1

    test_dir = repo_root / args.dir
    if not test_dir.exists():
        print(f"Error: Directory '{test_dir}' does not exist")
        return 1

    if args.rec:
        wast_files = sorted(test_dir.glob("**/*.wast"))
    else:
        wast_files = sorted(test_dir.glob("*.wast"))

    if not wast_files:
        print(f"No .wast files found in '{test_dir}'")
        return 1

    print(f"Found {len(wast_files)} .wast test files in '{test_dir}'")

    total_passed = total_failed = total_skipped = 0
    files_ok = files_failed = 0
    for wast_file in wast_files:
        result = run_file(wast_file, wasmoon)
        total_passed += result["passed"]
        total_failed += result["failed"]
        total_skipped += result["skipped"]
        name = str(wast_file.relative_to(test_dir))
        if result["failed"] == 0:
            status = f"[PASS] (pass={result['passed']} skip={result['skipped']})"
            files_ok += 1
        else:
            status = (
                f"[FAIL] (pass={result['passed']} fail={result['failed']} "
                f"skip={result['skipped']})"
            )
            files_failed += 1
        print(f"{name:50} {status}")
        if args.dump_failures and result["failed"]:
            for failure in result["failures"][:10]:
                print(f"  - {failure}")

    print("\nSummary:")
    print(f"  Files passed:  {files_ok}/{len(wast_files)}")
    print(f"  Files failed:  {files_failed}")
    print(f"  Commands passed:  {total_passed}")
    print(f"  Commands failed:  {total_failed}")
    print(f"  Commands skipped: {total_skipped}")

    return 0 if total_failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
