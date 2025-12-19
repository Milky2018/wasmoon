# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

A MoonBit implementation of a WebAssembly runtime with JIT compilation (wasmoon).

## Development Commands

- `moon check` - Lint and type-check (runs in pre-commit hook)
- `moon test` - Run all tests
- `moon fmt` - Format code
- `moon info` - Update `.mbti` interface files
- `moon info && moon fmt` - Standard workflow before committing

## Project Structure

- Each directory is a MoonBit package with `moon.pkg.json`
- Test files: `*_test.mbt` (blackbox), `*_wbtest.mbt` (whitebox)
- `.mbti` files - Generated interfaces (check diffs to verify API changes)
- Code organized in **block style** separated by `///|`

## Testing

- Prefer `inspect` for tests, use `moon test --update` to update snapshots
- `moon test -p <package> -f <file>` runs specific tests
- Never batch use `--update`. Treat snapshot errors seriously
- Don't use `println` in tests. Use `inspect(expr)` and update snapshots, then read the file

## Building and Running

- After `moon build`, run `./install.sh` to use the `./wasmoon` binary
- `./wasmoon test <wast_file>` - Run WAST tests
- `./wasmoon explore <wat_file> --stage vcode mc` - View compilation output
- Run all WAST tests: `python3 scripts/run_all_wast.py`

## Debugging

For crashes (e.g., Exit Code 134), use lldb:
```bash
lldb -- ./wasmoon test path/to/test.wast
(lldb) run
(lldb) bt  # stack trace after crash
```

## Git Conventions

- Write commit messages in English
- Create a new branch for each change, merge via PR
- Don't use `commit --amend` or `push --force`, use new commits instead

## MoonBit Notes

- Use `suberror` for error types, `raise` to throw, `try! func() |> ignore` to ignore errors
- Use `func() |> ignore` not `let _ = func()`
- Use `s.code_unit_at(i)` not `s[i]` (deprecated)
