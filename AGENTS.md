# Repository Guidelines

## Project Structure & Module Organization

Wasmoon is a WebAssembly runtime written in MoonBit. Module metadata lives in `moon.mod.json`; each package directory has a `moon.pkg.json`.

- Pipeline: parsers (`wat/`, `wast/`, `parser/`) → `validator/` → `runtime/` → `executor/` or JIT (`milkir` → semantic `machv` → target VCode → `machv_regalloc` → target emitter → v9 artifact installer).
- CLI entry point: `cmd/wasmoon/` (builds the `wasmoon` binary).
- WASI Preview 1 support: `wasi/`.
- Tests: `testsuite/` (MoonBit tests) and `spec/` (upstream WAST scripts used by the CLI runner).
- Build artifacts: `target/`; `install.sh` creates/updates symlinks in repo root (`./wasmoon`, `./wasmoon-tools`) that point at the built executables.

## Development Commands

- `moon check` - Lint and type-check (runs in pre-commit hook)
- `moon test` - Run all tests
- `moon test -p <package> -f <file>` - Run specific tests
- `moon fmt` - Format code
- `moon info` - Update `.mbti` interface files
- `moon info && moon fmt` - Standard workflow before committing

## Building and Running

```bash
./install.sh    # Build and (re)link wasmoon binaries into repo root
./wasmoon test <file.wast>    # Run WAST tests
./wasmoon test --no-jit <file.wast>  # Run in interpreter-only mode
./wasmoon explore <file.wat> --stage milkir machv vcode allocated-vcode code-object mc  # View compilation stages
python3 scripts/run_all_wast.py --rec  # Run all WAST tests (ensure ./wasmoon exists; run ./install.sh once)
python3 scripts/run_component_wast.py --suite stable-0.2  # Stable Component Model 0.2
python3 scripts/run_component_wast.py --suite async-0.3   # Component Model 0.3 async
python3 scripts/run_component_wast.py --suite future-gated  # Later gated features
```

## Testing

- Prefer `inspect` for tests; run `moon test --update` to update snapshots
- Never batch use `--update`. Treat snapshot errors seriously
- Don't use `println` in tests. Use `inspect(expr)` and update snapshots, then read the file
- Use `compare_jit_interp(wat_string)` in `testsuite/` for JIT regression tests
- Component-model runner requires pinned `wasm-tools` 1.254.0 on `PATH` (used to compile `.wast` `(component ...)` forms):
  `cargo install wasm-tools --version 1.254.0 --locked`

## Debugging

For crashes (e.g., Exit Code 134), use lldb:
```bash
lldb -- ./wasmoon test path/to/test.wast
(lldb) run
(lldb) bt  # stack trace after crash
```

## Project Structure

- Each directory is a MoonBit package with `moon.pkg.json`
- Test files: `*_test.mbt` (blackbox), `*_wbtest.mbt` (whitebox)
- `.mbti` files - Generated interfaces (check diffs to verify API changes)
- Code organized in **block style** separated by `///|`

## Compiler Infrastructure Boundaries

Reusable compiler-infrastructure modules include `wasm_core`, `milkir`, `machv`, `regalloc`, `machv_regalloc`, `milkir_machv`, `wasm_machv`, `aarch64_target`, and `x64_target`.

- Hard boundary: reusable modules must not import Wasmoon-owned packages such as `Milky2018/wasmoon`, `Milky2018/wasmoon_jit`, or Wasmoon native FFI packages. `scripts/audit_module_boundaries.py` enforces this at `moon.pkg` import level.
- Soft convention: avoid product-specific runtime names such as `wasmoon_jit_*`, `c_jit_*`, and `wasmoon.runtime.*` in reusable module code, comments, tests, and public APIs. Prefer generic terms such as external symbol, runtime helper, `wasm.runtime.*`, or embedding runtime.
- Native runtime address resolution belongs in `wasmoon_jit` or another explicitly Wasmoon-owned package. Generic emitters should produce machine code plus symbolic relocation/fixup metadata.
- If a product-specific name is temporarily necessary in reusable infrastructure, document why in the local code and track the cleanup in an issue instead of broadening the boundary audit with ad-hoc string checks.

