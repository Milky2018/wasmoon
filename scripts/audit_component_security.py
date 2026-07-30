#!/usr/bin/env python3
"""Audit Component Model security boundaries and hardening evidence."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path

from component_hardening_lib import WASMTIME_VERSION


@dataclass(frozen=True)
class AuditCheck:
    name: str
    passed: bool
    detail: str


def read_text(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


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
    forbidden_interface_owners = [
        owner
        for owner, markers in [
            ("runtime_impl", ["runtime_impl"]),
            (
                "component_engine",
                ["@component_engine", "/component_engine\""],
            ),
            ("component_host", ["@component_host", "/component_host\""]),
            (
                "component_native",
                ["@component_native", "/component_native\""],
            ),
        ]
        if any(marker in interface for marker in markers)
    ]
    checks.append(
        AuditCheck(
            "stable-interface-isolation",
            not forbidden_interface_owners,
            "stable component interface must not expose implementation owners; "
            f"found {forbidden_interface_owners}",
        )
    )
    adapter_leaks: list[str] = []
    for relative in [
        "modules/wasmoon/component_engine",
        "modules/wasmoon/component_host",
    ]:
        path = root / relative
        if path.exists() and any(
            child.is_file()
            and (child.suffix in {".mbt", ".mbti"} or child.name == "moon.pkg")
            for child in path.iterdir()
        ):
            adapter_leaks.append(relative)
    checks.append(
        AuditCheck(
            "adapter-interface-isolation",
            not adapter_leaks,
            "obsolete generic component adapter packages must remain absent; "
            f"found {adapter_leaks}",
        )
    )
    validation = facade.find("@component_model.validate_component_with_config")
    instantiate = facade.find(".linker.instantiate(", validation + 1)
    checks.append(
        AuditCheck(
            "validate-before-instantiate",
            validation >= 0 and instantiate > validation,
            "facade must validate before linker instantiation",
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
