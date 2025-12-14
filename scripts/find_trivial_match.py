#!/usr/bin/env python3
"""Find match expressions where one branch is trivial and could be replaced with if-is.

Examples to find:
  match opt { Some(v) => ...; None => () }
  match result { Ok(v) => ...; Err(_) => () }
  match opt { None => (); Some(v) => ... }
"""

import re
from pathlib import Path


def find_trivial_matches(content: str, filepath: Path) -> list[tuple[int, str]]:
    """Find match expressions with one trivial branch.

    Returns list of (line_number, matched_text) tuples.
    """
    matches = []

    # Look for specific patterns where one branch is just ()
    # Pattern 1: Some pattern => ()
    trivial_branch_patterns = [
        # Pattern => () followed by newline/space and another pattern
        r'(\w+(?:\([^)]*\))?\s*=>\s*\(\)\s*(?:\n|\s)*\w+(?:\([^)]*\))?\s*=>)',
        # Pattern => something, then another Pattern => ()
        r'(\w+(?:\([^)]*\))?\s*=>[^}]+?\w+(?:\([^)]*\))?\s*=>\s*\(\))',
    ]

    for pattern in trivial_branch_patterns:
        for match in re.finditer(pattern, content, re.MULTILINE | re.DOTALL):
            # Find the start of the match expression
            # Search backwards for 'match'
            start = match.start()
            before_text = content[:start]
            match_keyword_pos = before_text.rfind('match', max(0, start - 200))

            if match_keyword_pos == -1:
                continue

            # Find the end of the match expression (closing brace)
            end = match.end()
            remaining = content[end:]
            # Count braces to find the matching closing brace
            brace_count = content[match_keyword_pos:match.start()].count('{') - content[match_keyword_pos:match.start()].count('}')
            brace_count += 1  # For the opening brace of match

            pos = 0
            for char in remaining:
                if char == '{':
                    brace_count += 1
                elif char == '}':
                    brace_count -= 1
                    if brace_count == 0:
                        break
                pos += 1

            full_match_end = end + pos + 1

            # Extract full match expression
            full_match_text = content[match_keyword_pos:full_match_end]

            # Find line number
            line_num = content[:match_keyword_pos].count('\n') + 1

            # Clean up for display
            display_text = ' '.join(full_match_text.split())
            if len(display_text) > 120:
                display_text = display_text[:117] + '...'

            matches.append((line_num, display_text))

    # Remove duplicates
    seen = set()
    unique_matches = []
    for line_num, text in matches:
        key = (line_num, text[:50])  # Use first 50 chars as key
        if key not in seen:
            seen.add(key)
            unique_matches.append((line_num, text))

    return unique_matches


def scan_file(filepath: Path) -> list[tuple[int, str]]:
    """Scan a single .mbt file for trivial matches."""
    try:
        content = filepath.read_text(encoding='utf-8')
        return find_trivial_matches(content, filepath)
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []


def main() -> None:
    """Scan all .mbt files in the project."""
    project_root = Path(__file__).parent.parent
    mbt_files = sorted(project_root.rglob('*.mbt'))

    # Exclude .mooncakes and other build directories
    mbt_files = [
        f for f in mbt_files
        if '.mooncakes' not in str(f) and 'target' not in str(f)
    ]

    print(f"Scanning {len(mbt_files)} .mbt files for trivial match expressions...\n")

    total_matches = 0
    files_with_matches = 0

    for mbt_file in mbt_files:
        matches = scan_file(mbt_file)
        if matches:
            files_with_matches += 1
            total_matches += len(matches)

            rel_path = mbt_file.relative_to(project_root)
            print(f"\n{rel_path}:")
            for line_num, matched_text in matches:
                print(f"  Line {line_num}: {matched_text}")

    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Files scanned: {len(mbt_files)}")
    print(f"  Files with trivial matches: {files_with_matches}")
    print(f"  Total trivial matches found: {total_matches}")
    print(f"{'='*60}")

    if total_matches > 0:
        print("\nThese match expressions could potentially be replaced with if-is:")
        print("  if value is Pattern(v) { ... }")


if __name__ == "__main__":
    main()
