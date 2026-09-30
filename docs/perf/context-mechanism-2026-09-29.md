# Context placement: native spill addresses and repeated context loads

Date: 2026-09-29. Follow-up to ISS-592; tracking ISS-599.

## What is established

The AEGIS context-offset effect can be reproduced in one process with the exact hot machine-code function, captured input, and controlled JIT/linear-memory/native-stack addresses. It depends on the low address bits of repeated 64-bit memory-base loads and native stack accesses. Moving either side changes the effect predictably, including sign reversals and recurrence after a 256-byte displacement.

This is stronger than an alignment correlation: concrete instructions and stack locations have causal interventions. It is **not** a proven identification of a particular M3 hardware unit or PMU event. Partial-address memory disambiguation/forwarding effects are the leading explanation. Ordinary cache-capacity conflict and scheduling alone do not adequately explain these interventions, but timing alone cannot name an undocumented hardware mechanism conclusively.

No production code, context alignment, register reservation or allocation policy is changed. All machine-code edits below are diagnostic interventions. Frame edits do not update production unwind metadata; no trap/unwind acceptance is claimed for them.

## Fixed evidence and minimal replay

Use the original baseline executable from ISS-592, SHA-256 `d2946cb166a5a6b3c4f9467ccf28760b76f40e938dc54a9acaf740bccf8f73f8`, source `ae3ca9c8897999bd4989b56fd730c6ffb09ff432`. The hot function is identified by matching its complete 1328 bytes at the recorded mapping, rather than assuming mapping order equals a function index. Its controlled address is `0x20000078000`.

The first actual call has guest SP `0xffde0`, output `0xffee0`, input `0xffed0`, second input `0xffec0`, memory base `0x30200010000`, and native entry SP `0x40001003930`. The sparse replay fixture retains the exact table and input bytes read by the function, with the original full capture hash. Replay checksums agree across original and altered functions. A zero-filled sparse reconstruction was replayed through 124 replay cases and matches checksum 300361051. This is a function-level semantic check; the full benchmark's printed synthetic timer is not an independent cryptographic oracle.

The original 128-byte frame puts two 32-bit spill slots at:

```
entry SP        = 0x40001003930
frame SP        = 0x400010038b0
[SP + 0x18]     = 0x400010038c8  (4 bytes)
[SP + 0x1c]     = 0x400010038cc  (4 bytes)
context + 8     = ...dc8         (8 bytes, slow context position)
context + 8     = ...e08         (8 bytes, comparison position)
```

These are distinct real addresses. Only their low address bits overlap. The hot loop reloads the same context memory-base field eight times, although `x12` already contains that base throughout the loop. One intervention replaces those loads with `mov destination, x12`, preserving instruction count and positions. This introduces no new reserved register in the diagnostic function.

Synthetic input without fixed native code/stack addresses did not reproduce a stable offset difference. Captured input alone was also insufficient. Fixing the original code, linear-memory and native-stack addresses produced the same-process effect. These negative probes are retained rather than omitted.

## Same-process interventions

Each row uses 31 alternating AB/BA pairs per variant. Positive means context `0xdc0` is slower than `0xe00`; for the +4096 row both offsets are shifted together. Intervals are descriptive pointwise bootstrap 95% intervals, not multiple-comparison-adjusted guarantees. No local builds or other benchmark processes overlapped timed runs. The OS was not isolated from other activity.

| Intervention | Original instructions | Altered instructions |
|---|---:|---:|
| Fixed original addresses; reuse all eight loads | +1.577% [+0.870, +1.998] | -0.435% [-0.877, +0.104] |
| Guest SP +128; reuse all eight loads | +1.615% [+1.264, +2.026] | +0.140% [-0.212, +0.356] |
| Native SP +64; reuse all eight loads | -1.309% [-1.523, -0.752] | -0.036% [-0.361, +0.119] |
| Native SP +128; reuse all eight loads | -0.260% [-0.840, +0.659] | +0.118% [-0.596, +0.764] |
| Native SP +256; reuse all eight loads | +1.996% [+0.489, +2.448] | -0.149% [-0.675, +0.183] |
| JIT code +64; reuse all eight loads | +1.829% [+1.633, +2.049] | +0.027% [-0.452, +0.349] |
| Context +4096; reuse all eight loads | +1.650% [+1.146, +2.369] | +0.077% [-0.102, +0.632] |
| Reuse only the last of eight loads | +2.035% [+1.625, +2.295] | +1.619% [+1.373, +2.274] |
| Reuse the first seven loads | +1.827% [+1.395, +2.183] | -0.202% [-0.346, +0.169] |
| Move eight load sources +128; keep loads | +2.169% [+1.671, +2.745] | +0.294% [+0.011, +0.753] |
| Move eight load sources +192; keep loads | +1.997% [+1.731, +2.223] | -1.103% [-1.405, -0.871] |
| Move eight load sources +256; keep loads | +1.942% [+1.359, +3.277] | +2.199% [+1.562, +3.071] |
| Move only spill slot +0x18 to +0x2c | +1.656% [+1.340, +1.875] | +0.630% [-0.072, +0.985] |
| Extend frame by 16; preserve all accessed addresses | +1.649% [+1.297, +1.983] | +1.738% [+1.398, +2.399] |
| Extended frame; move spill slots +0x18 and +0x1c | +1.633% [+1.422, +1.966] | +0.085% [-0.222, +0.294] |

