# Cancellation-poll diagnosis and function-table ownership

Date: 2026-09-29. Tracking: ISS-610, ISS-612; parent ISS-602.
Migration baseline: `f3b1e0aa9cc68f7cecaf795adaebc31f4035ac75`.
Original control comparison: `951b7b1f5ab14138067001178159155fb4501310` versus `6d447b7da60e410c856fe5a1cc59d9eb79d652ed`.

## What the earlier timings measured

The original workloads use the WAST runner. That runner explicitly enables cancellation instrumentation (and uses optimization level zero and stack switching). The translator inserts a CancelPoll at function entry and loop headers. The indirect workload therefore exercises polling at both its loop and its called guest function. Ordinary uncontrolled `run` uses different compiler configuration and does not enable these cancellation safepoints; it is a useful comparison, not a strict single-factor experiment.

The activation RC snapshot is taken at native invocation entry, not on each guest loop iteration. It is incorrect to attribute a loop-dependent regression directly to per-iteration RC without inspecting the actual hot path.

The saved ARM64 disassembly shows two calls to `jit_current_trap_activation` on each normal cancellation poll. Each lookup in these macOS binaries performs two TLV address-resolution calls. Duplicate lookup predates the control migration; migration added branches when selecting the activation-owned control view. This gives a concrete amplified hot-path cost, distinct from the once-per-invocation snapshot. Code placement and ordinary measurement variation can still contribute to the original small differences.

## Reproduction and controls

Unless otherwise noted, timings below are serial local macOS ARM64 runs, 31 retained paired samples after warmup, with balanced alternating order. No build/test workloads overlap retained timings. Intervals resample contiguous blocks of four pairs rather than treating every pair as independent; they describe this run, not all machines.

Repeating the original WAST comparison:

| Workload | Before | After | Paired median change [block-bootstrap interval] |
|---|---:|---:|---:|
| indirect | 251.610 ms | 258.198 ms | +3.99% [+1.93%, +5.72%] |
| gc | 50.096 ms | 50.621 ms | +1.13% [+0.35%, +1.42%] |
| exceptions | 116.007 ms | 116.483 ms | +0.82% [-0.41%, +1.03%] |

A/A control: both labels execute the exact same baseline binary. This exposes host/order variation; it is not a second implementation:

| Workload | Before | After | Paired median change [block-bootstrap interval] |
|---|---:|---:|---:|
| indirect | 243.913 ms | 239.143 ms | -1.03% [-3.49%, -0.22%] |
| gc | 45.946 ms | 46.007 ms | +0.17% [-0.05%, +0.61%] |
| exceptions | 112.659 ms | 113.704 ms | -0.34% [-1.40%, +1.21%] |

The `run` comparison records the invocation phase separately from compilation and setup:

| Workload | Before | After | Paired median change [block-bootstrap interval] |
|---|---:|---:|---:|
| indirect | 126.594 ms | 126.257 ms | -0.07% [-1.57%, +1.22%] |
| gc | 56.565 ms | 55.670 ms | -1.23% [-2.04%, -0.59%] |
| exceptions | 101.576 ms | 98.980 ms | -3.37% [-3.57%, -2.64%] |

These WAT runs reported fresh compilation, not cache hits. The invocation phase excludes the separately recorded compile/setup phases. Their compiler settings differ from WAST, so this comparison alone cannot prove polling is the only cause. Raw phase reports and cache reports are archived; no warm-cache claim is made.

## Controlled fix

On the segment-migration baseline, the only source change in the `poll-after` executable passes the already-resolved control view to the cancellation check. Atomic wait retains its context-taking entry point. The normal cancel-poll path now looks up the activation once instead of twice; cancellation, scheduling, reentry and ownership semantics are unchanged. The saved diff and disassembly verify this mechanism.

This comparison was built and measured before changing function-table allocation:

| Workload | Before | After | Paired median change [block-bootstrap interval] |
|---|---:|---:|---:|
| indirect | 255.742 ms | 199.977 ms | -20.73% [-22.25%, -20.01%] |
| gc | 50.826 ms | 48.330 ms | -5.09% [-5.73%, -4.39%] |
| exceptions | 117.839 ms | 116.865 ms | -0.53% [-1.41%, +0.28%] |

The improvement demonstrates a real repeated-lookup cost, larger than the earlier reported regression in the indirect workload. It does not assign every percentage point of the original small regression to one instruction or rule out placement effects. The definite issue was fixed without undoing activation-local cancellation ownership.

## Function-table migration

MoonBit now constructs a FixedArray of a private external FunctionAddress type and transfers it to the native context. The array is RC-managed; its raw executable-address elements are not RC-managed. C retains the existing void-pointer-array view and finalization decrefs the array. Raw C context construction creates the same external-pointer array representation. Existing code-object owners still keep executable memory alive.

Zero-length tables use the runtime empty external array. Negative counts still yield an invalid/null context; NativeJITContext.try_alloc returns None. Native owner allocation remains recoverable; array allocation follows MoonBit allocator behavior rather than the previous calloc failure behavior.

The local layout probe reports context 352 bytes, generated prefix 128 bytes and function-pointer stride 8 bytes, all unchanged. A nonempty table adds an 8-byte array header; it does not add another table allocation. Generated accesses and artifact format are unchanged. Allocation order changes because MoonBit constructs the table before native owner allocation. Module-shaped context layout is still outstanding.

Final implementation versus the poll-only binary, isolating this subsequent migration as a separate comparison:

| Workload | Before | After | Paired median change [block-bootstrap interval] |
|---|---:|---:|---:|
| indirect | 179.917 ms | 180.125 ms | +0.13% [-0.10%, +0.84%] |
| gc | 42.515 ms | 42.777 ms | +0.61% [+0.34%, +0.80%] |
| exceptions | 102.873 ms | 102.565 ms | -0.11% [-1.22%, +2.53%] |

The first table-migration GC comparison was +0.61% with an interval above zero. A follow-up interleaved randomized A/B and A/A trials for 63 retained pairs per mode: A/B was +0.26% [-0.02%, +0.75%], while identical-binary A/A was +0.10% [-0.48%, +0.98%]. Both intervals cross zero. The small initial difference did not reproduce as a clearly separated effect in this follow-up; that is not proof of exactly zero cost. Both datasets are retained.

## Validation

- 2,619 native tests and 73 ASan/UBSan tests passed.
- Strict MoonBit checks, 38 strict C stub checks and existing lifetime/module-boundary audits passed.
- Core WAST: 258 files and 62,563 assertions per engine.
- Async component WAST: 24 files, 153 commands, no skips.
- New regression checks zero/negative counts, initialized slots, typed/raw allocation, and teardown with deliberately non-RC address values.
- Existing invocation isolation, parked cancellation-capture lifetime, continuation inheritance and blocked atomic-wait cancellation tests remain passing.

Cross-platform CI for this commit is tracked separately. Timing scripts, raw samples, phases, fixtures, assembly, isolated diff, validation logs and executable/source hashes are in [the evidence archive](control-diagnosis-2026-09-29.json.gz).
