# Repository Guidelines

## Project Structure & Module Organization

Wasmoon is a WebAssembly runtime written in MoonBit. Module metadata lives in `moon.mod.json`; each package directory has a `moon.pkg.json`.

- Pipeline: parsers (`wat/`, `wast/`, `cwasm/`, `parser/`) → `validator/` → `runtime/` → `executor/` or JIT (`ir/` → `vcode/` → `jit/`).
- CLI entry point: `main/` (builds the `wasmoon` binary).
- WASI Preview 1 support: `wasi/`.
- Tests: `testsuite/` (MoonBit tests) and `spec/` (upstream WAST scripts used by the CLI runner).
- Build artifacts: `target/`; `install.sh` copies the built executable to `./wasmoon`.

## Development Commands

- `moon check` - Lint and type-check (runs in pre-commit hook)
- `moon test` - Run all tests
- `moon test -p <package> -f <file>` - Run specific tests
- `moon fmt` - Format code
- `moon info` - Update `.mbti` interface files
- `moon info && moon fmt` - Standard workflow before committing

## Building and Running

```bash
moon build && ./install.sh    # Build and install wasmoon binary
./wasmoon test <file.wast>    # Run WAST tests
./wasmoon test --no-jit <file.wast>  # Run in interpreter-only mode
./wasmoon explore <file.wat> --stage ir vcode mc  # View compilation stages
python3 scripts/run_all_wast.py --rec  # Run all WAST tests (run ./install.sh first)
python3 scripts/run_component_wast.py --dir component-spec/values --rec  # Component model (subset)
python3 scripts/run_component_wast.py --dir component-spec/names --rec   # Component model (subset)
```

## Testing

- Prefer `inspect` for tests; run `moon test --update` to update snapshots
- Never batch use `--update`. Treat snapshot errors seriously
- Don't use `println` in tests. Use `inspect(expr)` and update snapshots, then read the file
- Use `compare_jit_interp(wat_string)` in `testsuite/` for JIT regression tests
- Component-model runner requires `wasm-tools` on `PATH` (used to compile `.wast` `(component ...)` forms)

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

## Git Conventions

- **NEVER commit or push directly to main branch** - always create a feature branch and merge via PR
- Write commit messages in English
- Create a new branch for each change, merge via PR
- Don't use `commit --amend` or `push --force`, use new commits instead

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
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

Use 'bd' for task tracking
