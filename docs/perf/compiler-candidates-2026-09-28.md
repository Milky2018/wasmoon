# Bounded compiler experiments, 2026-09-28

## Decision

Relative to `ae3ca9c8897999bd4989b56fd730c6ffb09ff432`, retain only the instruction-owner scan optimization: skip the second scan only when `args` and `operands` are physically the same array. Preserve all other validation and first-error order.

Conditional jump-threading use counts show a small compiler benefit but are withheld: the combined candidate regresses a real CLI workload, including cache-hit execution where neither changed compiler path runs. Individual CLI probes do not identify the responsible mechanism. Track the unresolved execution sensitivity in [ISS-592](../../issues/ISS-592.md); do not ship the combination based solely on its faster compiler timer.

Reject the per-block prefix-scratch candidate. It reduces allocation but makes complete compilation slower on every workload in both rounds. Its patch and results are retained; no scratch-pooling change is shipped. These experiments do not justify a broad compiler rewrite.

## Protocol and scope

Each candidate was built independently from the same baseline. Each has two fixed rounds of 21 paired, serial, fresh-process compilations on eight inputs; round two reverses candidate and workload order. The two-candidate combination has another two rounds of 21 pairs. There is one uncounted warmup per executable/input/round. No build, test, allocation tracer or other agent workload overlaps timing. All 2,688 timed full-compilation artifacts are byte-identical between versions for each input. Timings include the entire public `compile_module` call; artifact encoding/writing and process teardown are outside that timer. Separate CLI measurements cover command lifetime.

The six existing C/libsodium inputs are supplemented by the MoonBit issue-tracker CLI and a cached Rust WASIp1 directory-reading test program. The latter is a compiler-shape supplement, not a claim about a fresh upstream conformance run or its original build provenance. Exact input/executable hashes, recipes, sample arrays, diagnostic counts and rejected patches are included in the [compressed evidence](compiler-candidates-2026-09-28.json.gz). The supplemental binaries remain at the hash-pinned local paths in that evidence and are not redistributed; reproducing those exact supplemental results requires those inputs. The C inputs are tracked in `examples/algorithms` at the baseline revision.

This is one Apple Silicon machine/toolchain. Pairwise bootstrap intervals are descriptive, pointwise 95% intervals, not a multiple-comparison correction or cross-platform guarantee. Filesystem/code pages are warmed, but compilation is fresh and bypasses JIT artifacts; this is not an empty OS page-cache experiment.

## Independent complete-compilation experiments

Percent changes are candidate/baseline minus one; negative is faster. Each cell shows round 1 / round 2 paired median changes. Full samples and intervals are retained in the evidence.

| Workload | Prefix scratch (rejected) | Owner scan | Conditional use counts |
| --- | ---: | ---: | ---: |
| auth | +0.99% / +1.54% | -0.83% / -0.48% | -0.41% / -0.82% |
| onetimeauth | +1.56% / +1.16% | -0.43% / -1.03% | -0.58% / -1.26% |
| aead_chacha20poly1305 | +0.91% / +1.17% | -0.90% / -1.26% | -0.72% / -1.48% |
| generichash | +1.47% / +2.06% | -1.05% / -0.78% | -0.43% / -0.69% |
| aead_aegis128l | +0.69% / +2.13% | -0.74% / -0.82% | -0.80% / -0.62% |
| xchacha20 | +1.31% / +1.32% | -0.63% / -0.95% | -0.63% / -0.56% |
| derive-tracker | +1.14% / +1.22% | -0.98% / -0.81% | -1.04% / -1.12% |
| p1_fd_readdir | +0.94% / +1.26% | -1.02% / -0.85% | -0.87% / -0.87% |

Prefix scratch regresses in all 16 workload/round comparisons, with every interval above zero. Fewer allocation calls are therefore insufficient grounds to retain it. Generated C has a per-instruction clear/truncation path in place of fresh scratch construction; the exact CPU/code-layout cause of the slowdown was not isolated. No claim that `Array::clear` is intrinsically slower is warranted.

Owner-scan and use-count changes show modest consistent directions, with some individual intervals crossing zero. Their measured percentages must not be added. The subsequent combination experiment and real CLI results decide what can be retained.

## Withheld combination

| Workload | Round 1, 95% interval | Round 2, 95% interval |
| --- | ---: | ---: |
| auth | -1.05% [-1.27, -0.70] | -0.53% [-1.06, -0.20] |
| onetimeauth | -0.79% [-0.99, -0.59] | -0.45% [-1.49, +0.39] |
| aead_chacha20poly1305 | -1.12% [-1.37, -0.98] | -0.56% [-0.90, -0.19] |
| generichash | -0.83% [-1.17, -0.64] | -0.09% [-1.19, +0.48] |
| aead_aegis128l | -0.95% [-1.17, -0.51] | -0.85% [-1.88, -0.13] |
| xchacha20 | -0.77% [-1.14, -0.14] | -0.49% [-0.92, -0.13] |
| derive-tracker | -0.34% [-0.82, +0.07] | -0.91% [-1.85, -0.44] |
| p1_fd_readdir | -0.94% [-1.34, -0.26] | -0.80% [-1.97, +0.08] |

Only four workloads have intervals below zero in both rounds. These small compiler savings do not override the repeated CLI regression below. The combined patch is not shipped.

## Allocation and consumer diagnostics

