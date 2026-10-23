# Separate compilation and invocation against Wasmtime

Local measurement only, based on dirty Wasmoon `7cf4fe9895a38e6315813eec9f28c2379aaab057`.
Functional sources match the preceding implementation receipt. No compiler or
runtime code changed in this follow-up. All raw samples and the complete temporary
Rust harness, manifest, lockfile and timing driver are in the
[JSON receipt](issue568-wasmtime-phases-2026-10-23.json).

## Same input, separate phases

The asserted 20000-iteration Core property is unchanged: probe SHA-256
`fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`. Every invocation returns 1.
Five fresh processes per engine run serially, with reversed engine order on
alternate rounds. Wasmoon uses a fresh empty cache for every sample. Wasmtime
uses one compilation thread and no cache; its collector is explicitly Copying.
All owned builds have finished before timing. Unrelated host activity is left
alone; the outlying Wasmtime compile sample is retained, not discarded.

Seconds, five-sample medians:

| Stage | Wasmoon | Wasmtime API | Wasmoon / Wasmtime |
| --- | ---: | ---: | ---: |
| Compilation timer | 1.074480 | 0.333068 | 3.23x |
| Instantiation including start | 0.010596 | 0.000292 | Different embedding setup |
| First invocation | 2.344665 | 2.368019 | 0.99x |
| Ready-to-invoke phase sum | 1.149864 | 0.333451 | 3.45x |
| Whole process | 3.494085 | 2.827711 | API versus CLI embedding |

The stock Wasmtime CLI whole-process median in the same rounds is
2.739962s. It is a cross-check, not an
invocation timer. Invocation is effectively at parity for this specific workload;
the remaining end-to-end difference against Wasmtime is concentrated in
compilation/preparation. This does not resolve the separate optimized-V8 goals
or establish parity on other programs.

## Timer boundaries

Wasmtime is measured directly through its exact 49.0.1 source revision
`46c23a87dac1465986a8ad53ba6a7ae49372857b`, with dependencies pinned to that
source's lockfile. `Module::new` includes validation, native compilation and
code publication. File reading and Engine construction are outside this timer.
Store/Linker construction and `instantiate_async`, including start, are timed
separately. The invocation timer wraps `Func::call_async`, matching the stock
CLI call form, and includes guest GC and runtime helper costs.

Wasmoon's existing `compile` phase wraps `compile_validated_module_to_jit`.
Read/parse, validation, artifact checks, cache writing and code loading/GC setup
remain separate. Therefore the compile columns are explicit API timers, not a
claim that their internal boundaries or amount of compiler work are identical.
The ready-to-invoke row sums each sample's phases before taking the median.
Wasmoon's read/parse phase includes file reading; the API harness reads the input
before its timers. Neither row mixes compilation with the probe's invocation.

## Verify the harness represents the CLI

The initial reduced-feature harness was rejected because it lacked the CLI's
concurrency tunable. It is recorded as a diagnostic control, not primary evidence.
The retained harness enables matching concurrency/stack support and Copying GC.
Its trusted local serialized artifact loads and runs in the stock CLI, and the
CLI artifact loads and runs in the harness. Both return 1.

More strongly, their generated ELF `.text` sections are byte-identical:
983040 bytes, SHA-256
`02c9695dc0189cec04de354beac4a59c9f2c5cabc732158b4283f65881bb34bf`. The official C API archive's DRC result
from the older investigation is not reused. The compatibility/AOT controls are
excluded from all five primary compile/invoke samples.

This is local macOS ARM64 evidence. Background load makes the absolute times
different from the preceding batch; only same-round phase ratios are used here.
The raw ranges are preserved. All temporary harnesses, Cargo registry/builds,
Moon outputs, artifacts, caches and logs are removed after saving the receipt.
No production source, release, commit or delivery action is part of this probe.
