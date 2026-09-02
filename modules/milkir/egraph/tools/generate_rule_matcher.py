#!/usr/bin/env python3
"""Generate the default e-graph rule registry and its compiled prefilter.

Each ``rule NAME TAG,...`` line registers one rewrite. Its ``when`` lines are
alternative necessary conditions for invoking that rewrite. A condition may be
conservative and admit false positives, but it must never reject an e-node on
which the handwritten rewrite can succeed. Rules without ``when`` lines remain
unfiltered. The generator shares identical conditions and emits a dispatch tree
over root opcode, child arity, and integer-comparison condition.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path
import re
import sys


RULE_RE = re.compile(r"^rule\s+(rule_[A-Za-z0-9_]+)\s+(.+)$")
WHEN_RE = re.compile(r"^when(?:\s+(.*))?$")
TAG_RE = re.compile(r"^T[A-Za-z0-9_]+$")


@dataclass(frozen=True)
class Pattern:
    arity: int | None = None
    child_consts: tuple[int, ...] = ()
    child_const_values: tuple[tuple[int, int], ...] = ()
    child_fconsts: tuple[int, ...] = ()
    child_not_consts: tuple[int, ...] = ()
    child_opcodes: tuple[tuple[int, str], ...] = ()
    equivalent_children: tuple[tuple[int, int], ...] = ()
    root_icmp: int | None = None


@dataclass
class Rule:
    name: str
    tags: list[str]
    comments: list[str]
    patterns: list[Pattern] = field(default_factory=list)


def parse_pair(value: str, *, value_name: str) -> tuple[int, int]:
    fields = value.split(":")
    if len(fields) != 2:
        raise ValueError(f"{value_name} expects INDEX:VALUE, got {value!r}")
    return int(fields[0]), int(fields[1])


def parse_opcode_pair(value: str) -> tuple[int, str]:
    fields = value.split(":", 1)
    if len(fields) != 2:
        raise ValueError(f"child-op expects INDEX:TAG, got {value!r}")
    index, tag = fields
    if not TAG_RE.fullmatch(tag):
        raise ValueError(f"invalid child opcode tag {tag!r}")
    return int(index), tag


def parse_pattern(text: str) -> Pattern:
    values: dict[str, object] = {
        "child_consts": [],
        "child_const_values": [],
        "child_fconsts": [],
        "child_not_consts": [],
        "child_opcodes": [],
        "equivalent_children": [],
    }
    for field in text.split():
        if "=" not in field:
            raise ValueError(f"pattern field must use NAME=VALUE: {field!r}")
        name, value = field.split("=", 1)
        if name == "arity":
            if "arity" in values:
                raise ValueError("arity may only be specified once")
            values["arity"] = int(value)
        elif name == "const":
            values["child_consts"].append(int(value))
        elif name == "const-value":
            values["child_const_values"].append(
                parse_pair(value, value_name=name)
            )
        elif name == "fconst":
            values["child_fconsts"].append(int(value))
        elif name == "not-const":
            values["child_not_consts"].append(int(value))
        elif name == "child-op":
            values["child_opcodes"].append(parse_opcode_pair(value))
        elif name == "equiv":
            values["equivalent_children"].append(
                parse_pair(value, value_name=name)
            )
        elif name == "root-icmp":
            if "root_icmp" in values:
                raise ValueError("root-icmp may only be specified once")
            values["root_icmp"] = int(value)
        else:
            raise ValueError(f"unknown pattern field {name!r}")
    pattern = Pattern(
        arity=values.get("arity"),
        child_consts=tuple(values["child_consts"]),
        child_const_values=tuple(values["child_const_values"]),
        child_fconsts=tuple(values["child_fconsts"]),
        child_not_consts=tuple(values["child_not_consts"]),
        child_opcodes=tuple(values["child_opcodes"]),
        equivalent_children=tuple(values["equivalent_children"]),
        root_icmp=values.get("root_icmp"),
    )
    if pattern.arity is None or pattern.arity < 0:
        raise ValueError("matcher patterns require a non-negative arity")
    indices = [
        *pattern.child_consts,
        *(index for index, _ in pattern.child_const_values),
        *pattern.child_fconsts,
        *pattern.child_not_consts,
        *(index for index, _ in pattern.child_opcodes),
        *(index for pair in pattern.equivalent_children for index in pair),
    ]
    if any(index < 0 or index >= pattern.arity for index in indices):
        raise ValueError("child indices must be within the declared arity")
    if pattern.root_icmp is not None and not 0 <= pattern.root_icmp <= 9:
        raise ValueError("root-icmp must be between 0 and 9")
    return pattern


def parse_schema(path: Path) -> list[Rule]:
    rules: list[Rule] = []
    comments: list[str] = []
    current: Rule | None = None
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#"):
            comments.append(line[1:].strip())
            continue
        if match := RULE_RE.fullmatch(line):
            tags_text = match.group(2)
            tags = [] if tags_text == "*" else [
                tag.strip() for tag in tags_text.split(",")
            ]
            if any(not TAG_RE.fullmatch(tag) for tag in tags):
                raise ValueError(f"{path}:{line_number}: invalid tag list")
            current = Rule(match.group(1), tags, comments)
            comments = []
            rules.append(current)
            continue
        if match := WHEN_RE.fullmatch(line):
            if current is None:
                raise ValueError(f"{path}:{line_number}: when without rule")
            if not current.tags:
                raise ValueError(
                    f"{path}:{line_number}: universal rules cannot use when"
                )
            try:
                pattern = parse_pattern(match.group(1) or "")
            except ValueError as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
            if pattern.root_icmp is not None and "TIcmp" not in current.tags:
                raise ValueError(
                    f"{path}:{line_number}: root-icmp requires a TIcmp rule"
                )
            current.patterns.append(pattern)
            continue
        raise ValueError(f"{path}:{line_number}: invalid schema line {line!r}")
    if comments:
        raise ValueError(f"{path}: trailing comments are not attached to a rule")
    names = [rule.name for rule in rules]
    if len(names) != len(set(names)):
        raise ValueError(f"{path}: rule names must be unique")
    buckets: dict[str, int] = {}
    for rule in rules:
        for tag in rule.tags:
            buckets[tag] = buckets.get(tag, 0) + 1
    oversized = {tag: count for tag, count in buckets.items() if count > 64}
    if oversized:
        raise ValueError(f"opcode buckets exceed UInt64 matcher capacity: {oversized}")
    return rules


def moon_int64(value: int) -> str:
    return f"{value}L"


def emit_pattern(
    pattern: Pattern,
    *,
    include_arity: bool = True,
    include_root_icmp: bool = True,
) -> str:
    checks: list[str] = []
    required_indices = [
        *pattern.child_consts,
        *(index for index, _ in pattern.child_const_values),
        *pattern.child_fconsts,
        *pattern.child_not_consts,
        *(index for index, _ in pattern.child_opcodes),
        *(index for pair in pattern.equivalent_children for index in pair),
    ]
    if include_arity and pattern.arity is not None:
        checks.append(f"node.children.length() == {pattern.arity}")
    elif include_arity and required_indices:
        checks.append(f"node.children.length() > {max(required_indices)}")
    if include_root_icmp and pattern.root_icmp is not None:
        checks.append(f"node.op is Icmp({pattern.root_icmp})")
    for index in pattern.child_consts:
        checks.append(f"eg.find_const(node.children[{index}]) is Some(_)")
    for index, value in pattern.child_const_values:
        checks.append(
            f"eg.find_const(node.children[{index}]) is Some({moon_int64(value)})"
        )
    for index in pattern.child_fconsts:
        checks.append(f"eg.find_fconst(node.children[{index}]) is Some(_)")
    for index in pattern.child_not_consts:
        checks.append(f"eg.find_const(node.children[{index}]) is None")
    for index, tag in pattern.child_opcodes:
        checks.append(
            f"generated_child_has_opcode(eg, node.children[{index}], {tag})"
        )
    for left, right in pattern.equivalent_children:
        checks.append(
            f"eg.equiv(node.children[{left}], node.children[{right}])"
        )
    return " && ".join(checks) if checks else "true"


def emit_pattern_leaves(
    pattern_masks: dict[Pattern, int],
    *,
    indent: str,
) -> list[str]:
    lines: list[str] = []
    for pattern, mask in pattern_masks.items():
        expression = emit_pattern(
            pattern,
            include_arity=False,
            include_root_icmp=False,
        )
        lines.extend([
            f"{indent}if {expression} {{",
            f"{indent}  bits = bits | 0x{mask:016X}UL",
            f"{indent}}}",
        ])
    return lines


def emit_bucket_tree(bucket: list[Rule]) -> list[str]:
    by_arity: dict[int, dict[Pattern, int]] = {}
    for index, rule in enumerate(bucket):
        for pattern in rule.patterns:
            if pattern.arity is None:
                raise ValueError(f"{rule.name}: matcher patterns require arity")
            masks = by_arity.setdefault(pattern.arity, {})
            masks[pattern] = masks.get(pattern, 0) | (1 << index)

    lines = ["        match node.children.length() {"]
    for arity, pattern_masks in by_arity.items():
        generic = {
            pattern: mask
            for pattern, mask in pattern_masks.items()
            if pattern.root_icmp is None
        }
        by_icmp: dict[int, dict[Pattern, int]] = {}
        for pattern, mask in pattern_masks.items():
            if pattern.root_icmp is not None:
                by_icmp.setdefault(pattern.root_icmp, {})[pattern] = mask
        lines.append(f"          {arity} => {{")
        lines.extend(emit_pattern_leaves(generic, indent="            "))
        if by_icmp:
            lines.append("            match node.op {")
            for condition, masks in by_icmp.items():
                lines.append(f"              Icmp({condition}) => {{")
                lines.extend(emit_pattern_leaves(masks, indent="                "))
                lines.append("              }")
            lines.append("              _ => ()")
            lines.append("            }")
        lines.append("          }")
    lines.extend(["          _ => ()", "        }"])
    return lines


def emit_registry(rules: list[Rule]) -> list[str]:
    lines = [
        "///|",
        "/// Build the default indexed ruleset from the matcher schema.",
        "fn generated_build_indexed_ruleset() -> IndexedRuleSet {",
        "  let rs = IndexedRuleSet::IndexedRuleSet()",
    ]
    for rule in rules:
        lines.extend(f"  // {comment}" for comment in rule.comments)
        tags = ", ".join(rule.tags)
        lines.append(f"  rs.add_rule({rule.name}(), [{tags}])")
    lines.extend([
        "  rs.use_generated_matcher()",
        "  rs",
        "}",
        "",
    ])
    return lines


def emit_matcher(rules: list[Rule]) -> list[str]:
    buckets: dict[str, list[Rule]] = {}
    for rule in rules:
        for tag in rule.tags:
            buckets.setdefault(tag, []).append(rule)
    lines = [
        "///|",
        "fn generated_rule_bucket_size(tag : EOpcodeTag) -> Int {",
        "  match tag {",
        *(f"    {tag} => {len(bucket)}" for tag, bucket in buckets.items()),
        "    _ => 0",
        "  }",
        "}",
        "",
    ]
    lines.extend([
        "///|",
        "fn generated_child_has_opcode(",
        "  eg : EGraph,",
        "  class_id : EClassId,",
        "  tag : EOpcodeTag,",
        ") -> Bool {",
        "  for node in eg.get_nodes(class_id) {",
        "    if node.op.tag() == tag {",
        "      return true",
        "    }",
        "  }",
        "  false",
        "}",
        "",
    ])
    lines.extend([
        "///|",
        "fn generated_rule_match_bits(",
        "  eg : EGraph,",
        "  class_id : EClassId,",
        "  tag : EOpcodeTag,",
        ") -> UInt64 {",
        "  match tag {",
    ])
    for tag, bucket in buckets.items():
        if not any(rule.patterns for rule in bucket):
            continue
        always_mask = sum(
            1 << index for index, rule in enumerate(bucket) if not rule.patterns
        )
        lines.extend([
            f"    {tag} => {{",
            f"      let mut bits = 0x{always_mask:016X}UL",
            "      for node in eg.get_nodes(class_id) {",
            f"        if node.op.tag() != {tag} {{",
            "          continue",
            "        }",
        ])
        lines.extend(emit_bucket_tree(bucket))
        lines.extend(["      }", "      bits", "    }"])
    lines.extend([
        "    _ => 0xFFFFFFFFFFFFFFFFUL",
        "  }",
        "}",
        "",
    ])
    return lines


def generate(rules: list[Rule], schema_name: str) -> str:
    lines = [
        f"// Generated by tools/generate_rule_matcher.py from {schema_name}.",
        "// DO NOT EDIT. Update the schema and run a Moon development command.",
        "",
        *emit_registry(rules),
        *emit_matcher(rules),
    ]
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
