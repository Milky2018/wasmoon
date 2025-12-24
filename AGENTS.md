# Repository Guidelines

## Project Structure & Module Organization

Wasmoon is a WebAssembly runtime written in MoonBit. Module metadata lives in `moon.mod.json`; each package directory has a `moon.pkg.json`.

High-level pipeline: parsers (`wat/`, `wast/`, `cwasm/`) → `validator/` → `runtime/` → `executor/` or JIT (`ir/` → `vcode/` → `jit/`).

Key packages:
- `main/`: CLI entry point (builds the `wasmoon` binary)
- `wat/`, `wast/`, `cwasm/`, `parser/`: text/binary parsing
- `validator/`: module validation
- `runtime/`, `executor/`: runtime + interpreter
- `ir/`, `vcode/`, `jit/`: JIT pipeline (AArch64)
- `wasi/`: WASI Preview 1
- `testsuite/`: MoonBit tests
- `spec/`: upstream WAST scripts used by the CLI test runner

Build artifacts live under `target/`. `install.sh` copies the built executable to `./wasmoon`.

## Build, Test, and Development Commands

- `moon update`: fetch/update MoonBit dependencies.
- `moon check --target native`: type-check + lint (CI runs this).
- `moon test --target native`: run MoonBit tests.
- `moon test --update`: update snapshots when behavior changes.
- `moon info && moon fmt`: update `.mbti` interfaces and format code (CI requires a clean diff; review `.mbti` diffs for API changes).
- `moon build --target native --release && ./install.sh`: build and install the CLI locally.

CLI example: `./wasmoon test spec/i32.wast` (add `--no-jit` to force interpreter)

## Coding Style & Naming Conventions

- Use MoonBit “block style”: separate top-level blocks with `///|`.
- Naming: functions `snake_case`, types/constructors `PascalCase`, constants `SCREAMING_SNAKE_CASE`.
- Prefer `expr |> ignore` over `let _ = expr`; use `suberror`/`raise`/`try` patterns for errors.
- Keep deprecated APIs in `deprecated.mbt` within the relevant package directory.
- Format with `moon fmt` before pushing.

## Testing Guidelines

- Test files: blackbox `*_test.mbt`, whitebox `*_wbtest.mbt`.
- Prefer snapshot-style assertions via `inspect(...)` (avoid `println`); only use `assert_eq` in loops/parameterized cases.
- For JIT regressions in `testsuite/`, prefer `compare_jit_interp(wat_string)`.
- WAST regression: run a file with `./wasmoon test spec/<name>.wast` or all via `python3 scripts/run_all_wast.py`.

## Commit & Pull Request Guidelines

- Use Conventional Commits as seen in history: `feat(scope): ...`, `fix: ...`, `refactor: ...`, `docs: ...`, `test: ...`, `chore: ...`, `style: ...`.
- Write commit messages in English; avoid `git commit --amend` and `git push --force` (use follow-up commits).
- PRs should include: a short rationale, linked issues, how you tested (commands + target), and note any snapshot updates.
- Optional: enable hooks with `git config core.hooksPath .githooks`.

## Security Note

This project is AI-assisted and not thoroughly audited; avoid production/security-sensitive use.
