# ISS-626 Core boundary verification, 2026-10-15

This is local macOS ARM64 evidence for the uncommitted implementation based on
`afd1daf99abd54c1d52088f8c518d8128dc4827e`, on
`milky/protect-core-runtime-boundaries`. It is not exact-commit CI acceptance.
[local.json](local.json) records the toolchain, fresh CLI hashes, corpus pins,
profiles, exclusions, results, and pending platform checks.
[source-manifest.json](source-manifest.json) hashes changed/new module files
relative to that base, including generated interfaces and the embedding example.

## Defects and negative controls

[baseline-two-failures.log](baseline-two-failures.log) captures two independent
public API defects before the implementation: calling an instance with a
second Store silently used the second Store's function at the same address;
mutating the source instruction array changed an existing instance's behavior.
These are embedding API defects, not evidence of a CLI validation bypass.

Further regressions were reproduced during the change:

- [raw-graph-before.log](raw-graph-before.log): a raw self-supertype model passed
  validation. The [same self-supertype](invalid-self-supertype.wat) is rejected
  by wasm-tools 1.254.0 ([control](wasm-tools-self-supertype.log)). The final
  tests also cover forward/multiple parents, malformed recursive groups,
  passive-data sentinels, wrong-kind type references, negative unsigned indices
  and malformed SIMD immediates through both validator entry points.
- [reentrant-start-before.log](reentrant-start-before.log): a host global-read
  callback changed the original module's start index during initialization.
  Sync and async instantiation now execute the accepted snapshot's start index.
- [host-handle-before.log](host-handle-before.log): rolling back a host export
  left its namespace instance valid; a retained function handle then called a
  replacement at the reused address. Handles now check an independent allocation
  lifetime token stored with the function entry.
- [cleanup-development-control.log](cleanup-development-control.log): an
  implementation control caught a leaked owned cleanup closure despite successful
  logical GC root release. This was an intermediate defect in the new code,
  not a finding against the base revision. The generated FuncRef adapter borrows
  the callback; C must decref its owned closure after invoking it. The final
  regression observes an independent captured external object's finalizer,
  for both early close and automatic RC cleanup. It runs in the sanitizer suite.

The [negative compiler fixture](static-probe.mbt.txt) was temporarily checked
from an external package and then removed from compilable sources.
[Diagnostics](static-diagnostics.json) confirm that external clients cannot
access Store function storage or validation backing storage, assign instance
address maps, or modify an immutable instruction array. This is an actual
compiler check, not source-text matching or a new style-audit script.

## Final validation

| Gate | Result |
| --- | --- |
| `moon info`, `moon fmt` | Completed; generated interfaces refreshed. |
| `moon check --target native --warn-list +73 --deny-warn` | [Passed](check.log). |
| `moon test --target native` | [2689/2689](native-tests.log), including the executable embedding example. |
| `python3 scripts/check_native_c.py` | [42 stubs](native-c.log), warnings denied. |
| `python3 scripts/audit_module_boundaries.py` | [Passed](module-boundaries.log). |
| `python3 scripts/run_sanitizers.py` | [143/143](sanitizer-tests.log), plus event-loop and ASan/native-ASan positive controls. |
| `./install.sh` | Clean release build of both CLIs; hashes in local.json. |
| Core `run_all_wast.py --rec --dump-failures` | [258/258 files per engine](core-wast.log). |
| Component stable-0.2, both engines | 23/23 files and 845 commands per engine. |
| Component async-0.3, both engines | 24/24 files and 153 commands per engine. |
| Component future-gated, both engines | 12/12 files and 387 commands per engine. |
| Wasmtime misc default profile, both engines | 676 pass, 72 script-only, 16 deferred; no failures/timeouts/harness errors. |
| Wasmtime P1 capabilities profile, both engines | 116 pass; 2 not applicable for Wasmtime-specific hostcall fuel. |
| WASI 0.3 HTTP-contract profile, both engines | 110 pass. |

The misc profile retains its existing high-memory/host exclusions; this run did
not opt into high-memory cases. P1 uses the documented capabilities adaptations;
WASI 0.3 uses the existing two-guest HTTP contract corrections. These results do
not claim that the unadapted upstream profiles or deferred cases were executed.
Detailed runner results remain in the ignored `target/iss626-final-*` directories.

The WASI 0.3 runner initially failed before execution because the system Python
lacked `colorama`. The final run used the existing
`target/iss625-wasi03-venv/bin/python`; no toolchain or global Python environment
was modified.

The native test log contains the deliberate `ExpectedExploreCompileFailure`
diagnostic from the existing explore failure-path test. Its final result is
2689 passed, zero failed.

## Ownership and acceptance boundary

[The sanitizer receipt](sanitizer-summary.json) explicitly records
`source_dirty=true`, enabled ASan/UBSan, and positive controls. On this macOS
host, `leak_detection=false` and `lsan_probe=not_applicable`. The finalizer-count
regression verifies the specific closure ownership path locally; it does not
substitute for Linux LSan or instrument MoonBit runtime objects/JIT machine code.

Linux AMD64, macOS ARM64 CI, Windows Clang/MSVC, and Linux ASan/UBSan/LSan remain
pending for this change. ISS-626 stays in progress until that platform acceptance
is recorded. No PR, package publication, or merge was performed by this task.

[Core embedding boundaries](../../core-embedding.md) inventories the checked
embedding API, read-only observations, deliberate raw execution seams, native
ABI capabilities and source-breaking migration. Raw Store-local indices and C
pointers retain explicit preconditions; these checks are not a claim that every
public engine API accepts arbitrary hostile host-written values.
