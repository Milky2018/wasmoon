#!/usr/bin/env python3
"""Audit Component Model security boundaries and hardening evidence."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path

from component_hardening_lib import WASMTIME_VERSION


@dataclass(frozen=True)
class AuditCheck:
    name: str
    passed: bool
    detail: str


@dataclass(frozen=True)
class InterfaceOwnerAnalysis:
    owners: tuple[str, ...]
    unresolved_aliases: tuple[str, ...]


MBTI_IMPORT_ENTRY = re.compile(
    r'^\s*"(?P<owner>[^"]+)"'
    r"(?:\s+@(?P<alias>[A-Za-z_][A-Za-z0-9_]*))?,?\s*$"
)
MBTI_ALIAS_REFERENCE = re.compile(r"@([A-Za-z_][A-Za-z0-9_]*)")


def read_text(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def analyze_interface_owners(interface: str) -> InterfaceOwnerAnalysis:
    """Resolve package owners referenced by a generated public interface."""
    aliases: dict[str, str] = {}
    public_declarations: list[str] = []
    in_imports = False
    for line in interface.splitlines():
        stripped = line.strip()
        if stripped == "import {":
            in_imports = True
            continue
        if in_imports:
            if stripped == "}":
                in_imports = False
                continue
            entry = MBTI_IMPORT_ENTRY.match(line)
            if entry is not None:
                owner = entry.group("owner")
                alias = entry.group("alias") or owner.rsplit("/", 1)[-1]
                aliases[alias] = owner
            continue
        if not stripped.startswith("//"):
            public_declarations.append(line)
    referenced_aliases = set(
        MBTI_ALIAS_REFERENCE.findall("\n".join(public_declarations))
    )
    return InterfaceOwnerAnalysis(
        owners=tuple(
            sorted(
                {
                    aliases[alias]
                    for alias in referenced_aliases
                    if alias in aliases
                }
            )
        ),
        unresolved_aliases=tuple(
            sorted(alias for alias in referenced_aliases if alias not in aliases)
        ),
    )


def owner_matches_root(owner: str, root: str) -> bool:
    return owner == root or owner.startswith(root + "/")


def effective_moonbit_code(source: str) -> str:
    """Replace comments and literal contents while preserving code positions."""
    output = list(source)
    index = 0
    block_depth = 0
    quote: str | None = None
    while index < len(source):
        if block_depth > 0:
            if source.startswith("/*", index):
                output[index] = " "
                output[index + 1] = " "
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                output[index] = " "
                output[index + 1] = " "
                block_depth -= 1
                index += 2
            else:
                if source[index] != "\n":
                    output[index] = " "
                index += 1
            continue
        if quote is not None:
            if source[index] == "\\" and index + 1 < len(source):
                output[index] = " "
                if source[index + 1] != "\n":
                    output[index + 1] = " "
                index += 2
            else:
                char = source[index]
                if char != "\n":
                    output[index] = " "
                index += 1
                if char == quote:
                    quote = None
            continue
        if source.startswith("//", index) or source.startswith("#|", index):
            while index < len(source) and source[index] != "\n":
                output[index] = " "
                index += 1
            continue
        if source.startswith("/*", index):
            output[index] = " "
            output[index + 1] = " "
            block_depth = 1
            index += 2
            continue
        if source[index] in {'"', "'"}:
            quote = source[index]
            output[index] = " "
        index += 1
    return "".join(output)


def moonbit_function_body(source: str, qualified_name: str) -> str | None:
    code = effective_moonbit_code(source)
    declaration = re.search(
        rf"\bpub\s+fn\s+{re.escape(qualified_name)}\s*\(",
        code,
    )
    if declaration is None:
        return None
    opening = code.find("{", declaration.end())
    if opening < 0:
        return None
    depth = 1
    for index in range(opening + 1, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return code[opening + 1 : index]
    return None


def delimiter_depths(code: str) -> list[int] | None:
    """Return nesting depth before each character, or None if unbalanced."""
    depths: list[int] = []
    stack: list[str] = []
    closing_delimiters = {")": "(", "}": "{", "]": "["}
    for char in code:
        depths.append(len(stack))
        if char in "({[":
            stack.append(char)
        elif char in closing_delimiters:
            if not stack or stack.pop() != closing_delimiters[char]:
                return None
    return depths if not stack else None


def matching_delimiter(
    code: str,
    opening: int,
    open_char: str,
    close_char: str,
) -> int | None:
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == open_char:
            depth += 1
        elif code[index] == close_char:
            depth -= 1
            if depth == 0:
                return index
            if depth < 0:
                return None
    return None


def top_level_arrows(code: str) -> list[int] | None:
    depths = delimiter_depths(code)
    if depths is None:
        return None
    return [
        match.start()
        for match in re.finditer(r"=>", code)
        if depths[match.start()] == 0
    ]


def validation_executes_or_propagates(
    body: str,
    validation: re.Match[str],
) -> bool:
    line_start = body.rfind("\n", 0, validation.start()) + 1
    if body[line_start : validation.start()].strip():
        return False
    if re.search(r"\b(?:defer|try[!?]?)\s*$", body[: validation.start()]):
        return False

    opening = validation.end() - 1
    closing = matching_delimiter(body, opening, "(", ")")
    if closing is None:
        return False
    suffix = body[closing + 1 :].lstrip()
    catch = re.match(r"catch\s*\{", suffix)
    if catch is None:
        return re.match(r"catch\b", suffix) is None

    catch_opening = catch.end() - 1
    catch_closing = matching_delimiter(suffix, catch_opening, "{", "}")
    if catch_closing is None:
        return False
    catch_body = suffix[catch_opening + 1 : catch_closing]
    arrows = top_level_arrows(catch_body)
    if not arrows:
        return False
    return all(
        re.match(r"\s*raise\b", catch_body[arrow + 2 :]) is not None
        for arrow in arrows
    )


def validates_before_every_instantiation(facade: str) -> bool:
    body = moonbit_function_body(
        facade,
        "ComponentRuntime::instantiate_component",
    )
    if body is None:
        return False
    depths = delimiter_depths(body)
    if depths is None:
        return False
    validations = [
        match.start()
        for match in re.finditer(
            r"@component_model\s*\.\s*"
            r"validate_component_with_config\s*\(",
            body,
        )
        if depths[match.start()] == 0
        and validation_executes_or_propagates(body, match)
    ]
    instantiations = [
        match.start()
        for match in re.finditer(
            r"\bself\s*\.\s*state\s*\.\s*linker\s*\.\s*"
            r"instantiate\s*\(",
            body,
        )
    ]
    return bool(
        validations
        and instantiations
        and all(
            any(validation < instantiation for validation in validations)
            for instantiation in instantiations
        )
    )


def check_manifest(root: Path) -> tuple[dict[str, object], list[AuditCheck]]:
    path = root / "docs/component-hardening.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {}, [AuditCheck("manifest", False, str(error))]
    checks = [
        AuditCheck(
            "manifest-schema",
            manifest.get("schema_version") == 1,
            "schema_version must be 1",
        )
    ]
    evidence = manifest.get("evidence")
    expected = {
        "fuzz",
        "wasmtime-differential",
        "logical-resource-lifecycle",
        "native-sanitizers",
        "large-component-stress",
    }
    names = (
        {str(item.get("name")) for item in evidence if isinstance(item, dict)}
        if isinstance(evidence, list)
        else set()
    )
    checks.append(
        AuditCheck(
            "manifest-evidence",
            names == expected,
            f"expected {sorted(expected)}, found {sorted(names)}",
        )
    )
    oracle = manifest.get("oracle")
    checks.append(
        AuditCheck(
            "manifest-oracle",
            isinstance(oracle, dict)
            and oracle.get("name") == "wasmtime"
            and oracle.get("version") == WASMTIME_VERSION,
            "manifest and harness must pin the same official Wasmtime release",
        )
    )
    return manifest, checks


def audit_repo(root: Path) -> list[AuditCheck]:
    manifest, checks = check_manifest(root)
    if not manifest:
        return checks
    source = manifest.get("source_checks")
    if not isinstance(source, dict):
        return checks + [
            AuditCheck("manifest-source-checks", False, "missing source_checks")
        ]
    try:
        interface = read_text(root, str(source["stable_interface"]))
        facade = read_text(root, str(source["facade"]))
        validator = read_text(root, str(source["validator"]))
    except (KeyError, OSError) as error:
        return checks + [AuditCheck("source-inputs", False, str(error))]
    interface_scan_root = source.get("interface_scan_root")
    implementation_owner_roots = source.get("implementation_owner_roots")
    implementation_interface_allowlist = source.get(
        "implementation_interface_allowlist"
    )
    valid_interface_config = (
        isinstance(interface_scan_root, str)
        and isinstance(implementation_owner_roots, list)
        and all(isinstance(owner, str) for owner in implementation_owner_roots)
        and isinstance(implementation_interface_allowlist, list)
        and all(
            isinstance(path, str) for path in implementation_interface_allowlist
        )
    )
    checks.append(
        AuditCheck(
            "interface-owner-config",
            valid_interface_config,
            "interface scan root, implementation owner roots, and interface "
            "allowlist must be configured",
        )
    )
    if not valid_interface_config:
        return checks
    owner_roots = [str(owner) for owner in implementation_owner_roots]
    interface_allowlist = {
        str(path) for path in implementation_interface_allowlist
    }
    stable_analysis = analyze_interface_owners(interface)
    forbidden_interface_owners = [
        owner
        for owner in stable_analysis.owners
        if any(owner_matches_root(owner, root) for root in owner_roots)
    ]
    checks.append(
        AuditCheck(
            "stable-interface-isolation",
            not forbidden_interface_owners
            and not stable_analysis.unresolved_aliases,
            "stable component interface must not expose implementation owners; "
            f"found {forbidden_interface_owners}; unresolved aliases "
            f"{list(stable_analysis.unresolved_aliases)}",
        )
    )
    adapter_leaks: list[str] = []
    scan_root = root / str(interface_scan_root)
    if scan_root.exists():
        for path in sorted(scan_root.rglob("pkg.generated.mbti")):
            relative = str(path.relative_to(root))
            if relative in interface_allowlist:
                continue
            analysis = analyze_interface_owners(
                path.read_text(encoding="utf-8")
            )
            exposed = [
                owner
                for owner in analysis.owners
                if any(owner_matches_root(owner, root) for root in owner_roots)
            ]
            if exposed or analysis.unresolved_aliases:
                detail = exposed + [
                    f"unresolved:@{alias}"
                    for alias in analysis.unresolved_aliases
                ]
                adapter_leaks.append(f"{relative}: {detail}")
    checks.append(
        AuditCheck(
            "adapter-interface-isolation",
            not adapter_leaks,
            "unreviewed interfaces must not expose implementation owners; "
            f"found {adapter_leaks}",
        )
    )
    checks.append(
        AuditCheck(
            "validate-before-instantiate",
            validates_before_every_instantiation(facade),
            "ComponentRuntime::instantiate_component must unconditionally "
            "validate before every linker instantiation",
        )
    )
    checks.append(
        AuditCheck(
            "validator-limits",
            "effective type size exceeds the limit" in validator
            and "type nesting is too deep" in validator,
            "component type size and nesting limits must remain explicit",
        )
    )
    roots = source.get("forbidden_termination_roots", [])
    patterns = source.get("forbidden_termination_patterns", [])
    allowlist = set(source.get("termination_allowlist", []))
    violations: list[str] = []
    if isinstance(roots, list) and isinstance(patterns, list):
        for relative in roots:
            path = root / str(relative)
            for file in sorted(path.rglob("*.mbt")):
                for line_number, line in enumerate(
                    file.read_text(encoding="utf-8").splitlines(), start=1
                ):
                    if any(str(pattern) in line for pattern in patterns):
                        location = f"{file.relative_to(root)}:{line_number}"
                        if location not in allowlist:
                            violations.append(location)
    else:
        violations.append("invalid forbidden termination configuration")
    checks.append(
        AuditCheck(
            "structured-termination",
            not violations,
            "violations: " + ", ".join(violations) if violations else "none",
        )
    )
    unsafe_allowlist = source.get("unsafe_conversion_allowlist", [])
    unsafe_limits: dict[str, int] = {}
    invalid_allowlist = False
    if isinstance(unsafe_allowlist, list):
        for entry in unsafe_allowlist:
            if (
                not isinstance(entry, dict)
                or not isinstance(entry.get("path"), str)
                or not isinstance(entry.get("max_occurrences"), int)
                or not isinstance(entry.get("rationale"), str)
                or not entry["rationale"]
            ):
                invalid_allowlist = True
                continue
            unsafe_limits[entry["path"]] = entry["max_occurrences"]
    else:
        invalid_allowlist = True
    unsafe_counts: dict[str, int] = {}
    for relative in roots if isinstance(roots, list) else []:
        path = root / str(relative)
        for file in sorted(path.rglob("*.mbt")):
            count = file.read_text(encoding="utf-8").count(".unsafe_to_")
            if count:
                unsafe_counts[str(file.relative_to(root))] = count
    unsafe_violations = [
        f"{path} ({count}>{unsafe_limits.get(path, 0)})"
        for path, count in sorted(unsafe_counts.items())
        if count > unsafe_limits.get(path, 0)
    ]
    checks.append(
        AuditCheck(
            "unsafe-conversion-budget",
            not invalid_allowlist and not unsafe_violations,
            "violations: " + ", ".join(unsafe_violations)
            if unsafe_violations
            else "within reviewed per-file budgets",
        )
    )
    cleanup_source = "\n".join(
        read_text(root, path)
        for path in [
            "modules/wasmoon/component/runtime_impl/async_types.mbt",
            "modules/wasmoon/component/runtime_impl/canon_stream.mbt",
            "modules/wasmoon/component/runtime_impl/canon_future.mbt",
            "modules/wasmoon/component/runtime_impl/host_stream.mbt",
        ]
    )
    checks.append(
        AuditCheck(
            "resource-cleanup-boundary",
            "cleanup_closed_stream" in cleanup_source
            and "cleanup_closed_future" in cleanup_source,
            "stream and future backing state must have explicit cleanup",
        )
    )
    scripts = [
        "scripts/component_fuzz.py",
        "scripts/component_differential.py",
        "scripts/component_stress.py",
        "scripts/install_wasmtime_oracle.py",
    ]
    missing_scripts = [path for path in scripts if not (root / path).is_file()]
    checks.append(
        AuditCheck(
            "hardening-tools",
            not missing_scripts,
            "missing: " + ", ".join(missing_scripts) if missing_scripts else "present",
        )
    )
    try:
        ci_text = read_text(root, ".github/workflows/check.yml")
    except OSError:
        ci_text = ""
    required_ci_tokens = [
        "runtime_cleanup_wbtest.mbt",
        "run native sanitizer checks",
        "stable-0.2",
        "async-0.3",
        "future-gated",
    ]
    missing_ci = [token for token in required_ci_tokens if token not in ci_text]
    checks.append(
        AuditCheck(
            "platform-ci",
            not missing_ci,
            "missing CI references: " + ", ".join(missing_ci)
            if missing_ci
            else "configured",
        )
    )
    return checks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("target/component-hardening/security-audit.json"),
    )
    args = parser.parse_args()
    checks = audit_repo(args.root.resolve())
    report = {
        "schema_version": 1,
        "passed": all(check.passed for check in checks),
        "checks": [asdict(check) for check in checks],
    }
    output = args.out
    if not output.is_absolute():
        output = args.root / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    for check in checks:
        print(f"{'PASS' if check.passed else 'FAIL'} {check.name}: {check.detail}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
