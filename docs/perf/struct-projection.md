# Reusing admitted struct metadata

Tracking: [ISS-692](../../issues/ISS-692.md).

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
info/fmt, C45 and boundary/MSVC audits pass. Fresh clean sanitizer and new
exact-head CI are checked separately. ARM64 disassembly keeps the legacy
ref.test call and emits the canonical parent relation inline.
Raw profiles, fixtures, samples and caches remain in auto-cleaned OS temporary
workspaces.
