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


def has_validated_instantiation_boundary(
    validator_interface: str,
    runtime_interface: str,
) -> bool:
    """Check the compiler-generated type-state boundary, not source ordering."""
    validator = re.sub(r"\s+", " ", validator_interface)
    runtime = re.sub(r"\s+", " ", runtime_interface)
    has_abstract_evidence = re.search(
        r"\btype ValidatedComponent\b",
        validator,
    )
    has_evidence_producer = re.search(
        r"pub fn validate_component_for_instantiation_with_config"
        r"\(@model\.Component, ComponentValidationConfig\)"
        r" -> ValidatedComponent raise ComponentValidationError",
        validator,
    )
    linker_requires_evidence = re.search(
        r"pub fn ComponentLinker::instantiate"
        r"\(Self, String, @component_model\.ValidatedComponent\)"
        r" -> ComponentInstance raise ComponentRuntimeError",
        runtime,
    )
    # A component import is instantiated by whichever component imports it,
    # so the registration boundary needs the same evidence as instantiation.
    component_import_requires_evidence = re.search(
        r"pub fn ComponentLinker::add_component"
        r"\(Self, String, @component_model\.ValidatedComponent\) -> Unit",
        runtime,
    )
    # A constructible closure would let external code forge a
    # `Component(closure)` extern around an unchecked component.
    closure_not_constructible = re.search(
        r"\btype ComponentClosure\b", runtime
    ) and not re.search(r"pub(\(all\))? struct ComponentClosure\b", runtime)
    return bool(
        has_abstract_evidence
        and has_evidence_producer
        and linker_requires_evidence
        and component_import_requires_evidence
        and closure_not_constructible
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
        validator = read_text(root, str(source["validator"]))
        validator_interface = read_text(
            root,
            str(source["validator_interface"]),
        )
        runtime_interface = read_text(
            root,
            str(source["runtime_interface"]),
        )
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
            has_validated_instantiation_boundary(
                validator_interface,
                runtime_interface,
            ),
            "ComponentLinker::instantiate and ComponentLinker::add_component "
            "must require abstract evidence returned by successful component "
            "validation, and ComponentClosure must not be constructible",
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
