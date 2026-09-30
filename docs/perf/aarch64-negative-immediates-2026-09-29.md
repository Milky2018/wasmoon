# AArch64 negative immediates and memory-base policy review

## Scope

Baseline: `ece1aa8c09f6c1ed3d2d123144f54c9d624685fd`, native macOS ARM64.
Only AArch64 direct arithmetic-immediate selection changes. There is no new
register reservation, memory-base reuse rule, optimization budget, dependency,
or public API. Tracking: [ISS-594](../../issues/ISS-594.md).

## Bounded instruction-selection improvement

For i32 `x + (-64)`, the baseline constructs `0xffffffc0` with MOV/MOVK and
uses register ADD. The candidate selects SUB immediate. The arithmetic and RET
sequence shrinks from 16 bytes to 8 bytes. Subtracting a negative constant
similarly selects ADD immediate. Modular negation uses the operand width;
unencodable magnitudes retain the existing register-form fallback. Existing
positive immediate encodings take precedence. No comparison/flags-producing
operation or constant-left subtraction is rewritten by this target rule.

The direct-selection regression failed on the baseline with 16 bytes instead
of 8, then passed after the change. It checks exact machine words for both
widths, both operation directions, ordinary and shifted immediates, the maximum
shifted magnitude, and positive controls. Fallback controls include -4097 and
signed minima. The interpreter/JIT regression makes 56 comparisons covering
shared constants, both operand orders, and zero, negative and signed-boundary
inputs; parameters prevent folding away all arithmetic.

## Real-function code comparison

The same before/after CLI builds were used for target exploration:

| Workload/function | Before bytes | After bytes | Base loads before/after |
| --- | ---: | ---: | ---: |
| scrypt_ll / 37 | 4072 | 4056 | 66 / 66 |
| scrypt_ll / 41 | 1780 | 1752 | 58 / 58 |
| scrypt_ll / 42 | 916 | 916 | 17 / 17 |
| scrypt_ll / 43 | 3448 | 3432 | 50 / 50 |
| AEGIS-128L / 30 | 1328 | 1288 | 23 / 23 |
| onetimeauth / 50 | 14660 | 14644 | 167 / 167 |

The rule changes allocator input, so allocation edits need not remain identical.
In scrypt function 41, printed instruction reload edits increase from 58 to 59
while total emitted code falls by 28 bytes. These printed edit counts exclude
edge-transfer accounting; they are not substituted for full module metrics.
Code size and base-load counts alone are not runtime-speed measurements.

## Memory-base decision: preserve the existing policy

The preceding performance investigation observed repeated base loads, but
load count alone is not evidence that removing them improves execution.
Historical experiments explicitly rejected the broader reuse strategy:

| Historical experiment | Base loads | Spills/reloads | Decision |
| --- | ---: | ---: | --- |
| ISS-259 original bounded reuse | 40 | 8/10 | Baseline |
| ISS-259 distance 32, three reuses | 16 | 12/14 | Rejected |
| ISS-259 distance 16, one reuse | 30 | 8/10 | Retained |
| ISS-433 before change | 41 | 11/12 | Baseline |
| ISS-433 unbounded stable-global reuse | 1 | 17/19 | Rejected |
| ISS-433 distance 16, one reuse | 23 | 12/12 | Retained |

These are the dated records in [ISS-259](../../issues/ISS-259.md) and
[ISS-433](../../issues/ISS-433.md), not new measurements on today's compiler.
ISS-433 records seven cold-cache pairs: unbounded reuse worsened the AEGIS
median guest ratio against its then-current Wasmtime from 1.248 to 1.634;
bounded reuse measured 1.093. Do not combine these historical ratios with the
Wasmtime 49.0.1 comparison.

The unbounded experiment kept an ordinary virtual value live across the whole
function. It was not a direct experiment reserving one fixed physical register.
A dedicated register would additionally remove that register from allocation
for other values; the project explicitly prohibits adding such a heap-base
reservation in those issues. Historical evidence therefore establishes a real
live-range pressure problem, rather than proving that every possible dedicated
register design was benchmarked.

Current source still enforces the decision:

- `milkir/optimize/internal/acyclic/gvn.mbt` uses a post-budget stable-global
  reuse distance of 16 and a reuse limit of one, introduced by `7516a11b`.
  Cheap GVN continues beyond the memory precision budget; it does not simply
  stop optimizing the remainder of a large function.
- `milkir/optimize/global_value_gvn_wbtest.mbt` tests bounded reuse after budget
  exhaustion and invalidation of mutable fields after unknown stores/calls.
- `milkir/native/lower.mbt` emits an ordinary EnvironmentField value.
  `aarch64_target/direct_lower.mbt` selects a ScalarLoad with `Input::any` and
  `Output::any`; it does not pin the base to a physical register.
- `aarch64_target/allocation.mbt` reserves ABI/scratch roles but no dedicated
  heap-base register. The context pointer and the loaded linear-memory base
  are distinct values.

Decision: retain this policy. A future change needs controlled evidence that
local reuse or rematerialization reduces total hot-path cost without increasing
harmful spilling, plus pressure-sensitive AEGIS/BLAKE2b/Salsa controls. Neither
"58 loads" nor "Wasmtime loads once" is sufficient justification by itself.

## Fixed before/after CLI diagnostic

Seven paired cold-cache runs per workload, alternating build order, plus one
retained warmup pair each. No build, test, or profiler from this task overlapped
timing. Other desktop tasks were not controlled, so these are diagnostic
samples, not an isolated-machine performance acceptance. No sample was removed.
The inputs and executable hashes, all 48 runs, runner source, code exploration,
and candidate production patch are retained in the [compressed evidence](aarch64-negative-immediates-2026-09-29.json.gz).

Positive paired change means slower. Intervals are fixed-seed paired bootstrap
intervals and do not remove host-load confounding or multiple-comparison risk.

| Workload | Median paired wall change | 95% interval |
| --- | ---: | ---: |
| onetimeauth | -1.82% | [-2.14%, -0.28%] |
| aead_aegis128l | +0.61% | [-2.10%, +1.44%] |
| pwhash_scrypt_ll | +0.68% | [-1.73%, +2.57%] |

The short onetimeauth sample supports a small local improvement. AEGIS and
scrypt intervals include both improvements and regressions; this experiment
does not establish a general execution speedup or prove zero regression. The
change is retained as a bounded instruction-selection improvement with verified
semantic behavior and smaller real-function code. No additional rounds were
used to seek a favorable result. ISS-592 remains unresolved.

## Validation

- The initial exact-code regression failed with 16 bytes instead of 8; the
  implemented selector passes all 14 direct-selection cases.
- Generated interfaces are unchanged; formatting and warning-denied native
  checking pass.
- All 2,595 native tests pass, including the 56 new interpreter/JIT comparisons.
- A fresh installed CLI passes all 258 core WAST files and 62,563 assertions per
  engine, with zero failures.
- All 48 warmup/measured CLI executions pass fresh-cache evidence checks.
- Native execution was tested on ARM64. No native x64 performance result is
  claimed; x64 selection was not changed.
