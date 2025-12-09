#!/usr/bin/env python3
"""
Find match expressions with only two branches where one is a wildcard (_)
that returns Unit (i.e., `_ => ()`).
These can typically be replaced with `if ... is` pattern.
"""

import re
import sys
from pathlib import Path


def find_simple_matches(filepath: Path) -> list[tuple[int, str, str]]:
    """
    Find match expressions that have exactly two branches with one being a wildcard
    that returns Unit.
    Returns list of (line_number, match_expr, context).
    """
    results = []
    content = filepath.read_text()
    lines = content.split('\n')

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Look for match expression start
        match_start = re.search(r'\bmatch\s+', stripped)
        if not match_start:
            i += 1
            continue

        # Find the opening brace
        start_line = i
        brace_pos = line.find('{', match_start.start())

        # If no brace on same line, look on next lines
        search_line = i
        while brace_pos == -1 and search_line < min(i + 3, len(lines)):
            search_line += 1
            if search_line < len(lines):
                brace_pos = lines[search_line].find('{')
                if brace_pos != -1:
                    break

        if brace_pos == -1:
            i += 1
            continue

        # Now collect the match block
        brace_count = 1
        match_content = []
        j = search_line

        # Start after the opening brace
        if j == i:
            rest = line[brace_pos + 1:]
        else:
            rest = lines[j][brace_pos + 1:]

        match_content.append(rest)
        brace_count += rest.count('{') - rest.count('}')
        j += 1

        while j < len(lines) and brace_count > 0:
            current_line = lines[j]
            brace_count += current_line.count('{') - current_line.count('}')
            match_content.append(current_line)
            j += 1

        end_line = j

        # Analyze the match content
        full_match = '\n'.join(match_content)

        # Count the number of => patterns (branches)
        # Be careful to not count => inside nested blocks
        branch_count = 0
        wildcard_unit_branch = False
        depth = 0

        for line_content in match_content:
            for k, char in enumerate(line_content):
                if char == '{':
                    depth += 1
                elif char == '}':
                    depth -= 1
                elif char == '=' and depth == 0:
                    # Check if this is =>
                    if k + 1 < len(line_content) and line_content[k + 1] == '>':
                        branch_count += 1

        # Check for wildcard branch that returns Unit: _ => ()
        if re.search(r'^\s*_\s*=>\s*\(\)\s*$', full_match, re.MULTILINE):
            wildcard_unit_branch = True

        # Check if it's a simple two-branch match with wildcard returning Unit
        if branch_count == 2 and wildcard_unit_branch:
            # Get context
            context_lines = lines[start_line:min(end_line, start_line + 10)]
            context = '\n'.join(context_lines)

            # Get the match expression
            match_expr = lines[start_line].strip()

            results.append((start_line + 1, match_expr, context))

        i = end_line

    return results


def main():
    # Find all .mbt files
    root = Path('/Users/zhengyu/Documents/projects/wasmoon')
    mbt_files = list(root.rglob('*.mbt'))

    # Exclude target/, .mooncakes/, and test files
    mbt_files = [f for f in mbt_files
                 if 'target/' not in str(f)
                 and '.mooncakes' not in str(f)
                 and '_test' not in f.name
                 and '_wbtest' not in f.name]

    total_found = 0

    for filepath in sorted(mbt_files):

        results = find_simple_matches(filepath)

        if results:
            rel_path = filepath.relative_to(root)
            for line_num, match_expr, context in results:
                total_found += 1
                print(f"\n{'='*60}")
                print(f"File: {rel_path}:{line_num}")
                print(f"Match: {match_expr}")
                print(f"Context:")
                print("-" * 40)
                # Indent context
                for ctx_line in context.split('\n'):
                    print(f"  {ctx_line}")

    print(f"\n{'='*60}")
    print(f"Total found: {total_found}")


if __name__ == '__main__':
    main()
