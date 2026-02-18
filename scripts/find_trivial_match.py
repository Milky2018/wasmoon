#!/usr/bin/env python3
"""Find match expressions where one branch is trivial and could be replaced with if-is.

Examples to find:
  match opt { Some(v) => ...; None => () }
  match result { Ok(v) => ...; Err(_) => () }
  match opt { None => (); Some(v) => ... }

This version handles both single-line and multi-line match expressions.
"""

import argparse
from pathlib import Path


def find_match_blocks(content: str) -> list[tuple[int, int, str]]:
    """Find all match expressions and return (start_pos, end_pos, match_text)."""
    matches = []
    pos = 0

    while True:
        # Find next 'match' keyword
        match_pos = content.find('match ', pos)
        if match_pos == -1:
            break

        # Find the opening brace
        brace_start = content.find('{', match_pos)
        if brace_start == -1:
            pos = match_pos + 6
            continue

        # Find the matching closing brace
        brace_count = 1
        i = brace_start + 1
        while i < len(content) and brace_count > 0:
            if content[i] == '{':
                brace_count += 1
            elif content[i] == '}':
                brace_count -= 1
            i += 1

        if brace_count == 0:
            match_text = content[match_pos:i]
            matches.append((match_pos, i, match_text))
            pos = i
        else:
            pos = match_pos + 6

    return matches


def remove_comments(text: str) -> str:
    """Remove // line comments from text."""
    # Find // comment
    comment_pos = text.find('//')
    if comment_pos != -1:
        # Keep everything before the comment
        text = text[:comment_pos]
    return text.strip()


def is_trivial_match(match_text: str) -> bool:
    """Check if a match expression has one trivial branch (returns ())."""
    # Extract the body between braces
    brace_start = match_text.find('{')
    brace_end = match_text.rfind('}')
    if brace_start == -1 or brace_end == -1:
        return False

    body = match_text[brace_start + 1:brace_end]

    # Find all => at depth 0
    arrow_positions = []
    brace_depth = 0
    paren_depth = 0

    i = 0
    while i < len(body):
        char = body[i]
        if char == '(':
            paren_depth += 1
        elif char == ')':
            paren_depth -= 1
        elif char == '{':
            brace_depth += 1
        elif char == '}':
            brace_depth -= 1
        elif char == '=' and i + 1 < len(body) and body[i + 1] == '>' and brace_depth == 0 and paren_depth == 0:
            arrow_positions.append(i)
            i += 1  # Skip '>'
        i += 1

    # Need exactly 2 branches
    if len(arrow_positions) != 2:
        return False

    # Check each branch
    for idx, arrow_pos in enumerate(arrow_positions):
        # Find the body after =>
        body_start = arrow_pos + 2  # Skip '=>'

        # Find where this branch ends
        if idx == len(arrow_positions) - 1:
            # Last branch
            body_end = len(body)
        else:
            # Find where next pattern starts
            body_end = arrow_positions[idx + 1]
            # Walk backwards to find actual end
            j = body_end - 1
            brace_depth = 0
            while j > body_start:
                if body[j] == '}':
                    brace_depth += 1
                elif body[j] == '{':
                    brace_depth -= 1
                elif brace_depth == 0 and body[j] not in ' \n\t':
                    body_end = j + 1
                    break
                j -= 1

        # Extract and clean the branch body
        branch_body = body[body_start:body_end].strip()

        # Remove trailing comma/semicolon
        branch_body = branch_body.rstrip(',;').strip()

        # Remove comments before checking if trivial
        branch_body = remove_comments(branch_body)

        # Check if trivial
        if branch_body == '()' or branch_body == '':
            return True

    return False


def find_trivial_matches(content: str, filepath: Path) -> list[tuple[int, str]]:
    """Find all match expressions with trivial branches.

    Returns list of (line_number, matched_text) tuples.
    """
    matches = []
    match_blocks = find_match_blocks(content)

    for start_pos, end_pos, match_text in match_blocks:
        if is_trivial_match(match_text):
            # Calculate line number
            line_num = content[:start_pos].count('\n') + 1

            # Clean up for display
            display_text = ' '.join(match_text.split())
            if len(display_text) > 120:
                display_text = display_text[:117] + '...'

            matches.append((line_num, display_text))

    return matches


def scan_file(filepath: Path) -> list[tuple[int, str]]:
    """Scan a single .mbt file for trivial matches."""
    try:
        content = filepath.read_text(encoding='utf-8')
        return find_trivial_matches(content, filepath)
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan MoonBit files for trivial match expressions."
    )
    parser.add_argument(
        "--include-generated",
        action="store_true",
        help="Include generated/build directories (_build/target/.mooncakes).",
    )
    parser.add_argument(
        "--include-tests",
        action="store_true",
        help="Include *_test.mbt and *_wbtest.mbt files.",
    )
    parser.add_argument(
        "--dir",
        action="append",
        default=[],
        help="Restrict scan to a top-level directory (repeatable).",
    )
    return parser.parse_args()


def should_skip_file(
    filepath: Path,
    project_root: Path,
    include_generated: bool,
    include_tests: bool,
    allowed_dirs: list[str],
) -> bool:
    rel = filepath.relative_to(project_root).as_posix()
    parts = rel.split("/")
    top_level = parts[0] if parts else ""

    if allowed_dirs and top_level not in allowed_dirs:
        return True

    if not include_generated and top_level in {".mooncakes", "target", "_build", ".git"}:
        return True

    if not include_tests and (
        filepath.name.endswith("_test.mbt") or filepath.name.endswith("_wbtest.mbt")
    ):
        return True

    return False


def main() -> None:
    """Scan .mbt files in the project."""
    args = parse_args()
    project_root = Path(__file__).parent.parent
    mbt_files = sorted(project_root.rglob("*.mbt"))
    mbt_files = [
        f
        for f in mbt_files
        if not should_skip_file(
            f,
            project_root,
            include_generated=args.include_generated,
            include_tests=args.include_tests,
            allowed_dirs=args.dir,
        )
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
