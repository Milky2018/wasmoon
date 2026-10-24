# Reuse canonical VCode instruction handles

Repeated flat queries constructed new owner-tagged `Instruction` wrappers even
though each instruction already had a canonical handle in its block. Scoped
constructor sampling of the current pinned parse workload attributed 4,379,047
allocations and 105,097,128 bytes to this query. These are cumulative sampled
constructor bytes, not live memory or a complete allocator/RSS measurement.

A private dense vector now retains those existing handles alongside instruction
records. Both builder insertion paths append the same immutable handle already
published to the block. Queries keep their bounds guard; all ownership, operand,
metadata and verification checks remain unchanged. The owner token does not
reference the Function, so the vector introduces no ownership cycle or public
API change. No mutable payload is cached.

A single field inside the larger instruction record slightly regressed small
inputs; private value representations were flat or slower. Those experiments
are removed. The dense vector avoids that record indirection. Generated C for
the query reads and retains the existing handle without constructing a wrapper.

Fifteen alternating serial cold pairs on macOS ARM64 use the existing public
`testsuite/compiler_memory` fixture, with no allocation instrumentation or JIT
cache. Every compared artifact is byte-identical. Parent is `7173217`, binary
`1671b46e74a9`; candidate binary is `08f1cd6d1a35`. Compilation excludes artifact
encoding and file I/O. Use `scripts/benchmark_compiler_memory.py` to repeat this
boundary; Wasmtime comparisons require serial compilation as documented there.

| Input | Parent median | Candidate median | Median paired change |
| --- | ---: | ---: | ---: |
| auth3 | 41.520ms | 40.705ms | -1.88% |
| Argon2i | 71.935ms | 70.288ms | -2.24% |
| ed25519 conversion | 133.467ms | 130.212ms | -2.19% |
| current parse property | 828.862ms | 796.071ms | -4.05% |

All paired bootstrap 95% intervals are below zero. Peak RSS stays within about
one percent; the extra dense reference vector is a real storage cost. The parse
input is extracted from Core `7547b846`, current compiler output SHA-256
`d256b1ab6b9a310e8240fca61bf9972e73978cc3cf0506ed886f183c4962bb31`;
it must not be mixed with the historical October16 guest or its timing table.

Public lifetime/foreign-owner controls pass on native and wasm, including handles
kept after their creating Function is released. Full native3123, wasm1465 and
strict checks pass; verified and ordinary JIT Core/Component executions pass.
Clean current-head sanitizer and actual Windows/x64 execution are CI gates.