## Git Branch Model

- `dev` is the long-lived development branch and the only branch for ordinary
  implementation work. `main` is the stable/release branch.
- **Make all ordinary changes directly on `dev`.** Do not create topic or
  per-task branches unless the user explicitly requests an exception.
- Start every task from the current remote `dev`:
  ```bash
  git fetch origin --prune
  git switch dev
  git pull --rebase origin dev
  ```
- Commit and push development work directly to `dev`. **NEVER commit or push
  directly to `main`.**
- Periodically open a `dev` to `main` PR after a coherent batch of development
  work has passed the complete required check set. PRs are integration points
  for promoting `dev`; they are not required for each development commit.
- After a `dev` to `main` PR is merged, continue working on the same long-lived
  `dev` branch. Do not delete, recreate, or replace it.
- A successful push to `dev` proves delivery to the development branch only.
  Never claim that a commit is in `main` without verifying that it is an
  ancestor of `origin/main`.
- Write commit messages and PR text in English.
- Don't use `commit --amend` or `push --force`; add a new commit instead.

## MoonBit Notes

- Use `suberror` for error types, `raise` to throw, `try! func() |> ignore` to ignore errors
- Use `func() |> ignore` not `let _ = func()`
- When using `inspect(value, content=expected_string)`, don't declare a separate `let expected = ...` variable - it causes unused variable warnings. Put the expected string directly in the `content=` parameter
- Use `!condition` not `not(condition)`
- Use `f(value)` not `f!(value)` (deprecated)
- Use `for i in 0..<n` not C-style `for i = 0; i < n; i = i + 1`
- Use `if opt is Pattern(v) { ... }` for single-branch matching, not `match opt {}`
- Use `arr.clear()` not `while arr.length() > 0 { arr.pop() }`
- Use `s.code_unit_at(i)` or `for c in s` not `s[i]` (deprecated)
- Struct/enum visibility: `priv` (hidden) < (none)/abstract (type only) < `pub` (readonly) < `pub(all)` (full)
- Default to abstract (no modifier) for internal types; use `pub struct` when external code reads fields
- Use `pub(all) enum` for enums that external code pattern-matches on
- Use `let mut` only for reassignment, not for mutable containers like Array
- Use `reinterpret_as_uint()` for unsigned ops, `to_int()` for numeric conversion
- Use `Array::length()` not `Array::size()`
- In moon.pkg.json, use "import", "test-import" and "wbtest-import" to manage package importing for ".mbt", "_test.mbt" and "_wbtest.mbt"
- Use `Option::unwrap_or` not `Option::or`

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **SYNC AND PUSH `dev`** - This is mandatory. Rebase local development work
   onto the latest remote `dev`, resolve any conflict, and push:
   ```bash
   git switch dev
   git pull --rebase origin dev
   git push origin dev
   ```
5. **Clean up** - Clear stashes and prune obsolete remote branches.
6. **Verify** - The working tree is clean and local `dev` exactly matches
   `origin/dev`:
   ```bash
   test "$(git branch --show-current)" = dev
   test "$(git rev-parse HEAD)" = "$(git rev-parse origin/dev)"
   git status --short --branch
   ```
7. **Promote periodically** - When requested or when a coherent release batch
   is ready, open a `dev` to `main` PR and wait for the complete check set
   before merging.
8. **Hand off** - Report the commit, checks, and whether it is only in `dev` or
   has also been promoted to `main`.

**CRITICAL RULES:**
- Work is NOT complete until `git push origin dev` succeeds and local `dev`
  matches `origin/dev`.
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
- NEVER do ordinary implementation work on `main`
- NEVER create a topic branch unless the user explicitly requests one
- NEVER claim a development commit is in `main` without an ancestry check
