# GC type registration: local diagnosis and validation

Issue: [GitHub #548](https://github.com/Milky2018/wasmoon/issues/548).
Baseline: `7854228a50434f587992e17e1a9f40bb363a99a3`.
These results describe an **uncommitted working tree on macOS ARM64**, not CI.
[local.json](local.json) records source and binary SHA-256 identities, toolchain,
all measured cases, and validation results. Raw logs remain in ignored
`target/issue548/` and `target/sanitizers/`.

## Cause and change

Before a ModuleInstance exists, each GC allocation registered the complete
module type graph again. The negative instance index did not have a cached
mapping. Each registration also rebuilt recursive-group indices in a new
TypeEquivalenceContext for every representative comparison. Native sampling
placed repeated context/index construction on the hot allocation path.

The Store now retains a registered graph for its current `set_module_types`
scope. Replacing the scope invalidates the cache, rollback restores its prior
graph, and terminal close releases it without allowing rollback to resurrect
it. Published instances can reuse that graph when their snapshots agree.
Within one registration, comparisons against the same graph share a temporary
equivalence context. Full recursive-group equivalence still determines matches;
canonical identities remain Store-local. No public API changed.

## Serial performance measurements

Release builds were compiled separately. Timed runs were serial, after this
task's build/test workers exited. Compilation is excluded. Synthetic cases use
a fresh Store; parsing and explicit validation are timed separately. The raw
instantiation API performs its own validation again. The clock has millisecond
resolution, so the candidate results do not support precise speedup ratios.

| Input and measured operation | Baseline, ms | Candidate, ms |
| --- | --- | --- |
| 100 types / 100 GC globals, raw instantiation | 4916, 4829 | 2, 2 |
| Same input, prevalidated instantiation | 4900, 5114 | 1, 1 |
| Real cmp module, prevalidated unstarted instantiation | 2135, 2104, 2074 | 7, 7, 7 |

The real input is `cmp.blackbox_test.wasm` from moonbitlang/core checkout
`7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1`, with 233 decoded types and
19 globals. Its hash is recorded in local.json. Function imports are trap
stubs, and **the module start and tests are not executed**. This measurement
does not claim to reproduce or resolve the issue's entire 89-second embedding
workload.

### Replaying the harnesses

[benchmark.mbt](benchmark.mbt) and
[real-module-benchmark.mbt](real-module-benchmark.mbt) are exact copies of the
measured harness sources. Place either in an ignored scratch executable project
as `main.mbt`. For the synthetic project, use this `moon.mod`:

```toml
name = "repro/wasmoon548"
preferred_target = "native"
import {
  "Milky2018/wasmoon_runtime@0.17.0",
  "Milky2018/wasm_core@0.17.0",
  "moonbitlang/async@0.22.4",
}
```

Use this `moon.pkg`:

```moonbit
import {
  "Milky2018/wasmoon_runtime/runtime",
  "Milky2018/wasmoon_runtime/executor",
  "Milky2018/wasm_core/wat",
  "Milky2018/wasm_core/validator",
  "moonbitlang/async",
}
pkgtype(kind: "executable")
```

Create `moon.work` with `members` containing `"."` and absolute paths to all
module members listed in the selected Wasmoon checkout's root `moon.work`.
This ensures the harness uses that checkout rather than published packages.
Run `moon build --target native --release`, then execute the resulting binary
directly. Use distinct build directories for baseline and candidate, and run
their binaries serially. Retain every trial, including outliers.

For the real harness, replace the `wat` package import with
`Milky2018/wasm_core/parser`, add `moonbitlang/x@0.5.5` to moon.mod and
`moonbitlang/x/fs` to moon.pkg, and adjust the absolute input path in the source.
Verify the input hash before comparing measurements. That harness performs one
trial per process; the recorded comparison uses three processes per revision.

## Regression and validation results

The mapping-reuse regression failed before the optimization on both native and
wasm. A close-during-rollback control also failed before the terminal-close
guard. Public API tests cover repeated struct/array initialization, recursive
groups with shifted indices, different group boundaries, Store isolation,
mapping snapshot mutation, prepublication failure and budget recovery, nested
instantiation, CHeap identities, and JIT/interpreter subtype layouts.

The GC-global parity test exposed a separate existing comparison-helper bug:
it instantiated globals in one heap and ran JIT code with a new empty CHeap.
The fixture failed on unchanged main as well as the candidate. The helper now
uses the same Store-owned CHeap throughout; the expected value remains 43 and
JIT/interpreter parity passes.

Final local gates:

- `moon info`, `moon fmt`, strict native and wasm checks with warning 73 denied,
  and the module boundary audit passed.
- Native: **2808/2808**; wasm: **1333/1333**.
- Core: native interpreter, actual wasm interpreter, and JIT each passed
  **258 files / 62563 assertions**, with no failures or unsupported results.
- Component: each native engine passed **59 files / 1385 commands**, no skips.
- Complete pinned Wasmtime misc: **692 passed / 72 script-only**, no failures,
  timeouts, unsupported, deferred, or harness errors.
- Python: **173 tests**, with 54 existing platform skips.
- Fresh macOS ASan/UBSan: **200/200**, lifecycle checks and both ASan positive
  controls passed. No ordinary sanitizer error was reported. **Local leak
  detection is unavailable (`leak_detection=false`); this is not Linux LSan
  acceptance.** MoonBit runtime objects and JIT machine code remain outside the
  sanitizer instrumentation scope.

Supported-platform CI remains pending. ISS-644 stays in progress until that
acceptance is complete.

## PR review follow-up

The later [fingerprint-bucket follow-up](fingerprints.md) addresses first-time
registration and canonicalization costs for large type sections. Its separate
receipt preserves the provenance and results above as historical evidence.
