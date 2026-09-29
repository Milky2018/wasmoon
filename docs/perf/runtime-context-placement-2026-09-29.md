# Runtime-context placement and guest execution sensitivity

Date: 2026-09-29. Tracking: ISS-592. This report closes a diagnosis, not a production runtime fix.

## Finding

The heap placement of the JIT context is a causal contributor to the AEGIS execution difference between compiler-only native builds. Identical serialized JIT artifacts do not imply identical runtime data placement or performance. We did not establish the hardware mechanism (for example, a particular cache conflict), and do not introduce fixed addresses or context alignment into production.

The original baseline is `ae3ca9c8897999bd4989b56fd730c6ffb09ff432`; baseline and combined executables were checked against the prior candidate archive. Every controlled cache artifact has SHA-256 `e10877609870e29de3cc118eae22eb55e74a160a6625ec1f985c14fb9231d2b0`. Input: `examples/algorithms/aead_aegis128l.wasm`.

## Reproduction and controls

Warm each executable's cache once, then alternate AB/BA process order. Keep all samples. Positive values mean the after side is slower. Intervals are descriptive, pointwise bootstrap 95% intervals, not multiple-comparison-adjusted inference. No local builds or tests overlapped timed runs.

| Experiment | Pairs | Wall change | 95% interval |
|---|---:|---:|---:|
| ab | 21 | +0.680% | [+0.516, +1.047]% |
| aa | 21 | -0.346% | [-0.795, +0.052]% |
| observed | 7 | +0.698% | [-0.144, +2.213]% |
| fixed-jit | 7 | +0.707% | [+0.132, +4.044]% |
| fixed-memory | 7 | +1.260% | [-1.809, +1.489]% |
| fixed-both | 7 | +1.247% | [+0.504, +1.458]% |
| fixed-random | 7 | +1.115% | [+0.298, +1.380]% |
| fixed-stack | 7 | +0.868% | [+0.158, +1.184]% |
| context-control | 7 | +1.299% | [+1.070, +1.459]% |
| aligned-context | 7 | +0.615% | [+0.060, +0.776]% |
| fixed-clock | 7 | +0.675% | [+0.279, +1.078]% |
| fixed-inputs-placement | 7 | +0.107% | [-0.152, +0.346]% |
| without-context | 7 | +1.110% | [+0.687, +1.295]% |
| without-stack | 7 | -0.253% | [-0.305, +0.044]% |
| without-jit | 7 | -0.104% | [-0.159, +0.458]% |
| without-memory | 7 | -0.384% | [-0.602, +0.221]% |
| without-random | 7 | -0.054% | [-0.382, +0.376]% |
| without-clock | 7 | -0.188% | [-0.281, -0.185]% |
| offset-forward | 21 | +1.119% | [+0.998, +1.430]% |
| offset-reverse | 21 | -0.922% | [-1.060, -0.790]% |
| uses-aligned | 21 | -0.222% | [-0.503, +0.016]% |

`ab` uses the original baseline and combined candidate without interposition. `aa` uses the same baseline on both sides. The shim versions and source are archived. Individual placement/input controls did not remove the difference consistently. Controlling JIT mappings, linear memory, fiber stack, random input, clock input and 16 KiB context alignment reduced it to an interval spanning zero. Removing only the context control restored a roughly 1.1% difference. Other leave-one-out controls did not restore that positive gap; the small negative without-clock interval must not be described as spanning zero.

The decisive crossover uses **the exact same native baseline executable on both sides**, the same 16 KiB backing-allocation strategy, and context offsets `0xe00` versus `0xdc0`. It moves only the returned 544-byte context within that allocation and frees the original backing allocation correctly. Forward and reversed labels produce opposite timing effects. Recorded context offsets and random hashes are checked for all 84 measured processes. JIT and stack mappings are identical. One forward baseline process (pair 7) has a different second linear-memory mapping: the OS did not honor the repeated hint in the same way. All other controlled mapping sequences match. The primary result retains that sample; a separately labeled sensitivity calculation excluding pair 7 remains +1.106% [95% interval +0.990, +1.406]. This sensitivity result is secondary; the all-sample estimate remains primary. This isolates context placement as a cause in this controlled workload; it does not prove that every uncontrolled fluctuation has this cause.

Fixed-clock experiments deliberately change the clock import to deterministic values. Their internal phase durations and printed guest timer values are **synthetic and unusable as timing evidence**. Only Python process wall time and real `getrusage` CPU measurements remain meaningful. The archive retains synthetic fields for completeness, with this warning. The machine was not isolated from all OS activity.

## Sampling and scope

Short-process sampling returned empty call graphs. A separate profiling-only fixture increases the AEGIS benchmark loop and its matching averaging divisor from 200 to 2000. One-second samples put most main-thread observations in the same JIT mapping for both binaries. Disassembly near the observed offset contains the context memory-base load followed by guest loads/stores. Sampled PCs do not identify a hardware stall mechanism. An unsuccessful LLDB launch provided no evidence. Failed/empty diagnostics are retained.

The archive includes all probe source versions, recipes, recorded mappings, process samples, raw rows, summary statistics and executable hashes. Build probes with `clang -dynamiclib -O2 -Wall -Wextra -Werror`. These macOS interposers are diagnostic fixtures, not supported runtime configuration or production code. The profiling fixture transform is the single `i32.const 200` before `local.set 17` and matching `i64.const 200` before `i64.div_u` changed to 2000 in the original printed WAT.

## Decision

A separate 21-pair reevaluation of the old conditional-use-count candidate, using only 16 KiB context alignment and real clocks, finds wall -0.222% [-0.503, +0.016] and invocation -0.324% [-0.518, +0.093]. This does not establish a guest regression or a guest speedup under that control. It does not authorize shipping an old compiler patch against current HEAD: conditional use counts remain withheld pending a fresh revision-specific compiler and ordinary CLI acceptance run.

Keep ordinary end-to-end CLI measurements alongside artifact identity checks. If a compiler-only change shifts guest timing, use placement controls to explain the discrepancy; do not silently normalize it away or tune binary layout until a benchmark improves. No production memory-base or register-reservation policy changes were made.

Evidence: [compressed raw data and diagnostic sources](runtime-context-placement-2026-09-29.json.gz).
