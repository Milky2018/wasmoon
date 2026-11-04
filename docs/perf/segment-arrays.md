# Data-segment arrays

Tracking: [ISS-695](../../issues/ISS-695.md), [ISS-696](../../issues/ISS-696.md).

Core validation already accepts vector element types for array.new_data and
array.init_data. A public unaligned v128 fixture passes wasm-tools validation
and returns1 in Wasmtime49; the parent ac02661 JIT traps unreachable and its
interpreter CLI raises TypeMismatch. Explicit managed-Store execution instead
constructs null elements. This is a correctness defect, not a measured speedup.

The JIT metadata now distinguishes v128 with the existing six-word type-cache
stride and a16-byte element width. The interpreter uses the same width and an
owned16-byte value. Native segment decoding returns the existing two-word GcSlot;
both data operations use the established wide setter. Scalar conversions retain
their prior bits; element-segment reference writes are unchanged. The correctness repair is independent of the numeric bulk-copy optimization
below; allocation admission and validation remain unchanged.

Source/destination bounds still precede every element write. Dropped segments,
null references and zero-length ranges keep their ordering. Canonical and legacy
native arrays use their existing storage adapters. Public regressions retain both
vector words, unaligned strides, adjacent sentinels and post-collection values;
failed ranges cannot partially initialize the destination. Native JIT and
interpreter controls run at optimization levels0/2/3, and the portable interpreter
tests run on native and actual Wasm. The latter tests are also included in the
fresh sanitizer closure.

Before the repair, both new vector-value portable tests fail on native and Wasm,
while the dropped/null control passes; the native two-test segment matrix also
fails. Afterward native3164 ordinary/verified, Wasm1468, strict both, info/fmt,
C45, boundaries and generated MSVC bridges pass. The independent correctness head6ddd582 also passes clean Core/Component,
MacSAN365 and all six platform jobs with Linux LSan and clean provenance.
The later bulk-copy optimization requires its own clean/platform acceptance. Raw probes and
fixtures remain in automatically cleaned OS temporary workspaces.


## Numeric bulk initialization

A scaled i32 initialization profile attributes1174/1542 main-thread samples to
repeated checked wide setters. Both data operations now share a private copy
admission: at least four elements, a live canonical numeric array with the exact
physical width, and a little-endian host. Source/destination checks still finish
before copying. Unknown wide slots and other hosts retain the decoder/setter
path, including conservative barriers. Numeric copies verify the heap once after
the complete operation. There is no new allocator or collection policy.

On macOS ARM64, five alternating cold pairs over38 asserted cases compare
6ddd582 with this copy path. Guest artifacts are identical in all380 processes.
For65536 elements, median invocation milliseconds are:

| Element | new_data before / after | init_data before / after |
| --- | --- | --- |
| i8 |320.731 /4.107 |2323.039 /4.959 |
| i32 |47.842 /4.253 |362.342 /6.575 |
| i64 |25.274 /4.350 |179.837 /6.660 |
| v128 |15.214 /4.115 |99.970 /6.558 |

These are repeated operation workloads, not whole-application speedups. New-array
traffic is bounded to64MiB and initialization to512MiB; construction retains its
single non-collecting attempt. All seven numeric kinds improve at this size.
Small1–3-element controls mostly overlap: single-element initialization costs
about2% more for i32 and4% for v128 (paired ratio95% intervals1.009–1.034 and
1.006–1.062). An unconditional-copy prototype regressed tiny cases14–69% and was
rejected. The simple four-element boundary keeps that tradeoff bounded without
per-type special cases. Compilation/RSS are reported separately, with no compiler
improvement claimed. scripts/benchmark_gc_segments.py reproduces the asserted
size/width controls through the shared serial cross-engine protocol.

Public tests cover raw NaN bits, both vector words, unaligned source ranges,
neighbors, collection, legacy wide slots and their conservative barriers. Forcing
legacy admission loses four required barriers and fails; omitting the copy loses
values and fails. Forcing endian refusal passes through the original decoder.
This fallback control is not execution on a big-endian machine.
