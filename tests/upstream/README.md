# Upstream test corpora

Imported corpora are grouped by source. Wasmoon's own regressions live in
`tests/core`, `tests/component` and `tests/wasi`.

| Directory | Former location | Entry point from the repository root |
| --- | --- | --- |
| `core-spec/` | `spec/` | `python3 scripts/run_all_wast.py --rec` |
| `component-model/` | `component-spec/` | `python3 scripts/check_component_snapshot.py`, then `python3 scripts/run_component_wast.py --suite stable-0.2` (also `async-0.3` and `future-gated`) |
| `wasmtime/misc/` | `wasm-tests/wasmtime/` | `python3 scripts/run_wasmtime_misc.py --check`, then the same command without `--check` |
| `wasmtime/wasi-p1/` | `wasi-tests/wasmtime/` | `python3 scripts/run_wasmtime_p1.py --check`, then select the documented execution profile |

Each bundle retains its internal directory structure, licenses, source pins and
hash manifests. The Wasmtime bundles have independent snapshots and host
contracts. The Component Model bundle keeps imported `upstream/` files separate
from local `corrections/` and suite classifications in `suites/`. Relocating a
bundle does not change its test selection, assertions or execution profile.

Use each bundle's README and upstream notes for synchronization and execution
requirements. Component execution requires wasm-tools 1.254.0. The portable
Core runner, `scripts/run_portable_core_wast.py`, defaults to `core-spec/` for
both native and actual wasm execution.

Historical issue notes and evidence retain their original commands, file paths
and source revisions; the table above maps those paths to their current
locations. The external WASI Preview 3 checkout remains a caller-supplied input
to `scripts/run_wasi03.py`; its local HTTP contract profile is kept under
`tests/wasi/p3/http-contract/`.
