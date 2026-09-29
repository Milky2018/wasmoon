# Context metadata storage, lookup and publication

Date: 2026-09-29. Tracking: ISS-603. Baseline: `08fd0844592ca14f14987c0c112fa2aaeb54b77c` (the whitespace-only successor of `aabcfd31`).

## Changes and ownership

Per-function safepoint tables now directly own their stackmap and code-offset allocations. Two duplicate pointer arrays have been removed. On this macOS arm64 build, the context owner decreases from 456 to 440 bytes. Once safepoint storage is initialized, the removed arrays save another 16 bytes per function slot and two allocations per context. The generated-code prefix remains 128 bytes; no artifact revision or generated offsets changed.

The callable registry stores sorted 16-byte entries containing a 64-bit function address, a 32-bit canonical identity and a 32-bit original input position. This uses the same per-entry storage as the old pair of 64-bit integers. The original position preserves the public setter's first-match behavior for duplicate addresses. Lookup uses lower-bound binary search. Publication uses the C standard library's `qsort`; there is no custom sorting implementation or persistent auxiliary index.

A replacement with unchanged input addresses reuses the sorted allocation and updates identities through their original positions. Parent arrays are replaced only when their contents change. Changed arrays are allocated before committing, preserving the old view on allocation failure. Store execution remains serialized; this is not a concurrent publication mechanism. Address changes still rebuild/sort the full entry array. This is intentionally not a general incremental-update protocol.

The Store skips snapshot construction when there are no native subscribers, and avoids publishing again when retrieving an existing registry with unchanged callable identities. Existing explicit legacy view binding still sends its initial full snapshot.

## Allocation evidence

The native probe creates 64 contexts with 32 function slots each, binds a shared registry containing 256 types and 2,048 functions, and installs one safepoint slot in every context. It verifies lookups and releases all contexts.

| Requested C allocations | Before | After |
|---|---:|---:|
| Initial bytes | 179,456 | 145,664 |
| Initial allocation calls | 578 | 450 |
| Allocations for an unchanged publication | 2 | 0 |
| Total allocations / matching nonnull frees | 580 / 580 | 450 / 450 |

These are requested allocation sizes, not RSS. They exclude MoonBit-managed allocations and any internal allocations performed by libc. The native registry payload remains 24 bytes; callable entries remain 16 bytes. The 33,792-byte reduction is exactly 64 times the 16-byte owner reduction plus 32 times 16 bytes of removed safepoint pointers.

## Rejected alternative and publication tradeoff

The first candidate used MoonBit's stable sort before crossing the FFI. A full public-API benchmark of 1,000 replacements with 256 parents and 2,048 unordered entries measured roughly 2.5 ms before versus 84 ms with this candidate. It was rejected, and its source and raw samples are retained in the evidence archive.

The final native representation avoids repeated sorting when addresses remain unchanged. It does not make every forced replacement faster: checking the existing address mapping has a cost, and rebuilding a changed address set requires sorting. Public-API measurements include MoonBit array conversion and all native work, rather than timing only the C allocation path. Normal Store calls can skip publication entirely; the forced-replacement benchmark deliberately bypasses that optimization. New instances with changed address sets still pay the rebuild cost, so this is a read/update tradeoff rather than a universal speedup.

## Lifecycle and portability

Regression tests cover metadata copies outliving their input buffers, replacement and clearing of a safepoint slot without affecting peers, destruction with live slots, unordered callable input, duplicates and identity changes, lookup misses, large reverse-ordered input and clearing. Existing shared-registry isolation, parent subtype and Store terminal-close tests remain enabled.

Linux CI for the baseline exposed an undefined reference to `wasmoon_jit_bind_callable_registry` from the test-support archive: its newly separate C object was not pulled in by that link order. The binding entrypoint now lives in the context lifecycle translation unit alongside the allocation/get-pointer functions that those tests already require. No linker retention flags or synthetic anchor calls were added. This change needs confirmation in the new Linux CI run; macOS validation alone cannot prove ELF archive behavior.

The context/activation ownership review is recorded in ISS-602. Reentry and suspension already detach exception and GC-chain state into an activation; abandonment temporarily restores that state for context-based cleanup. A full migration must change helper access and cleanup together and preserve standalone helper behavior. No new activation correctness failure was established, and that architectural migration remains open.

## Timing

Measurements are serial on one macOS arm64 machine, with no builds or regression runs from this task overlapping timed samples. Native lookup and public replacement use seven retained alternating pairs after one warmup pair. Guest runs retain 31 rounds with rotated/reversed version order. Reported changes are median paired ratios; bootstrap intervals are descriptive (10,000 resamples), not cross-machine guarantees.

