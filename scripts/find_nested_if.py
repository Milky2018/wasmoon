#!/usr/bin/env python3
"""
Find consecutive nested if statements without else blocks in MoonBit code.

Pattern:
if condition1 {
  if condition2 {
    ...
  }
}

These can often be combined into: if condition1 && condition2 { ... }
"""

import os
import re
import sys

def find_matching_brace(content: str, start: int) -> int:
    """Find the matching closing brace for an opening brace at start position."""
    if start >= len(content) or content[start] != '{':
        return -1

    depth = 1
    i = start + 1
    in_string = False
    string_char = None

    while i < len(content) and depth > 0:
        c = content[i]

        # Handle string literals
        if not in_string and c in '"\'':
            in_string = True
            string_char = c
        elif in_string and c == string_char and content[i-1:i] != '\\':
            in_string = False
        elif not in_string:
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
        i += 1

    return i - 1 if depth == 0 else -1

def get_line_number(content: str, pos: int) -> int:
    """Get line number for a position in content."""
    return content[:pos].count('\n') + 1

def extract_if_body(content: str, if_start: int) -> tuple[int, int, str] | None:
    """
    Extract the body of an if statement.
    Returns (body_start, body_end, body_content) or None if not found.
    """
    # Find opening brace
    brace_pos = content.find('{', if_start)
    if brace_pos == -1:
        return None

    # Check there's no 'else' between if and brace (simple check)
    between = content[if_start:brace_pos]

    # Find matching closing brace
    close_brace = find_matching_brace(content, brace_pos)
    if close_brace == -1:
        return None

    body = content[brace_pos + 1:close_brace]
    return (brace_pos + 1, close_brace, body)

def has_else_after(content: str, close_brace_pos: int) -> bool:
    """Check if there's an else keyword after the closing brace."""
    rest = content[close_brace_pos + 1:close_brace_pos + 50].strip()
    return rest.startswith('else')

def is_only_nested_if(body: str) -> tuple[bool, int]:
    """
    Check if the body contains only a nested if statement (with optional whitespace).
    Returns (is_nested_if, if_position_in_body).
    """
    stripped = body.strip()

    # Check if it starts with 'if'
    if not stripped.startswith('if'):
        return (False, -1)

    # Make sure it's 'if' followed by space/condition, not 'if_something'
    if len(stripped) > 2 and stripped[2].isalnum():
        return (False, -1)

    # Find where this if ends (its closing brace)
    # First find the opening brace of this if
    brace_pos = stripped.find('{')
    if brace_pos == -1:
        return (False, -1)

    close_brace = find_matching_brace(stripped, brace_pos)
    if close_brace == -1:
        return (False, -1)

    # Check if there's anything significant after the closing brace
    after = stripped[close_brace + 1:].strip()

    # If there's an else, it's not a simple nested if we can combine
    if after.startswith('else'):
        return (False, -1)

    # If there's other code after the if, it's not just a nested if
    if after:
        return (False, -1)

    # Find the position in the original body
    if_pos = body.find('if')
    return (True, if_pos)

def is_in_comment(content: str, pos: int) -> bool:
    """Check if position is inside a comment."""
    # Find the start of current line
    line_start = content.rfind('\n', 0, pos)
    if line_start == -1:
        line_start = 0
    else:
        line_start += 1

    line_content = content[line_start:pos]
    # Check if there's a // before this position on the same line
    return '//' in line_content


def find_nested_ifs(filepath: str) -> list[dict]:
    """Find all nested if statements without else in a file."""
    results = []

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return results

    # Find all 'if' keywords (not preceded by 'else')
    if_pattern = re.compile(r'(?<!else\s)\bif\b')

    for match in if_pattern.finditer(content):
        if_start = match.start()

        # Skip if in comment
        if is_in_comment(content, if_start):
            continue

        # Extract the if body
        body_info = extract_if_body(content, if_start)
        if not body_info:
            continue

        body_start, body_end, body = body_info

        # Check if outer if has an else
        if has_else_after(content, body_end):
            continue

        # Check if body contains only a nested if
        is_nested, nested_pos = is_only_nested_if(body)
        if not is_nested:
            continue

        # Check if the nested if also has no else
        nested_if_start = body_start + nested_pos
        nested_body_info = extract_if_body(content, nested_if_start)
        if not nested_body_info:
            continue

        _, nested_body_end, _ = nested_body_info
        if has_else_after(content, nested_body_end):
            continue

        # Found a nested if without else!
        line_num = get_line_number(content, if_start)

        # Get context (the full nested if structure)
        context_start = if_start
        context_end = body_end + 1
        context = content[context_start:context_end]

        # Get outer condition
        brace_pos = content.find('{', if_start)
        outer_cond = content[if_start + 2:brace_pos].strip()

        # Get inner condition
        inner_if_start = body.strip().find('if')
        inner_brace = body.find('{', inner_if_start)
        inner_cond = body[inner_if_start + 2:inner_brace].strip() if inner_brace > inner_if_start else ""

        results.append({
            'file': filepath,
            'line': line_num,
            'context': context,
            'outer_condition': outer_cond,
            'inner_condition': inner_cond,
        })

    return results

def main():
    # Default to current directory
    search_dir = '.'
    if len(sys.argv) > 1:
        search_dir = sys.argv[1]

    all_results = []

    # Walk through directory
    for root, dirs, files in os.walk(search_dir):
        # Skip hidden directories and common non-source dirs
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ['target', 'node_modules', '.mooncakes']]

        for filename in files:
            if filename.endswith('.mbt'):
                filepath = os.path.join(root, filename)
                results = find_nested_ifs(filepath)
                all_results.extend(results)

    # Print results
    for result in all_results:
        print("=" * 60)
        print(f"File: {result['file']}:{result['line']}")
        print(f"Outer: {result['outer_condition'][:60]}..." if len(result['outer_condition']) > 60 else f"Outer: {result['outer_condition']}")
        print(f"Inner: {result['inner_condition'][:60]}..." if len(result['inner_condition']) > 60 else f"Inner: {result['inner_condition']}")
        print("Context:")
        print("-" * 40)
        # Limit context display
        context_lines = result['context'].split('\n')
        if len(context_lines) > 15:
            for line in context_lines[:12]:
                print(line)
            print("    ...")
            print(context_lines[-1])
        else:
            print(result['context'])
        print()

    print("=" * 60)
    print(f"Total found: {len(all_results)}")

if __name__ == '__main__':
    main()
