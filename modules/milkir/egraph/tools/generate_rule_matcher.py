#!/usr/bin/env python3
"""Generate the default e-graph rule registry and its compiled dispatcher.

Each ``rule NAME TAG,...`` line registers one rewrite. Its ``when`` lines are
alternative necessary conditions for invoking that rewrite. A condition may be
conservative and admit false positives, but it must never reject an e-node on
which the handwritten rewrite can succeed. Rules without ``when`` lines remain
unfiltered. The generator shares identical conditions and emits a dispatch tree
over root opcode, child arity, and integer-comparison condition. Child facts
are computed once per e-node and shared by all candidate-rule predicates.
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


@dataclass(frozen=True, order=True)
class MatchAtom:
    kind: str
    left: int
    value: int | str | None = None


def pattern_atoms(pattern: Pattern) -> frozenset[MatchAtom]:
    atoms = [
        *(MatchAtom("const", index) for index in pattern.child_consts),
        *(
            MatchAtom("const_value", index, value)
            for index, value in pattern.child_const_values
        ),
        *(MatchAtom("fconst", index) for index in pattern.child_fconsts),
        *(MatchAtom("not_const", index) for index in pattern.child_not_consts),
        *(
            MatchAtom("child_opcode", index, tag)
            for index, tag in pattern.child_opcodes
        ),
        *(
            MatchAtom("equivalent", left, right)
            for left, right in pattern.equivalent_children
        ),
        *(
            [MatchAtom("root_icmp", pattern.root_icmp)]
            if pattern.root_icmp is not None
            else []
        ),
    ]
    return frozenset(atoms)


def atom_expression(atom: MatchAtom, opcode_bits: dict[str, int]) -> str:
    if atom.kind == "const":
        return f"child_{atom.left}_const is Some(_)"
    if atom.kind == "const_value":
        return (
            f"child_{atom.left}_const is Some("
            f"{moon_int64(int(atom.value))})"
        )
    if atom.kind == "fconst":
        return f"child_{atom.left}_fconst is Some(_)"
    if atom.kind == "not_const":
        return f"child_{atom.left}_const is None"
    if atom.kind == "child_opcode":
        return (
            f"(child_{atom.left}_opcodes & "
            f"0x{opcode_bits[str(atom.value)]:016X}UL) != 0UL"
        )
    if atom.kind == "equivalent":
        return f"eg.equiv(node.children[{atom.left}], node.children[{atom.value}])"
    if atom.kind == "root_icmp":
        return f"node.op is Icmp({atom.left})"
    raise ValueError(f"unknown matcher atom {atom}")


def emit_bucket_tree(
    bucket: list[Rule], opcode_bits: dict[str, int]
) -> list[str]:
    by_arity: dict[int, list[tuple[int, Pattern]]] = {}
    for index, rule in enumerate(bucket):
        for pattern in rule.patterns:
            if pattern.arity is None:
                raise ValueError(f"{rule.name}: matcher patterns require arity")
            by_arity.setdefault(pattern.arity, []).append((index, pattern))

    lines = ["        match node.children.length() {"]
    for arity, indexed_patterns in by_arity.items():
        lines.append(f"          {arity} => {{")
        used_atoms = {
            atom
            for _, pattern in indexed_patterns
            for atom in pattern_atoms(pattern)
        }
        const_indices = sorted({
            atom.left
            for atom in used_atoms
            if atom.kind in ("const", "const_value", "not_const")
        })
        fconst_indices = sorted({
            atom.left for atom in used_atoms if atom.kind == "fconst"
        })
        opcode_indices = sorted({
            atom.left for atom in used_atoms if atom.kind == "child_opcode"
        })
        for index in const_indices:
            lines.append(
                f"            let child_{index}_const = "
                f"eg.find_const(node.children[{index}])"
            )
        for index in fconst_indices:
            lines.append(
                f"            let child_{index}_fconst = "
                f"eg.find_fconst(node.children[{index}])"
            )
        for index in opcode_indices:
            lines.append(
                f"            let child_{index}_opcodes = "
                f"generated_child_opcode_bits(eg, node.children[{index}])"
            )
        pattern_count = len(indexed_patterns)
        word_count = (pattern_count + 63) // 64
        for word in range(word_count):
            bits = min(64, pattern_count - word * 64)
            initial = (1 << bits) - 1
            lines.append(
                f"            let mut patterns_{word} = 0x{initial:016X}UL"
            )
        for atom in sorted(used_atoms):
            masks = [0] * word_count
            for pattern_index, (_, pattern) in enumerate(indexed_patterns):
                if atom in pattern_atoms(pattern):
                    masks[pattern_index // 64] |= 1 << (pattern_index % 64)
            lines.append(
                f"            if !({atom_expression(atom, opcode_bits)}) {{"
            )
            for word, mask in enumerate(masks):
                if mask:
                    lines.append(
                        f"              patterns_{word} = patterns_{word} & "
                        f"0x{(~mask & ((1 << 64) - 1)):016X}UL"
                    )
            lines.append("            }")
        for word in range(word_count):
            lines.extend([
                f"            while patterns_{word} != 0UL {{",
                f"              let pattern_index = patterns_{word}.ctz() + {word * 64}",
                f"              patterns_{word} = patterns_{word} & (patterns_{word} - 1UL)",
                "              match pattern_index {",
            ])
            for pattern_index, (rule_index, _) in enumerate(indexed_patterns):
                if pattern_index // 64 == word:
                    lines.append(
                        f"                {pattern_index} => bits = bits | "
                        f"0x{1 << rule_index:016X}UL"
                    )
            lines.extend([
                "                _ => ()",
                "              }",
                "            }",
            ])
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
        lines.append(f"  rs.add_rule({rule.name}, [{tags}])")
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
    child_opcodes = sorted({
        tag
        for rule in rules
        for pattern in rule.patterns
        for _, tag in pattern.child_opcodes
    })
    opcode_bits = {tag: 1 << index for index, tag in enumerate(child_opcodes)}
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
        "fn generated_child_opcode_bits(",
        "  eg : EGraph,",
        "  class_id : EClassId,",
        ") -> UInt64 {",
        "  let mut bits = 0UL",
        "  for node in eg.get_nodes(class_id) {",
        "    match node.op.tag() {",
        *(f"      {tag} => bits = bits | 0x{opcode_bits[tag]:016X}UL" for tag in child_opcodes),
        "      _ => ()",
        "    }",
        "  }",
        "  bits",
        "}",
        "",
    ])
    lines.extend([
        "///|",
        "fn generated_apply_rule(",
        "  eg : EGraph,",
        "  class_id : EClassId,",
        "  node : ENode,",
        "  tag : EOpcodeTag,",
        "  rule_index : Int,",
        ") -> Bool {",
        "  match tag {",
    ])
    for tag, bucket in buckets.items():
        lines.extend([
            f"    {tag} =>",
            "      match rule_index {",
            *(
                f"        {index} => {rule.name}(eg, class_id, node)"
                for index, rule in enumerate(bucket)
            ),
            "        _ => false",
            "      }",
        ])
    lines.extend([
        "    _ => false",
        "  }",
        "}",
        "",
    ])
    lines.extend([
        "///|",
        "fn generated_rule_match_bits(",
        "  eg : EGraph,",
        "  node : ENode,",
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
            f"      guard node.op.tag() == {tag} else {{ return 0UL }}",
        ])
        lines.extend(emit_bucket_tree(bucket, opcode_bits))
        lines.extend(["      bits", "    }"])
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
