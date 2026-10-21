# Owned regression inputs

This directory contains Wasmoon's own regression inputs. Module-local MoonBit
tests remain with their owning packages. Imported test corpora live under
[`upstream/`](upstream/README.md), with their existing manifests, licenses and
runners.

| Directory | Contents | Runner |
| --- | --- | --- |
| `core/` | Core execution WAST regressions and standalone arithmetic fixtures | `python3 scripts/run_all_wast.py --dir tests/core --rec` |
| `component/` | Component runtime WAST regressions | `python3 scripts/run_component_wast.py --dir tests/component --dump-failures` and the same command with `--no-jit` |
| `wasi/p1/` | Preview 1 WAST regressions, CLI smoke suite and auxiliary fixtures | See [`wasi/p1/README.md`](wasi/p1/README.md) |
| `wasi/http/` | HTTP service, middleware and mixed-command guest inputs | `python3 scripts/test_wasi_http.py --wasmoon ./wasmoon` |
| `wasi/p3/http-contract/` | Explicit corrections to two pinned upstream Preview 3 guests | See [the profile and rebuild instructions](wasi/p3/http-contract/README.md) |

Run these commands from the repository root with current Wasmoon binaries.
The Core runner executes both interpreter and JIT modes. Component execution
requires the pinned wasm-tools 1.254.0.

The former `tests/runtime/` and top-level `myspec/*.wast` inputs are now in
`core/`; `tests/component-runtime/` is now `component/`. The former
`myspec/wasip1/` and `examples/wasi_tests/` inputs are now in `wasi/p1/`.
`tests/http/` and `tests/wasi03/` are now `wasi/http/` and `wasi/p3/`.
Historical evidence retains the original paths and source revisions.
