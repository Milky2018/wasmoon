# Repository Guidelines

## Project Structure & Module Organization

Wasmoon is a WebAssembly runtime written in MoonBit. Module metadata lives in `moon.mod.json`; each package directory has a `moon.pkg.json`.

- Pipeline: parsers (`wat/`, `wast/`, `cwasm/`, `parser/`) → `validator/` → `runtime/` → `executor/` or JIT (`ir/` → `vcode/` → `jit/`).
- CLI entry point: `main/` (builds the `wasmoon` binary).
- WASI Preview 1 support: `wasi/`.
- Tests: `testsuite/` (MoonBit tests) and `spec/` (upstream WAST scripts used by the CLI runner).
- Build artifacts: `target/`; `install.sh` copies the built executable to `./wasmoon`.

## Build, Test, and Development Commands

- `moon update`: fetch/update MoonBit dependencies.
- `moon check --target native`: type-check + lint (CI runs this).
- `moon test --target native`: run MoonBit tests.
- `moon test --update`: update snapshots after intentional behavior changes.
- `moon info && moon fmt`: update `.mbti` interfaces and format code (CI expects a clean diff).
- `moon build --target native --release && ./install.sh`: build and install the CLI locally.
- CLI usage: `./wasmoon test spec/i32.wast` (add `--no-jit` to force the interpreter).

## Coding Style & Naming Conventions

- Use MoonBit “block style”: separate top-level blocks with `///|`.
- Naming: functions `snake_case`, types/constructors `PascalCase`, constants `SCREAMING_SNAKE_CASE`.
- Prefer `expr |> ignore` over `let _ = expr`; use `suberror`/`raise`/`try` patterns for errors.
- Keep deprecated APIs in `deprecated.mbt` within the relevant package.

## Testing Guidelines

- Test naming: blackbox `*_test.mbt`, whitebox `*_wbtest.mbt`.
- Prefer snapshot assertions via `inspect(...)` (avoid `println`); use `assert_eq` for loops/parameterized cases.
- JIT regressions: prefer `compare_jit_interp(wat_string)` in `testsuite/`.
- WAST regression: `./wasmoon test spec/<name>.wast` or `python3 scripts/run_all_wast.py`.

## Commit & Pull Request Guidelines

- Use Conventional Commits: `feat(scope): ...`, `fix: ...`, `refactor: ...`, `docs: ...`, `test: ...`, `chore: ...`, `style: ...`.
- PRs should include rationale, linked issues, exact test commands + target, and note any snapshot updates.

## Security Note

This project is AI-assisted and not thoroughly audited; avoid production/security-sensitive use.
