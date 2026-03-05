#!/usr/bin/env python3
"""Delta-reduce a failing .wast/.wat/.wasm reproducer."""

from __future__ import annotations

import argparse
import math
import shlex
import subprocess
import tempfile
from pathlib import Path


def run_command(command_template: str, file_path: Path, timeout: int) -> bool:
    command = shlex.split(command_template.format(file=str(file_path)))
    completed = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if completed.returncode != 0:
        return True
    output = completed.stdout + completed.stderr
    for line in output.splitlines():
        stripped = line.strip()
        if not stripped.startswith("Failed:"):
            continue
        try:
            return int(stripped.split(":", maxsplit=1)[1].strip()) > 0
        except Exception:
            continue
    return False


def ddmin_lines(
    initial_lines: list[str],
    command_template: str,
    suffix: str,
    timeout: int,
) -> list[str]:
    lines = initial_lines[:]
    granularity = 2

    with tempfile.TemporaryDirectory(prefix="wasmoon-reduce-") as temp_dir:
        temp_path = Path(temp_dir) / f"candidate{suffix}"

        while len(lines) >= 2:
            chunk_size = math.ceil(len(lines) / granularity)
            reduced = False

            for start in range(0, len(lines), chunk_size):
                end = min(len(lines), start + chunk_size)
                candidate = lines[:start] + lines[end:]
                if not candidate:
                    continue
                temp_path.write_text("".join(candidate), encoding="utf-8")
                if run_command(command_template, temp_path, timeout):
                    lines = candidate
                    granularity = max(2, granularity - 1)
                    reduced = True
                    break

            if not reduced:
                if granularity >= len(lines):
                    break
                granularity = min(len(lines), granularity * 2)

    return lines


def main() -> None:
    parser = argparse.ArgumentParser(description="Delta reduce failing wasm/wast inputs")
    parser.add_argument("input", help="Input failing file")
    parser.add_argument(
        "--cmd",
        default="./wasmoon test {file}",
        help="Failure predicate command template, must include {file}",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Output reduced file path (default: <input>.reduced<ext>)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=20,
        help="Timeout per predicate command (seconds)",
    )
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    if not input_path.exists():
        raise SystemExit(f"Input file not found: {input_path}")
    if "{file}" not in args.cmd:
        raise SystemExit("Command template must include {file}")

    if not run_command(args.cmd, input_path, args.timeout):
        raise SystemExit("Input does not fail with the given command; refusing to reduce.")

    source_lines = input_path.read_text(encoding="utf-8").splitlines(keepends=True)
    reduced_lines = ddmin_lines(source_lines, args.cmd, input_path.suffix, args.timeout)

    if args.output:
        output_path = Path(args.output).resolve()
    else:
        output_path = input_path.with_name(
            f"{input_path.stem}.reduced{input_path.suffix}"
        )
    output_path.write_text("".join(reduced_lines), encoding="utf-8")

    print(f"Input lines:   {len(source_lines)}")
    print(f"Reduced lines: {len(reduced_lines)}")
    print(f"Output:        {output_path}")


if __name__ == "__main__":
    main()
