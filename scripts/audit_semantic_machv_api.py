#!/usr/bin/env python3
"""Audit the generated semantic MachV API for target or escape-hatch leakage."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
INTERFACE = ROOT / "modules/machv/pkg.generated.mbti"

FORBIDDEN_PUBLIC_IDENTIFIERS = [
    "AArch64",
    "AMD64",
    "X64",
    "RiscV",
    "PhysicalRegister",
    "PReg",
    "RegClass",
    "CallingConvention",
    "CallLayout",
    "FrameLayout",
    "StackSlot",
    "SpillSlot",
    "Encoding",
    "Custom",
    "Ext",
    "Legacy",
]

EXPECTED_VALUE_TYPES = {
    "I32",
    "I64",
    "F32",
    "F64",
    "V128",
    "Ptr64",
    "GcRef64",
}

EXPECTED_OPERATION_FAMILIES = {
    "I32Const",
    "I64Const",
    "F32Const",
    "F64Const",
    "V128Const",
    "NullPtr",
    "NullGcRef",
    "CodeAddress",
    "ExternalAddress",
    "DataAddress",
    "Copy",
    "Select",
    "GcRefAddress",
    "PointerOffset",
    "ReferenceCompare",
    "IntUnary",
    "IntBinary",
    "IntHighMultiply",
    "IntWithOverflow",
    "IntCompare",
    "FloatUnary",
    "FloatBinary",
    "FloatTernary",
    "FloatCompare",
    "Convert",
    "Load",
    "Store",
    "AtomicLoad",
    "AtomicStore",
    "AtomicRmw",
    "AtomicCompareExchange",
    "AtomicFence",
    "Vector",
    "VectorLoad",
    "VectorStoreLane",
    "Call",
    "Safepoint",
}


def enum_variants(text: str, name: str) -> set[str]:
    match = re.search(
        rf"pub\(all\) enum {re.escape(name)} \{{\n(.*?)\n\}} derive",
        text,
        re.DOTALL,
    )
    if match is None:
        raise ValueError(f"missing public enum {name}")
    variants = set()
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        variants.add(re.split(r"[\s(]", stripped, maxsplit=1)[0])
    return variants


def audit(text: str) -> list[str]:
    failures = []
    for identifier in FORBIDDEN_PUBLIC_IDENTIFIERS:
        if re.search(rf"\b{re.escape(identifier)}\b", text):
            failures.append(f"forbidden public identifier {identifier}")

    for handle in ("Value", "Block", "Instruction", "Function"):
        if not re.search(
            rf"pub struct {handle} \{{\n  // private fields\n\}}",
            text,
        ):
            failures.append(f"{handle} must keep private canonical storage")

    try:
        value_types = enum_variants(text, "ValueType")
        if value_types != EXPECTED_VALUE_TYPES:
            failures.append(
                "ValueType must remain exactly "
                f"{sorted(EXPECTED_VALUE_TYPES)}, got {sorted(value_types)}"
            )
    except ValueError as error:
        failures.append(str(error))

    try:
        operations = enum_variants(text, "Operation")
        if operations != EXPECTED_OPERATION_FAMILIES:
            failures.append(
                "Operation families changed without updating the semantic "
                f"boundary audit: {sorted(operations)}"
            )
    except ValueError as error:
        failures.append(str(error))

    return failures


def main() -> int:
    if not INTERFACE.exists():
        print(
            "semantic MachV API audit failed: run `moon info` first",
            file=sys.stderr,
        )
        return 1
    failures = audit(INTERFACE.read_text(encoding="utf-8"))

    # Prove the negative checks reject representative target, ABI, and escape
    # hatch leaks rather than merely accepting the current interface.
    for leak in ("AArch64", "PhysicalRegister", "CallingConvention", "Custom"):
        if not audit(
            INTERFACE.read_text(encoding="utf-8")
            + f"\npub struct {leak} {{}}\n"
        ):
            failures.append(f"negative audit did not reject synthetic {leak}")

    if failures:
        print("semantic MachV API audit failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("semantic MachV API audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