For load-source interventions, duplicate the memory-base pointer at another location in the synthetic context and change only the immediate of the eight loads. Instruction count and load count are unchanged. +192 reverses the effect, while +256 retains it. +128 reduces the original effect substantially but its small residual interval does not cross zero; it must not be called a complete elimination.

The frame control changes SP by 16 and compensates all SP-relative offsets, preserving actual accessed addresses. The moved-frame variant additionally relocates the two 32-bit slots into the newly available 16-byte space. Other accessed addresses, instruction count, branch offsets and register uses are unchanged. This separates concrete slot placement from merely increasing frame size. Moving one slot alone is less effective than moving both.

## Return to the complete workload

Serialized artifacts remain identical; runtime code is deliberately altered by the interposer after byte matching. The full process runs use fixed random/clock input and mapping hints, with each configuration warmed once. Only external wall time is interpreted as performance: guest timer output and phase clocks are synthetic. All measured samples are retained. Mapping hints are not guaranteed by the OS; raw mappings are archived.

| Experiment | Pairs per variant | Original offset difference | Altered offset difference |
|---|---:|---:|---:|
| Initial eight-load reuse | 15 | +1.327% [-1.148, +2.984] | +0.023% [-1.231, +0.287] |
| Move two slots | 31 | +0.835% [+0.660, +1.219] | +0.648% [+0.106, +0.795] |
| Repeat eight-load reuse | 31 | +1.133% [+0.812, +1.475] | +0.036% [-0.273, +0.275] |

Moving the two slots did **not** remove the whole-program offset difference. A non-timing entry trampoline that preserves entry SP explains why the first-call replay is incomplete: actual calls reach this function at multiple native SP residues. The first captured SP residue is only part of the dynamic workload. The census itself changes execution and is used solely to count entry addresses, never as a timing sample.

| Entry SP low byte | Calls | Share |
|---|---:|---:|
| `0x20` | 2225600 | 21.07% |
| `0x30` | 2764800 | 26.17% |
| `0x40` | 1024000 | 9.69% |
| `0x50` | 470400 | 4.45% |
| `0x60` | 235200 | 2.23% |
| `0xa0` | 396680 | 3.76% |
| `0xb0` | 1251152 | 11.84% |
| `0xc0` | 1787360 | 16.92% |
| `0xe0` | 407752 | 3.86% |

A particular slot move fixes the first-call replay but cannot cover every caller's stack placement. The repeated-load intervention addresses the context reads across all those placements; the full-program result above, rather than the first-call microbenchmark, bounds its effect. Neither intervention is proposed here as a shipped compiler optimization.

## Hardware interpretation and limits

The 256-byte recurrence, sign reversal when native SP or load source moves, and slot-specific interventions strongly support a partial-address load/store interaction. They do not prove whether the penalty is a wait, replay, forwarding restriction, or another implementation detail. No claim is made about a specific cache set, number of cache ways, or a `MEMORY_ORDER_VIOLATION` event count.

An exploratory five-second Instruments CPU Counters recording was obtained, but it uses the default guided bottleneck configuration, terminates the launched process at the time limit, and is not a paired event-specific comparison. It is not used to establish a hardware mechanism. Exact confirmation would require suitable event-specific measurements on this M3 Max (and ideally reproduction on another CPU).

Background only: [Dougall Johnson's M1 load/store experiments](https://dougallj.wordpress.com/2021/04/08/apple-m1-load-and-store-queue-measurements/) describe memory dependency prediction experiments and explicitly warn about reproducibility on later hardware. They are not proof of M3 behavior. Apple's [CPU optimization guide landing page](https://developer.apple.com/documentation/apple-silicon/cpu-optimization-guide) places the detailed guide behind a developer-account agreement; that restricted guide was not accessed.

## Engineering consequence

Do not fix this by selecting a lucky context alignment: the preferred placement depends on native stack residues and reverses under controlled shifts. A more robust candidate is avoiding redundant memory-base loads when the existing value remains valid, subject to register pressure, calls/growth invalidation and current-revision acceptance. This finding does not authorize a globally reserved memory-base register or establish a speedup for current compiler output.

The investigation establishes instruction/address-level causality and leaves the exact microarchitectural mechanism unconfirmed. No production correctness defect was found or fixed.

Evidence: [sources, replay fixture, raw samples and summaries](context-mechanism-2026-09-29.json.gz).

## Delivery validation

Production source is unchanged. `moon info`, `moon fmt`, strict native checking with warnings denied, and all 2605 native tests pass; logs are in the evidence archive. The previously pending [Check and Test run 36517870026](https://github.com/Milky2018/wasmoon/actions/runs/36517870026) at production code revision `9ef491a1` has now completed successfully across all five jobs, including Windows Clang. No new CI run is needed to validate these documentation-only changes.
