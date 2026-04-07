#!/usr/bin/env python3
"""Run component-model .wast tests with wasmoon validation harness."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple

BASE_VALIDATE_TIMEOUT_SECONDS = int(
    os.environ.get("WASMOON_COMPONENT_VALIDATE_TIMEOUT", "20")
)
BASE_SCRIPT_TIMEOUT_SECONDS = int(
    os.environ.get("WASMOON_COMPONENT_SCRIPT_TIMEOUT", "30")
)
BASE_TOOLS_TIMEOUT_SECONDS = int(
    os.environ.get("WASMOON_COMPONENT_TOOLS_TIMEOUT", "30")
)


def detect_qemu_tcg() -> bool:
    cpuinfo = Path("/proc/cpuinfo")
    if not cpuinfo.exists():
        return False
    try:
        text = cpuinfo.read_text(encoding="utf-8", errors="ignore").lower()
    except OSError:
        return False
    return "qemu tcg" in text or "qemu virtual cpu" in text


def running_in_ci() -> bool:
    return os.getenv("CI", "").strip().lower() in {"1", "true", "yes"}


QEMU_TIMEOUT_MULTIPLIER = float(
    os.environ.get("WASMOON_COMPONENT_QEMU_TIMEOUT_MULTIPLIER", "3.0")
)
RELAX_TIMEOUT_FOR_QEMU = (
    detect_qemu_tcg()
    and not running_in_ci()
    and QEMU_TIMEOUT_MULTIPLIER > 1.0
)


def scale_timeout(base: int) -> int:
    multiplier = QEMU_TIMEOUT_MULTIPLIER if RELAX_TIMEOUT_FOR_QEMU else 1.0
    return int(max(1, round(base * multiplier)))


DEFAULT_VALIDATE_TIMEOUT_SECONDS = scale_timeout(BASE_VALIDATE_TIMEOUT_SECONDS)
DEFAULT_SCRIPT_TIMEOUT_SECONDS = scale_timeout(BASE_SCRIPT_TIMEOUT_SECONDS)
DEFAULT_TOOLS_TIMEOUT_SECONDS = scale_timeout(BASE_TOOLS_TIMEOUT_SECONDS)


def run_command(
    cmd: list[str],
    *,
    timeout_sec: Optional[int] = None,
    cwd: Optional[Path] = None,
) -> tuple[int, str, str, bool]:
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd) if cwd is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
    except OSError as err:
        return 127, "", str(err), False

    try:
        stdout, stderr = proc.communicate(timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            try:
                proc.kill()
            except OSError:
                pass
        try:
            proc.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            # Keep moving even if the process is briefly stuck in uninterruptible
            # sleep under emulation.
            pass
        return 124, "", "", True

    return proc.returncode, (stdout or ""), (stderr or ""), False


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
            # WAT supports byte escapes like `\00` (two hex digits).
            if (
                esc in "0123456789abcdefABCDEF"
                and i + 1 < len(text)
                and text[i + 1] in "0123456789abcdefABCDEF"
            ):
                try:
                    out.append(chr(int(text[i : i + 2], 16)))
                    i += 2
                    continue
                except ValueError:
                    # Fall back to treating as a literal escape.
                    pass
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

UNSUPPORTED_ERROR_CODE = "COMP_UNSUPPORTED"


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
    if head == "list.const":
        items: list[dict] = []
        for item in node[1:]:
            val = parse_const(item)
            if val is None:
                return None
            items.append(val)
        return {"type": "list", "items": items}
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


def decode_wat_bytes(s: str) -> bytes:
    """Decode a WAT string literal payload into raw bytes.

    This is used for `(module binary "...")` forms in the component-spec
    directory (e.g. wasm-tools/wrong-order.wast).
    """
    out = bytearray()
    for ch in s:
        code = ord(ch)
        if code > 0xFF:
            raise ValueError("non-byte character in binary string")
        out.append(code)
    return bytes(out)


def parse_module_binary(node) -> Optional[bytes]:
    if not isinstance(node, list) or len(node) < 3 or node[0] != "module" or node[1] != "binary":
        return None
    parts: list[bytes] = []
    for item in node[2:]:
        if not isinstance(item, StringToken):
            return None
        try:
            parts.append(decode_wat_bytes(item.value))
        except ValueError:
            return None
    return b"".join(parts)


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
    # The `wasmoon component-test` harness provides the host bindings needed by
    # component-spec (e.g. `host`, `host-return-two`), so we should instantiate
    # every root component to actually exercise runtime behavior.
    return True


def compile_component(
    text: str,
    tmp: Path,
    idx: int,
    wasmoon_tools: Path,
) -> Tuple[Optional[Path], Optional[str]]:
    src = tmp / f"component_{idx}.wat"
    out = tmp / f"component_{idx}.wasm"
    src.write_text(text, encoding="utf-8")

    returncode, stdout, stderr, timed_out = run_command(
        [str(wasmoon_tools), "wat2wasm", str(src), "-o", str(out)],
        timeout_sec=DEFAULT_TOOLS_TIMEOUT_SECONDS,
    )
    if timed_out:
        return (
            None,
            f"wasmoon-tools wat2wasm timeout ({DEFAULT_TOOLS_TIMEOUT_SECONDS}s)",
        )
    if returncode != 0:
        err = (stderr or stdout).strip()
        return (
            None,
            "wasmoon-tools wat2wasm failed: " + (err or "unknown error"),
        )

    return out, None


def probe_component_wat_support(wasmoon_tools: Path) -> bool:
    with tempfile.TemporaryDirectory(prefix="wasmoon_component_probe_") as tmp:
        tmp_path = Path(tmp)
        src = tmp_path / "probe_component.wat"
        out = tmp_path / "probe_component.wasm"
        src.write_text("(component)", encoding="utf-8")
        returncode, _stdout, _stderr, timed_out = run_command(
            [str(wasmoon_tools), "wat2wasm", str(src), "-o", str(out)],
            timeout_sec=DEFAULT_TOOLS_TIMEOUT_SECONDS,
        )
        if timed_out:
            return False
        return returncode == 0 and out.exists()


def parse_component_json_result(out: str) -> Optional[dict]:
    for raw_line in out.splitlines():
        line = raw_line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict) and "ok" in payload:
            return payload
    return None


def validate_component(
    component_bin: Path, wasmoon: Path, *, wit_names: bool
) -> Tuple[bool, str, Optional[str]]:
    cmd = [str(wasmoon), "component", "--error-format", "json"]
    if not wit_names:
        cmd.append("--no-wit-names")
    cmd.extend(["--validate", str(component_bin)])
    returncode, stdout, stderr, timed_out = run_command(
        cmd,
        timeout_sec=DEFAULT_VALIDATE_TIMEOUT_SECONDS,
    )
    if timed_out:
        return False, "component validation timeout", "COMP_TIMEOUT"
    out = stdout + stderr
    payload = parse_component_json_result(out)
    if payload is not None:
        ok = bool(payload.get("ok", False))
        detail = str(payload.get("detail", "")).strip()
        code = payload.get("code")
        code_str = str(code) if isinstance(code, str) else None
        if ok:
            return True, detail or "component validated ok", None
        return False, detail or out.strip() or "unknown validation result", code_str
    if "validate component error" in out or "parse component error" in out:
        return False, out.strip(), None
    if "component validated ok" in out:
        return True, out.strip(), None
    return False, out.strip() or "unknown validation result", None


def wit_names_for_path(wast_file: Path) -> bool:
    # wasm-tools' suite validates the WIT component encoding, which imposes
    # kebab-case/package-name name rules. wasmtime's suite uses arbitrary names.
    return "wasmtime" not in wast_file.parts


def run_component_script(
    script: dict, wasmoon: Path, tmp: Path
) -> Tuple[int, int, int, list[str], str, bool]:
    script_path = tmp / "component_script.json"
    script_path.write_text(
        json.dumps(script, ensure_ascii=True, indent=2),
        encoding="utf-8",
    )
    returncode, stdout, stderr, timed_out = run_command(
        [str(wasmoon), "component-test", str(script_path)],
        timeout_sec=DEFAULT_SCRIPT_TIMEOUT_SECONDS,
    )
    if timed_out:
        return 0, 1, 0, ["component-test timeout"], "component-test timeout", False
    out = stdout + stderr
    if not out.strip():
        out = f"(exit={returncode})"
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


def run_file(
    path: Path,
    wasmoon: Path,
    wasmoon_tools: Path,
    *,
    keep_tmp_on_failure: bool = False,
) -> dict:
    text = path.read_text(encoding="utf-8")
    passed = failed = 0
    failures: list[str] = []
    defined_components: set[str] = set()
    anon_def_count = 0
    wit_names = wit_names_for_path(path)
    current_form_idx = 0
    current_cmd = ""

    def fail(reason: str) -> None:
        nonlocal failed
        failed += 1
        # Keep the list short to avoid dumping huge failure logs.
        if len(failures) < 50:
            failures.append(f"#{current_form_idx} {current_cmd}: {reason}")

    commands: list[dict] = []
    tmp_path = Path(tempfile.mkdtemp(prefix="wasmoon_component_wast_"))
    try:
        comp_idx = 0
        for form in iter_forms(text):
            current_form_idx += 1
            cmd = first_symbol(form)
            current_cmd = cmd or ""
            if cmd == "component":
                node = parse_form(form)
                normalized, kind = normalize_component_form(form)
                if kind == "instance":
                    inst = parse_component_instance(node)
                    if inst is None:
                        fail("unsupported component instance form")
                        continue
                    inst_name, comp_name = inst
                    if comp_name not in defined_components:
                        fail(f"component instance references unknown component {comp_name}")
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
                    fail(f"unsupported component form kind={kind}")
                    continue
                comp_bin, err = compile_component(
                    normalized,
                    tmp_path,
                    comp_idx,
                    wasmoon_tools,
                )
                comp_idx += 1
                if comp_bin is None:
                    fail(f"component parse failed: {err}")
                    continue
                ok, msg, _code = validate_component(
                    comp_bin,
                    wasmoon,
                    wit_names=wit_names,
                )
                if not ok:
                    fail(f"component validate failed: {msg}")
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
                    fail("assert_invalid missing component form")
                    continue
                normalized, kind = normalize_component_form(component_form)
                if kind == "instance" or normalized is None:
                    fail("assert_invalid uses unsupported component instance form")
                    continue
                comp_bin, err = compile_component(
                    normalized,
                    tmp_path,
                    comp_idx,
                    wasmoon_tools,
                )
                comp_idx += 1
                if comp_bin is None:
                    err_msg = err or "unknown component parse error"
                    if "unsupported" in err_msg.lower():
                        fail(f"assert_invalid failed due to unsupported feature: {err_msg}")
                        continue
                    if expected_msg:
                        if expected_msg.lower() in err_msg.lower():
                            passed += 1
                        else:
                            fail(f"assert_invalid parse failed: {expected_msg}: {err_msg}")
                    else:
                        # assert_invalid allows either parse-time or validate-time
                        # rejection; parse failure is acceptable.
                        passed += 1
                    continue
                ok, msg, code = validate_component(
                    comp_bin,
                    wasmoon,
                    wit_names=wit_names,
                )
                if ok:
                    if expected_msg:
                        fail(f"assert_invalid unexpectedly validated: {expected_msg}")
                    else:
                        fail("assert_invalid unexpectedly validated")
                    continue
                if code == UNSUPPORTED_ERROR_CODE:
                    fail(f"assert_invalid failed due to unsupported feature: {msg}")
                    continue
                passed += 1
            elif cmd == "assert_malformed":
                node = parse_form(form)
                expected_msg = extract_expected_message(node)
                component_form = find_component_form(form)
                if not component_form:
                    # Some upstream suites include core `(module binary ...)`
                    # malformed tests next to the component scripts.
                    if (
                        isinstance(node, list)
                        and len(node) > 1
                        and (data := parse_module_binary(node[1])) is not None
                    ):
                        wasm_path = tmp_path / f"module_{comp_idx}.wasm"
                        comp_idx += 1
                        wasm_path.write_bytes(data)
                        returncode, _stdout, _stderr, timed_out = run_command(
                            [str(wasmoon), "run", str(wasm_path)],
                            timeout_sec=DEFAULT_SCRIPT_TIMEOUT_SECONDS,
                        )
                        if timed_out:
                            fail("assert_malformed timed out")
                            continue
                        if returncode != 0:
                            passed += 1
                        else:
                            if expected_msg:
                                fail(f"assert_malformed unexpectedly ran: {expected_msg}")
                            else:
                                fail("assert_malformed unexpectedly ran")
                        continue
                    fail("assert_malformed missing component form")
                    continue
                normalized, kind = normalize_component_form(component_form)
                if kind == "instance" or normalized is None:
                    fail("assert_malformed uses unsupported component instance form")
                    continue
                comp_bin, _err = compile_component(
                    normalized,
                    tmp_path,
                    comp_idx,
                    wasmoon_tools,
                )
                comp_idx += 1
                if comp_bin is None:
                    err_msg = _err or "unknown component parse error"
                    if "unsupported" in err_msg.lower():
                        fail(f"assert_malformed failed due to unsupported feature: {err_msg}")
                    else:
                        passed += 1
                else:
                    ok, msg, code = validate_component(
                        comp_bin,
                        wasmoon,
                        wit_names=wit_names,
                    )
                    if code == UNSUPPORTED_ERROR_CODE:
                        fail(f"assert_malformed failed due to unsupported feature: {msg}")
                    else:
                        if expected_msg:
                            fail(f"assert_malformed unexpectedly parsed: {expected_msg}")
                        else:
                            fail("assert_malformed unexpectedly parsed")
            elif cmd == "assert_unlinkable":
                node = parse_form(form)
                expected_msg = extract_expected_message(node)
                component_form = find_component_form(form)
                if not component_form:
                    fail("assert_unlinkable missing component form")
                    continue
                normalized, kind = normalize_component_form(component_form)
                if kind == "instance" or normalized is None:
                    fail("assert_unlinkable uses unsupported component instance form")
                    continue
                comp_bin, err = compile_component(
                    normalized,
                    tmp_path,
                    comp_idx,
                    wasmoon_tools,
                )
                comp_idx += 1
                if comp_bin is None:
                    fail(f"assert_unlinkable parse failed: {err}")
                    continue
                ok, msg, _code = validate_component(
                    comp_bin,
                    wasmoon,
                    wit_names=wit_names,
                )
                if not ok:
                    fail(f"assert_unlinkable validate failed: {msg}")
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
                    fail("assert_return malformed")
                    continue
                action = parse_invoke(node[1])
                if action is None:
                    fail("assert_return unsupported invoke form")
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
                    fail("assert_return unsupported expected value")
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
                    fail("assert_trap malformed")
                    continue
                action = parse_invoke(node[1])
                msg = None
                if len(node) > 2 and isinstance(node[2], StringToken):
                    msg = node[2].value
                if action is not None:
                    commands.append(
                        {
                            "type": "assert_trap",
                            "instance": action["instance"],
                            "field": action["field"],
                            "args": action["args"],
                            "text": msg,
                        }
                    )
                    continue

                # Component-model scripts also use `assert_trap` around a full
                # `(component ...)` action, which means instantiation should
                # fail/trap (e.g. start function traps, canonical ABI traps).
                component_form = find_component_form(form)
                if not component_form:
                    fail("assert_trap unsupported invoke form")
                    continue
                normalized, kind = normalize_component_form(component_form)
                if kind == "instance" or normalized is None:
                    fail("assert_trap uses unsupported component instance form")
                    continue
                comp_bin, err = compile_component(
                    normalized,
                    tmp_path,
                    comp_idx,
                    wasmoon_tools,
                )
                comp_idx += 1
                if comp_bin is None:
                    fail(f"assert_trap component parse failed: {err}")
                    continue
                ok, vmsg, _code = validate_component(
                    comp_bin,
                    wasmoon,
                    wit_names=wit_names,
                )
                if not ok:
                    fail(f"assert_trap component validate failed: {vmsg}")
                    continue
                commands.append(
                    {
                        "type": "assert_unlinkable",
                        "path": str(comp_bin),
                        "text": msg,
                    }
                )
            elif cmd == "invoke":
                node = parse_form(form)
                action = parse_invoke(node)
                if action is None:
                    fail("invoke unsupported form")
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
                fail(f"unhandled command: {cmd or 'unknown'}")
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
            if sskipped:
                failed += sskipped
                fail(f"component-test skipped {sskipped} command(s)")
            failures.extend(sfailures)
            if not saw_result:
                fail(f"component-test failed: {raw or 'no output'}")
    finally:
        if keep_tmp_on_failure and failed > 0:
            failures.append(f"(debug) kept tmp dir: {tmp_path}")
        else:
            shutil.rmtree(tmp_path, ignore_errors=True)
    return {"passed": passed, "failed": failed, "skipped": 0, "failures": failures}


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
    parser.add_argument(
        "--keep-tmp-on-failure",
        action="store_true",
        help="Keep per-file temporary directories when a file fails (debug)",
    )
    parser.add_argument(
        "--wasmoon-tools",
        type=str,
        default="./wasmoon-tools",
        help="Path to wasmoon-tools binary (default: ./wasmoon-tools)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    wasmoon = repo_root / "wasmoon"
    if not wasmoon.exists():
        print(
            "Error: wasmoon binary not found. "
            "Run moon build --target native --release && ./install.sh first."
        )
        return 1

    wasmoon_tools = Path(args.wasmoon_tools)
    if not wasmoon_tools.is_absolute():
        wasmoon_tools = (repo_root / wasmoon_tools).resolve()
    if not wasmoon_tools.exists():
        print(
            "Error: wasmoon-tools binary not found at "
            f"'{wasmoon_tools}'. Run moon build --target native --release && ./install.sh first."
        )
        return 1

    supports_component_wat = probe_component_wat_support(wasmoon_tools)

    if not supports_component_wat:
        print(
            "Error: wasmoon-tools wat2wasm does not support component text yet; "
            "component-spec runner requires native component text support."
        )
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
    print(
        "Timeout settings: "
        f"validate={DEFAULT_VALIDATE_TIMEOUT_SECONDS}s(base {BASE_VALIDATE_TIMEOUT_SECONDS}s), "
        f"script={DEFAULT_SCRIPT_TIMEOUT_SECONDS}s(base {BASE_SCRIPT_TIMEOUT_SECONDS}s), "
        f"tools={DEFAULT_TOOLS_TIMEOUT_SECONDS}s(base {BASE_TOOLS_TIMEOUT_SECONDS}s), "
        f"qemu_relax={RELAX_TIMEOUT_FOR_QEMU}"
    )

    total_passed = total_failed = total_skipped = 0
    files_ok = files_failed = 0
    for wast_file in wast_files:
        result = run_file(
            wast_file,
            wasmoon,
            wasmoon_tools,
            keep_tmp_on_failure=args.keep_tmp_on_failure,
        )
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
            for failure in result["failures"]:
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
