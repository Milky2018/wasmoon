#!/usr/bin/env python3
"""Run component-model .wast tests with wasmoon validation harness."""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
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


def compile_component(text: str, tmp: Path) -> Tuple[Optional[Path], Optional[str]]:
    src = tmp / "component.wat"
    out = tmp / "component.wasm"
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


def validate_component(component_bin: Path, wasmoon: Path) -> Tuple[bool, str]:
    result = subprocess.run(
        [str(wasmoon), "component", "--validate", str(component_bin)],
        capture_output=True,
        text=True,
    )
    out = (result.stdout or "") + (result.stderr or "")
    if "validate component error" in out or "parse component error" in out:
        return False, out.strip()
    if "component validated ok" in out:
        return True, out.strip()
    return False, out.strip() or "unknown validation result"


def run_file(path: Path, wasmoon: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    passed = failed = skipped = 0
    failures: list[str] = []
    for form in iter_forms(text):
        cmd = first_symbol(form)
        if cmd == "component":
            normalized, kind = normalize_component_form(form)
            if kind == "instance" or normalized is None:
                skipped += 1
                continue
            with tempfile.TemporaryDirectory() as tmpdir:
                comp_bin, err = compile_component(normalized, Path(tmpdir))
                if comp_bin is None:
                    failed += 1
                    failures.append(f"component parse failed: {err}")
                    continue
                ok, msg = validate_component(comp_bin, wasmoon)
                if ok:
                    passed += 1
                else:
                    failed += 1
                    failures.append(f"component validate failed: {msg}")
        elif cmd == "assert_invalid":
            component_form = find_component_form(form)
            if not component_form:
                skipped += 1
                continue
            normalized, kind = normalize_component_form(component_form)
            if kind == "instance" or normalized is None:
                skipped += 1
                continue
            with tempfile.TemporaryDirectory() as tmpdir:
                comp_bin, err = compile_component(normalized, Path(tmpdir))
                if comp_bin is None:
                    failed += 1
                    failures.append(f"assert_invalid parse failed: {err}")
                    continue
                ok, _msg = validate_component(comp_bin, wasmoon)
                if ok:
                    failed += 1
                    failures.append("assert_invalid unexpectedly validated")
                else:
                    passed += 1
        elif cmd == "assert_malformed":
            component_form = find_component_form(form)
            if not component_form:
                skipped += 1
                continue
            normalized, kind = normalize_component_form(component_form)
            if kind == "instance" or normalized is None:
                skipped += 1
                continue
            with tempfile.TemporaryDirectory() as tmpdir:
                comp_bin, _err = compile_component(normalized, Path(tmpdir))
                if comp_bin is None:
                    passed += 1
                else:
                    failed += 1
                    failures.append("assert_malformed unexpectedly parsed")
        else:
            skipped += 1
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
