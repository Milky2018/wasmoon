# Native GC type admission

Tracking: [ISS-692](../../issues/ISS-692.md), [ISS-693](../../issues/ISS-693.md).

A five-second current-head regex sample places struct-view admission ahead of
other native helpers. Separate diagnostic counters at n=2100 observe 1,042,931,643
requests: 210,166,457 exact-cache hits, 600,668,099 uncached exact admissions and
232,097,087 subtype admissions. Instrumented execution is not timing evidence.

The subtype path had already checked the live struct and concrete target, then
called general `ref.test`, which decoded the object again and retrieved its kind
and local type before reading its canonical identity. The helper now uses that
identity with the same registered subtype relation. Missing/legacy identities
and abstract targets retain the complete existing fallback. Nominal ancestry,
prefix shape, field count, null/bounds checks, verifier flags and borrow lifetime
remain enforced. No new cache, guest expansion, ABI or artifact revision is added.

## Controlled comparison

Parent: e6d31bc7. Five alternating cold pairs per case, 60 fresh processes total,
serial execution with independent caches and retained guest assertions. All
artifacts are byte-identical across both binaries and every sample. Times below
are invocation medians; compilation and whole-process RSS are measured separately.

| Workload | Parent | Change | Invocation ratio95% interval |
| --- | ---: | ---: | --- |
| Regex GC n=700 |1567.6ms|1468.7ms|0.9375–0.9413|
| Regex GC n=2100 |18605.3ms|17692.2ms|0.9504–0.9522|
| Parse-double 20k |1638.0ms|1627.7ms|0.9859–0.9981|
| Small surviving graph |201.3ms|202.8ms|0.980–1.042|
| Large surviving graph |108.3ms|106.1ms|0.965–1.090|
| Zero i32 arrays |22.8ms|22.5ms|0.975–1.005|

Regex RSS remains approximately 316MB/2.114GB. Its compilation changes 369/374.5ms
to 370.1/375.6ms, with intervals crossing no change. Parse-double compilation
changes 758.7ms to 765.9ms, a small regression with ratio interval 1.004–1.020;
report it rather than inferring that unchanged guest artifacts imply identical
host compilation performance. Other controls do not establish an invocation gain.
This is an incremental comparison against the already optimized PR head, not a
new cross-engine result.

## Validation boundary

Public raw-JIT regression covers transitive canonical subtypes, equal-width
nominal rejection and legacy wide objects at O0/2/3, with an interpreter control.
It passes on the original implementation too. Deliberately bypassing canonical
subtype admission makes the unrelated-layout assertion fail; exact restoration
passes. Existing view growth, compaction, mutation, rollback and close controls
remain active. Eleven focused struct tests pass with all three verifiers.
Full native 3152/3152 ordinary and verified, Wasm 1465/1465, strict both,
info/fmt, C45 and boundary/MSVC audits pass. Clean local Core/Component and
ASan353 pass. Exact e0076b1 run40149380505 passes all six jobs, including fresh
LinuxLSan353/three controls, bothWindows3152/64 and clean portable provenance.
ARM64 disassembly keeps legacy ref.test and inlines canonical parent admission.
Raw profiles, fixtures, samples and caches remain in auto-cleaned OS temporary
workspaces.

## Concrete reference predicates

A fresh sample after the struct change still identifies ref.test and its object
queries. Independent n2100 counters observe244,433,867concrete canonical tests.
ARM64 code calls both kind and local-type helpers before branching on the target
kind. Neither result is used by the canonical path. Concrete checks now read
canonical identity first; only legacy checks query local type, and only abstract
checks query kind. Tags, nullability and nominal relations are unchanged.
The registry can be republished outside guest execution: neither optimization
caches subtype answers or assumes a view pointer implies immutable ancestry.

Five alternating cold pairs, six workloads and60asserted fresh processes compare
the predicate change alone against e0076b1. Every guest artifact remains identical.

| Workload | Parent invocation | Change | Parent/change compilation |
| --- | ---: | ---: | ---: |
| Regex GC n700 |1472.3ms|1430.7ms|369.6/374.9ms|
| Regex GC n2100 |17679.1ms|17328.1ms|373.8/380.6ms|
| Parse-double20k |1629.7ms|1613.0ms|767.1/780.4ms|

Regex invocation ratio95% intervals are0.9653–0.9775 and0.9744–0.9920. RSS
remains approximately316MB/2.114GB. Compilation medians regress about1–2%,
with intervals excluding no change for these workloads. Graph/zero-array
invocation controls do not establish a gain. These are measured tradeoffs,
not a claim that every phase improves. No Wasmtime/V8 ratio is inferred here.

A public raw-JIT/interpreter matrix covers base/child/unrelated structs, arrays,
i31, nullable/bottom predicates, casts and legacy local-type fallback at O0/2/3.
It passes on the original source; deliberately replacing canonical subtype
answers with true fails the actual predicate assertion. Exact source restoration
passes with all three verifiers. Native3153 ordinary/verified, Wasm1465, strict
both, info/fmt, C45 and boundary/MSVC gates pass. Fresh clean integration/SAN
and new exact-head acceptance are separate. Raw data stays in auto-cleaned
temporary workspaces.
