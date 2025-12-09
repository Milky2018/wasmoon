#!/usr/bin/env python3
"""
Replace `let _ = xxx` with `xxx |> ignore` in MoonBit files.

Usage:
    python scripts/fix_let_ignore.py [--dry-run] [path...]

Examples:
    python scripts/fix_let_ignore.py                    # Fix all .mbt files
    python scripts/fix_let_ignore.py --dry-run          # Preview changes
    python scripts/fix_let_ignore.py src/foo.mbt        # Fix specific file
"""

import re
import sys
from pathlib import Path


def find_mbt_files(paths: list[str]) -> list[Path]:
    """Find all .mbt files in given paths, or all in project if no paths given."""
    if not paths:
        # Find all .mbt files in project, excluding hidden dirs and target
        root = Path(__file__).parent.parent
        return [
            f for f in root.rglob("*.mbt")
            if not any(part.startswith('.') or part == 'target' for part in f.parts)
        ]

    result = []
    for p in paths:
        path = Path(p)
        if path.is_file() and path.suffix == '.mbt':
            result.append(path)
        elif path.is_dir():
            result.extend(path.rglob("*.mbt"))
    return result


def insert_ignore_before_comment(expr: str) -> str:
    """
    Insert `|> ignore` before any trailing comment.

    Examples:
        "foo()"              -> "foo() |> ignore"
        "foo() // comment"   -> "foo() |> ignore // comment"
        "foo() /// doc"      -> "foo() |> ignore /// doc"
    """
    # Find // comment (but not inside a string)
    # Simple approach: find the first // that's not inside quotes
    in_string = False
    string_char = None
    i = 0
    while i < len(expr):
        c = expr[i]
        if in_string:
            if c == '\\' and i + 1 < len(expr):
                i += 2  # Skip escaped char
                continue
            if c == string_char:
                in_string = False
        else:
            if c in '"\'':
                in_string = True
                string_char = c
            elif c == '/' and i + 1 < len(expr) and expr[i + 1] == '/':
                # Found comment start
                code_part = expr[:i].rstrip()
                comment_part = expr[i:]
                return f"{code_part} |> ignore {comment_part}"
        i += 1

    # No comment found
    return f"{expr} |> ignore"


def fix_let_ignore(content: str) -> tuple[str, int]:
    """
    Replace `let _ = expr` with `expr |> ignore`.

    Returns (new_content, count of replacements).
    """
    # Pattern explanation:
    # - `let\s+_\s*=\s*` matches "let _ = " with flexible whitespace
    # - We need to capture the expression that follows
    # - The expression ends at a newline (for simple cases)

    count = 0
    lines = content.split('\n')
    result_lines = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Match `let _ = ` at the start (with possible indentation)
        match = re.match(r'^(\s*)let\s+_\s*=\s*(.*)$', line)

        if match:
            indent = match.group(1)
            expr_start = match.group(2)

            # Check if this is a simple single-line expression
            # We need to handle multi-line expressions too

            # Collect the full expression (handle multi-line)
            expr_lines = [expr_start]

            # Count brackets to detect multi-line expressions
            def count_brackets(s):
                opens = s.count('(') + s.count('[') + s.count('{')
                closes = s.count(')') + s.count(']') + s.count('}')
                return opens - closes

            bracket_balance = count_brackets(expr_start)

            # Continue collecting lines if brackets are unbalanced
            while bracket_balance > 0 and i + 1 < len(lines):
                i += 1
                next_line = lines[i]
                expr_lines.append(next_line)
                bracket_balance += count_brackets(next_line)

            # Build the replacement
            if len(expr_lines) == 1:
                # Simple case: single line
                expr = expr_start.rstrip()
                if expr:
                    # Handle trailing comments: extract comment and put |> ignore before it
                    expr_with_ignore = insert_ignore_before_comment(expr)
                    result_lines.append(f"{indent}{expr_with_ignore}")
                    count += 1
                else:
                    # Empty expression, keep original
                    result_lines.append(line)
            else:
                # Multi-line expression
                # First line
                result_lines.append(f"{indent}{expr_start}")
                # Middle lines (keep as-is)
                for mid_line in expr_lines[1:-1]:
                    result_lines.append(mid_line)
                # Last line: append |> ignore (handle trailing comment)
                last_line = expr_lines[-1].rstrip()
                last_line_with_ignore = insert_ignore_before_comment(last_line)
                result_lines.append(last_line_with_ignore)
                count += 1
        else:
            result_lines.append(line)

        i += 1

    return '\n'.join(result_lines), count


def process_file(path: Path, dry_run: bool = False) -> int:
    """Process a single file. Returns count of replacements."""
    content = path.read_text()
    new_content, count = fix_let_ignore(content)

    if count > 0:
        if dry_run:
            print(f"{path}: {count} replacement(s) would be made")
            # Show diff preview
            old_lines = content.split('\n')
            new_lines = new_content.split('\n')
            for i, (old, new) in enumerate(zip(old_lines, new_lines)):
                if old != new:
                    print(f"  L{i+1}:")
                    print(f"    - {old}")
                    print(f"    + {new}")
        else:
            path.write_text(new_content)
            print(f"{path}: {count} replacement(s) made")

    return count


def main():
    args = sys.argv[1:]
    dry_run = '--dry-run' in args
    if dry_run:
        args.remove('--dry-run')

    files = find_mbt_files(args)

    if not files:
        print("No .mbt files found")
        return

    total = 0
    for f in sorted(files):
        total += process_file(f, dry_run)

    print(f"\nTotal: {total} replacement(s)" + (" (dry-run)" if dry_run else ""))


if __name__ == '__main__':
    main()
