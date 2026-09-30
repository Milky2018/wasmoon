# Module-shaped context implementation and validation

Implemented on `milky/research-module-context-layout`, based on
`b141554a74d16ac62aac16f4e74a4e51ccdc82e6`. The candidate was an uncommitted
working tree when measured. `source-sha256.json.gz` identifies source contents;
benchmark summaries identify both binaries and inputs. All results below are
local macOS ARM64 results, not Linux/Windows or CI validation.

Toolchain: moon 0.1.20260920 (`914d7da`), moonc v0.10.14+7d59c7ec9.
The baseline was exported with `git archive` to an isolated directory and built
with the same toolchain and `./install.sh`.

## Implementation

`context/layout` owns the module resource shape and offset computation. The
frontend embedding and native compiler embed these offsets in generated code;
allocation and C helpers use the same schema, retained as immutable MoonBit
Bytes shared by instances of a loaded artifact. This is not a dynamic offset
lookup in generated code. Native helpers do perform descriptor loads.

Absent memory/table/global fields occupy no ABI storage. Memory pointer arrays
and table pointer/size/maximum arrays live inside the context allocation.
Memory objects, table objects, global cells and their RC ownership are preserved.
GC fast fields remain present even without local GC instructions because a
cross-module invocation can bind the shared heap. Function addresses and GC
metadata retain their earlier managed ownership. The private native state is
still fixed-size; this change does not eliminate all per-instance metadata.

Activation-owned execution state, parked roots, cancellation captures and
continuation abandonment keep the ownership model established by ISS-606 and
ISS-609. The standalone constructor preserves the legacy offsets. Normal core
CLI and component artifacts use module-shaped contexts. Artifact format 11,
ABI 7, codegen `direct-vcode-9` and cache namespace v11 prevent old layouts from
being reused. Artifact compatibility also checks the resource shape.

## Storage accounting

These are requested bytes, not allocator usable sizes or process RSS. C sizeof
checks give private state 224 -> 216 bytes, legacy ABI 128 bytes, table bindings
40 bytes each, and MoonBit RC headers 8 bytes. Native tests check actual shaped
allocation spans and inline array addresses, including offsets greater than 255.

| Resource shape (memories, tables, globals) | Before: native owner + separate view arrays | After: native owner including view arrays | Native allocations before -> after |
| --- | ---: | ---: | ---: |
| Empty/numeric (0,0,0) | 352 | 256 | 1 -> 1 |
| GC/exception module with no memory/table/global | 352 | 256 | 1 -> 1 |
| One memory (1,0,0) | 360 | 304 | 2 -> 1 |
| Two memories (2,0,0) | 368 | 312 | 2 -> 1 |
| One table (0,1,0) | 376 | 328 | 4 -> 1 |
| Two memories, two tables, one global (2,2,1) | 416 | 408 | 5 -> 1 |

**The table is not total runtime memory.** There is additional shared metadata
per loaded shaped module. Generated native C and the installed MoonBit runtime
account for it as follows:

- Packed descriptor Bytes: 48-byte payload + 1 terminator + 8-byte RC header = 57.
- ContextLayout wrapper: 8-byte pointer + 8-byte RC header = 16.
- Module ContextShape: three Int32 values + 8-byte RC header = 20.
- Additional pointers in CompatibilityManifest and LoadedArtifact: 8 + 8 = 16.

That adds **109 requested bytes and three allocations per loaded module**,
before allocator rounding. Compiler/verification temporary objects are excluded
from this retained-state accounting; cold-process benchmarks include their cost.
If a caller separately retains compatibility/compiler state it can retain
additional shapes too; these numbers describe a loaded artifact and its instances.

For N instances sharing a loaded artifact, the changed retained storage is
`109 - N * per_instance_saving` bytes. Thus a single empty instance adds 13 bytes
net, one-memory adds 53, one-table adds 61, and the full shape adds 101. Requested
byte break-even needs respectively 2, 2, 3, and 14 instances. This implementation
is **not a demonstrated total-memory reduction for a single instance**.

Both versions additionally retain the same context finalizer wrapper (24 bytes),
function pointer array (8-byte header + 8 bytes/function), table bindings
(40 bytes/table in one allocation), global pointer array, resource payloads,
segment state, GC metadata, and activation/continuation state. Those unchanged
terms must be added for a particular workload; GC/exception heap and live stack
size cannot be inferred from resource counts. They cancel in this layout delta,
but are not claimed to be zero. Native allocation counts in the table exclude
these unchanged terms and the three new shared allocations.

## Performance

Nine alternating paired fresh-process samples per workload, cold Wasmoon caches;
three additional phase/compiler diagnostic samples. A separate A/A run compares
the exact same baseline binary. No correctness suites ran concurrently with
these samples. `benchmark.json.gz` and `control.json.gz` contain raw rows,
commands, hashes, phase metrics and summaries (84 and 72 successful rows).

| Workload | Paired median wall-time change | Bootstrap 95% interval | A/A paired median |
| --- | ---: | ---: | ---: |
| auth | -0.28% | [-1.00%, +0.29%] | -0.01% |
| aead_aegis128l | -0.22% | [-0.71%, +0.55%] | +0.20% |
| sign2 | +0.50% | [-0.42%, +0.68%] | -0.22% |

All intervals cross zero. These samples establish no measurable speedup and no
clear regression in the selected workloads. They do not isolate allocator or
code placement from layout effects: changed offsets and ABI necessarily change
artifacts. The conclusion concerns the complete patch, not a causal estimate
of context size. A/A controls quantify measurement noise, not all placement
variation. RSS is recorded but is too coarse to validate the small byte deltas.

The runner's new `--allow-artifact-differences` is explicit and opt-in. Each
version must still produce identical artifacts across its own samples; the
default continues to require identical before/after artifacts.

Reproduction:

```sh
./install.sh
python3 scripts/benchmark_startup.py --before /path/to/baseline/wasmoon \
  --wasmoon ./wasmoon --allow-artifact-differences \
  --output /tmp/context-benchmark --repetitions 9 --diagnostics 3 \
  examples/algorithms/auth.wasm examples/algorithms/aead_aegis128l.wasm \
  examples/algorithms/sign2.wasm
```

## Correctness

Final packed descriptor implementation:

- `moon info`, `moon fmt`, native `moon check --warn-list +73 --deny-warn`: pass.
- Native tests: 2627/2627, including artifact version/shape rejection, wide packed
  offsets, shared descriptor identity, inline spans, replacement/clearing and RC.
- Strict native C checks: 39 units pass; module-boundary and context-lifetime
  audits pass. Benchmark runner unit tests: 4/4.
- Core WAST: 258/258 files, 62,563 assertions **per engine**.
- Wasmtime misc, including high-memory cases: 692 pass, 72 script-only;
  zero failures/timeouts. Both engines are included.
- Component JIT: stable 23 files/845 commands; async 24/153; future-gated 12/387.
- P1 capabilities contract: 116 pass, two not applicable, zero failures,
  both engines. The unchanged explicit-rights contract has 112 pass and four
  failures: file_allocate and path_filestat in each engine. An independent full
  baseline run reproduces the same four failures. They expect NOTSUP whereas
  Wasmoon implements allocation and synchronous-write flags; the existing
  capabilities patch tests those implementations. They are not silently waived.
- ASan/UBSan: 77/77, event-loop lifecycle test and both instrumentation positive
  controls pass. MoonBit runtime objects and generated JIT machine code are
  outside sanitizer instrumentation; this is not proof of absence of all leaks.

Compressed logs and summaries are retained beside this report. Local test success
is not a claim of cross-platform execution or green remote CI.
