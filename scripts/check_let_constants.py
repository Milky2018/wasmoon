#!/usr/bin/env python3
"""
Check for constants defined with 'let' instead of 'const'.

This script finds potential constants that should use 'const' instead of 'let'.
It looks for patterns like:
  - let UPPERCASE_NAME : Type = value
  - let name_with_numbers123 : Int = literal

Usage:
  python3 scripts/check_let_constants.py [directory]
"""

import os
import re
import sys
from pathlib import Path


def find_let_constants(directory: str, exclude_dirs: list[str] = None) -> list[tuple[str, int, str]]:
    """Find all potential constants defined with 'let' instead of 'const'."""
    if exclude_dirs is None:
        exclude_dirs = ['target', '.git', 'node_modules', '__pycache__']

    results = []

    # Patterns for finding let definitions that look like constants
    # Pattern 1: let followed by UPPERCASE identifier
    pattern_uppercase = re.compile(r'^\s*let\s+([A-Z][A-Z0-9_]*)\s*:\s*\w+\s*=')

    # Pattern 2: let followed by snake_case with all letters lowercase and a simple literal value
    # This catches things like: let cc_slt : Int = 2
    pattern_const_value = re.compile(r'^\s*let\s+([a-z_][a-z0-9_]*)\s*:\s*(Int|UInt|Int64|UInt64|Float|Double|String|Bool)\s*=\s*(-?\d+|"[^"]*"|true|false|0x[0-9a-fA-F]+)\s*$')

    for root, dirs, files in os.walk(directory):
        # Modify dirs in-place to skip excluded directories
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        for filename in files:
            if not filename.endswith('.mbt'):
                continue

            filepath = os.path.join(root, filename)
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    for lineno, line in enumerate(f, 1):
                        # Check for uppercase let definitions
                        match = pattern_uppercase.match(line)
                        if match:
                            results.append((filepath, lineno, line.rstrip()))
                            continue

                        # Check for lowercase let definitions with constant values
                        match = pattern_const_value.match(line)
                        if match:
                            results.append((filepath, lineno, line.rstrip()))
            except Exception as e:
                print(f"Error reading {filepath}: {e}", file=sys.stderr)

    return results


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else '.'

    if not os.path.isdir(directory):
        print(f"Error: {directory} is not a directory", file=sys.stderr)
        sys.exit(1)

    results = find_let_constants(directory)

    if not results:
        print("No potential 'let' constants found.")
        return

    print(f"Found {len(results)} potential constants that should use 'const':\n")

    current_file = None
    for filepath, lineno, line in sorted(results):
        rel_path = os.path.relpath(filepath, directory)
        if rel_path != current_file:
            current_file = rel_path
            print(f"\n{rel_path}:")
        print(f"  {lineno}: {line}")

    print(f"\n\nTotal: {len(results)} potential issues")
    print("\nSuggestion: Replace 'let' with 'const' and use UPPERCASE names for constants.")


if __name__ == '__main__':
    main()