Allocation probes count requested MoonBit allocation bytes, including object headers, over the whole fixture process. They do not count all native-stub allocations, mapped pages, allocator size-class overhead or stacks. Probe control checks require two allocations totaling 50 bytes, a 50-byte peak, and zero live bytes after freeing both.

Initial captures used variant-specific output paths, producing a few bytes of argument-string differences. They are preserved as `totals.json`; the table uses additional `normalized-totals.json` captures through a fixed executable symlink and fixed artifact path. No timing sample was rerun or replaced by these diagnostics. Ownership-only totals, allocation counts, live bytes and peaks are exactly equal to baseline after normalization.

| Workload | Prefix requested bytes | Use-count requested bytes | Skipped use-count builds / calls |
| --- | ---: | ---: | ---: |
| auth | -0.556% | -0.055% | 54 / 64 |
| onetimeauth | -0.495% | -0.036% | 43 / 53 |
| aead_chacha20poly1305 | -0.481% | -0.033% | 57 / 69 |
| generichash | -0.496% | -0.035% | 39 / 53 |
| aead_aegis128l | -0.579% | -0.053% | 49 / 63 |
| xchacha20 | -0.573% | -0.066% | 75 / 91 |
| derive-tracker | -0.199% | -0.042% | 344 / 409 |
| p1_fd_readdir | -0.499% | -0.055% | 237 / 280 |

The no-consumer ratio counts functions/pass calls, not instructions or time. Every counter-instrumented artifact matches ordinary compilation. Small cumulative allocation reductions do not establish reduced peak memory; all normalized peak-byte counts are exactly unchanged, and process RSS provides no established reduction. No memory-reduction claim is made for the retained owner-scan change.

## Cold CLI and validation

CLI measurements use the six established numeric-output workloads, 21 AB/BA pairs and a fresh artifact-cache directory on every run. Three phase captures plus one detailed compiler capture per executable/input are outside ordinary timing. A repeated regression in the first combination round triggered one fixed second round in reversed workload order; both are retained. No rounds were rerun until favorable. These workloads represent fewer independent compiler shapes than their count suggests; the two supplementary inputs are only part of the compilation experiment.

| Workload | Combination round 1 | Combination round 2 | Final owner-only |
| --- | ---: | ---: | ---: |
| auth | -0.69% [-1.28, +0.28] | -0.34% [-1.02, +0.59] | +0.93% [-0.14, +2.56] |
| onetimeauth | -0.33% [-0.91, +0.09] | -0.64% [-1.62, +0.95] | +1.12% [+0.97, +2.65] |
| aead_chacha20poly1305 | -0.30% [-0.89, +0.27] | -0.45% [-1.71, +0.72] | -0.84% [-1.79, +0.40] |
| generichash | -0.26% [-0.62, -0.10] | -0.26% [-1.62, +0.19] | -0.36% [-0.70, +0.51] |
| aead_aegis128l | +0.71% [+0.60, +1.13] | +1.11% [+0.81, +1.30] | -0.10% [-0.31, +0.32] |
| xchacha20 | -0.21% [-0.28, -0.02] | -0.23% [-0.71, +0.36] | -0.31% [-0.73, -0.07] |

`aead_aegis128l` regresses in both combination rounds (+0.71%, +1.11%). In the first round's separate phase captures, median compilation drops from 51.267 to 51.046 ms, while invocation rises from 700.211 to 705.576 ms. A fixed 21-pair cache-hit diagnostic retains +0.51% wall [+0.36, +1.24] and +0.56% invocation [+0.36, +1.19], with identical cached artifacts and no compilation. This rules out allocation performed during that run's compilation as the direct explanation. It does not prove an address-layout, scheduling, workload, or host-call mechanism.

Follow-up single-workload CLI probes:

| Probe | Paired wall change, 95% interval |
| --- | ---: |
| Owner only | -0.11% [-1.21, +1.20] |
| Use counts only | +0.37% [-0.08, +1.25] |
| Identical baseline binary A/A | -0.19% [-0.95, +0.40] |

The A/A interval crosses zero; it does not demonstrate a fixed label/order bias. Individual candidate intervals also cross zero and do not identify which source change causes the combined effect. The conservative decision is to withhold conditional use counts and validate owner-only across the full six-workload CLI group. The final owner-only CLI group also includes a +1.12% interval-above-zero result for `onetimeauth`. This triggered one fixed 21-pair repeat of `onetimeauth` and `auth` (the other short case with a positive point estimate), without replacing the original group. The repeat is +0.02% [-1.14, +1.08] for `onetimeauth` and -0.51% [-1.45, +0.24] for `auth`: the observed slowdown did not repeat, but this is not proof of a general CLI improvement. Retain owner scanning on its two-round complete-compilation evidence and unchanged ownership contract, with this limitation explicit. No end-to-end speedup or peak-RSS reduction is claimed for the shipped change.


Validation: `moon info`, `moon fmt`, warning-denied native check and all 2,586 native tests pass. Existing malformed-owner tests cover foreign values in either distinct argument array, foreign results and foreign instruction ownership. A fresh `install.sh` build passes 258/258 core WAST files in each engine (62,563 assertions per engine). The pinned Wasmtime misc runner reports 676 passes, zero failures/timeouts/unsupported/harness errors, 72 script-only entries and 16 existing deferred entries. These explicit suite exclusions are unchanged. The install uses a fresh build directory, separate from the ordinary release timing builds; both executable hashes are retained. The final production diff touches only `milkir/ir.mbt`; public interfaces, jump threading and prefix scratch remain unchanged.
