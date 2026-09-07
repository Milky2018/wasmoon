# Wasmtime misc_testsuite

Complete snapshot of `tests/misc_testsuite` at Wasmtime commit
[`668016926adfd1b8a79dbce894f1e203d8892599`](https://github.com/bytecodealliance/wasmtime/tree/668016926adfd1b8a79dbce894f1e203d8892599/tests/misc_testsuite),
the same revision as the local P1 corpus. All 382 WAST scripts and four WAT
auxiliary inputs are retained byte-for-byte. Nine license/host-reference files
bring the hashed inventory to 395 files. The four WAT inputs are retained but
are not standalone WAST trials, matching upstream test discovery.

## Running

From the repository root, using Python 3.11+ and a freshly built Wasmoon:

```sh
./install.sh
# Required when running the component lane:
cargo install wasm-tools --version 1.254.0 --locked
python3 scripts/run_wasmtime_misc.py --check
python3 scripts/run_wasmtime_misc.py --list
python3 scripts/run_wasmtime_misc.py
python3 scripts/run_wasmtime_misc.py --lane core --mode jit
python3 scripts/run_wasmtime_misc.py --filter 'gc/*' --mode interp
python3 scripts/run_wasmtime_misc.py --filter add.wast --filter div-rem.wast
python3 scripts/run_wasmtime_misc.py --output tmp/misc-results --timeout 60
```

The default selects every WAST script and both execution modes. Filters match
suite-relative paths and can be repeated. A full scan currently exits nonzero;
see the initial results below. The runner does not download or rewrite tests.

Each file/mode gets its own subprocess, logs and fresh JIT cache. A 30-second
file timeout kills the worker process group. Component tools remain in the
worker's process group so they cannot outlive its timeout. Partial reports are
saved after every trial. Output directories must be new or empty.

Reports include upstream and snapshot identity, source hashes, host-contract
manifest hash, engine hash/version, tool versions, original `;;!` configuration,
commands, exit codes, counts, logs and available JIT compilation traces.

## Execution contracts

Core scripts execute unchanged through `wasmoon test`, with `--no-jit` in the
interpreter lane. The runner enables `WASMOON_WAST_REGISTER_NAMED_MODULES=1`
to reproduce Wasmtime's automatic registration of named modules for imports.
Ordinary WAST execution keeps explicit `register` semantics by default. Reports
record this compatibility setting. Bare `invoke` commands must complete without
trapping, and indexed `ref.func` expectations compare function identity.

Component scripts use the existing `run_component_wast.py`
adapter, including its WAST-to-JSON conversion, validation and runtime harness;
they require `wasmoon-tools` and exactly wasm-tools 1.254.0. Component results
therefore measure that adapter's coverage as well as Wasmoon's runtime.

Leading `;;!` TOML configuration is parsed with upstream's leading-lines rule
and retained in each trial. Wasmoon runs its available proposal set; this does
not reproduce Wasmtime's compiler, GC collector, pooling allocator or feature
configuration matrix. Explicit missing host contracts are listed per file in
[HOST_CONTRACTS.json](HOST_CONTRACTS.json):

- Wasmtime-only forced-GC and resource-table-capacity host imports are not
  replaced with no-op functions.
- Engine-wide NaN canonicalization and tests requiring disabled proposals
  cannot be expressed by the Wasmoon WAST CLI.
- Upstream `hogs_memory` tests are separately `deferred` by default. Use
  `--include-high-memory` on a suitable host to execute them. This is a resource
  policy, not a declaration that those tests pass or are unsupported.

Other parse, validation, instantiation, assertion and adapter failures remain
failures, including unsupported syntax encountered during execution. The host
contract manifest is not an expected-failure list; do not add failing filenames
without identifying an actual missing host contract.

Verdicts are explicit:

| Status | Meaning |
| --- | --- |
| `pass` | Successful exit, positive passing tally, no failed or skipped checks |
| `script_only` | Successful core module/register/invoke script with no assertion commands; counted separately |
| `fail` | Guest, parser, adapter, status/tally mismatch, skipped checks or missing result |
| `timeout` | Trial exceeded its wall-clock limit |
| `unsupported` | Explicit missing host configuration/import contract |
| `deferred` | High-memory trial not opted into |
| `harness_error` | Launcher/setup failure |

An empty or excluded-only selection never passes. Exit codes are 0 for successful
executed trials, 1 for failures/timeouts or no successful executions, and 2 for
harness errors. Command tallies are not file counts and may include checks from
partially failing files. `script_only` does not add any passing assertions.

## Initial results

The [historical result inventory](INITIAL_RESULTS.json) records macOS ARM64,
Wasmoon runtime `ebd11ae2`, wasm-tools 1.254.0 and the exact engine/source hashes.
The runner never reads this baseline or accepts its failures as expected.

| Mode | Files with passing checks | Script-only completed | Failed | Unsupported | Deferred | Timeout |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Interpreter | 181 | 27 | 130 | 36 | 8 | 0 |
| JIT | 181 | 27 | 130 | 36 | 8 | 0 |

Each mode runs 284 core and 98 component scripts. The core lane has 127 passing
scripts with passing checks, 27 script-only completions and 92 failures; the
component lane has 54 passes and 38 failures. Equal aggregate counts do not mean
identical failures: for example, `call_indirect.wast` passes in the interpreter
but fails JIT indirect-call type checks. These results identify gaps in both the
runtime and test adapters; they are not a claim of complete Wasm conformance or
an execution of Wasmtime's own compiler matrix. Linux has not been run locally.

The regular platform workflow checks the source inventory and runs six explicit
smoke scripts in both modes, covering arithmetic, function references, GC array
copy, a script-only element operation and component aliases. The separate
`Wasmtime misc testsuite` workflow runs the full selection on Linux and macOS
and uploads reports even when tests fail. Neither workflow masks failures.

## Updating

Copy the entire upstream directory and the nine reference/license files listed
in `SNAPSHOT.json` from one exact commit. Refresh the complete file inventory and
SHA-256 hashes, re-audit `;;!` options and `HOST_CONTRACTS.json`, then run the
snapshot tests and both execution lanes. Keep old observations explicitly
historical. Do not modify tests or hashes to make an assertion pass.

License: [Apache-2.0 WITH LLVM-exception](upstream/LICENSE).