The lookup probe calls the actual native runtime helper 200,000 times, mixes hits and misses with a fixed PRNG sequence, and verifies its checksum. Construction and sorting occur outside its timer.

| Entries | Before lookup batch | After lookup batch | Paired change |
|---|---:|---:|---:|
| 4 | 0.531 ms | 0.511 ms | -3.58% |
| 64 | 3.444 ms | 2.843 ms | -17.20% |
| 1024 | 41.164 ms | 4.410 ms | -89.27% |
| 16384 | 664.031 ms | 7.547 ms | -98.87% |

The four-entry result is inconclusive (interval crosses zero). Large-table lookup savings are clear in this probe; they are not whole-program speedups.

The public replacement benchmark uses 256 parents, 2,048 unordered entries and 1,000 calls per mode. Values below divide the batch median by 1,000 to show average time per replacement within that batch.

| Replacement mode | Before | After |
|---|---:|---:|
| unchanged | 2.219 us | 3.439 us |
| parents | 2.211 us | 3.480 us |
| identities | 2.223 us | 3.474 us |
| addresses | 2.242 us | 48.052 us |

Address rebuilding is approximately 21 times slower in this synthetic update-heavy case. This is accepted as a read/update tradeoff for the registry: binary lookup avoids scanning the entire Store on guest queries, while function address changes occur during binding/publication. It is not appropriate to advertise the publication path as uniformly faster. Workloads that constantly replace callable address sets with little subsequent execution remain a limitation, and a true incremental representation is not implemented here.

| Guest workload | Before | After | Paired change | Bootstrap interval |
|---|---:|---:|---:|---:|
| indirect | 231.54 ms | 231.93 ms | +0.71% | -0.84% to +2.40% |
| aegis | 710.70 ms | 709.05 ms | -0.28% | -0.49% to -0.04% |

Indirect is the prior 10-million-call WAST fixture; its interval crosses zero. AEGIS uses warm caches verified for each sample. A third executable from `77d901d0` is measured in the same rounds: the previous shared-registry version is +0.28% relative to it [-0.12%, +0.64%], and this version is -0.14% [-0.32%, +0.25%]. Thus the earlier repeated +0.9% is not reproduced at that magnitude in this session. This does not erase the earlier evidence or establish a hardware root cause. All three cache artifacts have the same SHA-256, excluding a change in serialized generated code in this comparison.

## AEGIS placement control

A diagnostic-only macOS interposer runs all three executables with fixed random/clock input, identical verified JIT/linear-memory/native-stack mappings, and context offsets 0xe00 and 0xdc0 within a 16 KiB-aligned allocation. It identifies the controlled context by its 71-function count and valid guest stack global. No generated instructions are patched. Guest synthetic timing output is ignored; external wall time is measured. Each offset retains 15 rounds after warmup.

An initial observer also recorded an unrelated allocation with the same size and failed its uniqueness assertion. That sample was excluded; the corrected observer records only the allocation it actually relocated and verifies the initialized context. The rejected log and diagnostics are retained.

| Context offset | Comparison | Paired wall-time change | Bootstrap interval |
|---|---|---:|---:|
| 0xdc0 | before/original | +0.41% | -0.59% to +1.26% |
| 0xdc0 | after/original | +0.33% | -0.14% to +1.42% |
| 0xdc0 | after/before | +0.93% | -0.48% to +1.40% |
| 0xe00 | before/original | +0.05% | -0.14% to +0.22% |
| 0xe00 | after/original | -0.09% | -0.90% to +0.30% |
| 0xe00 | after/before | +0.14% | -0.86% to +0.28% |

Every interval crosses zero. These controls do not establish a stable version penalty or prove that placement caused the earlier 0.9% observation. The earlier instruction/address investigation in ISS-599 applies to its own pinned baseline; it must not be promoted to proof for this newer difference. Current evidence rules out changed serialized code, bounds the observed differences in this session and leaves the specific earlier cause unconfirmed. No production alignment workaround is shipped.

## Validation

- Strict MoonBit native check with warning 73 enabled and warnings denied.
- 2,610 native tests and 65 sanitizer tests passed; sanitizer instrumentation verified.
- 38 native C stubs checked with warnings denied; module boundary audit passed.
- Core WAST: both engines passed 258/258 files, 62,563 assertions each.
- Async 0.3 component WAST: 24/24 files, 153 commands, none skipped.

Raw samples, source probes, rejected candidates, binary/source hashes, allocation counts and validation logs are retained in [the evidence archive](context-metadata-2026-09-29.json.gz). The archive identifies the exact baseline and measured after-source hashes. Linux CI confirmation of the archive-link fix remains a separate delivery check.
