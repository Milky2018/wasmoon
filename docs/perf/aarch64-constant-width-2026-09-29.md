# AArch64 zero-extended constants and shared comparison matching

Baseline: `17e9ad4d51f0ab073e1feebca0752aca8a17abc5`, native macOS ARM64.
Tracking: [ISS-597](../../issues/ISS-597.md).

## Changes

The AArch64 constant emitter selects W-register instructions when all upper
32 bits are zero, including i64 results. Architectural zero extension preserves
the full result. Constants requiring upper bits retain X-register instructions.
The existing MOVZ/MOVN/MOVK and logical-immediate cost choice then runs at the
selected width.

Native value and branch comparison selection share one operand matcher and
condition reversal implementation. Branches preserve their existing immediate
materialization fallback; value comparisons still require target eligibility.
This is code reuse, not a claimed execution optimization. There is no ISLE,
new public API, register reservation, or memory-base policy change.

## Exact generated-code comparison

Each standalone function returns the specified i64 constant. Sizes include RET.

| Constant | Before bytes | After bytes | Result |
| --- | ---: | ---: | --- |
| `0x00000000ffff1234` | 12 | 8 | Two MOV-wide instructions become one W MOVN |
| `0x0000000000ff00ff` | 12 | 8 | Two MOV-wide instructions become one W ORR |
| `0x00000000ffffffc0` | 8 | 8 | One X ORR becomes one W MOVN; no size saving |
| `0x0000000012345678` | 12 | 12 | Still two instructions |
| `0x00000000ffffffff` | 8 | 8 | Still one instruction |
| `0x0000000100000000` | 8 | 8 | X-register control |
| `0xffffffffffff1234` | 8 | 8 | Negative X-register control |

The encoding regression fails on the baseline and passes with the change.
Independent clang assembly matches the asserted machine words. One existing
stack-address snapshot changes a MOVZ opcode from X to W for a zero-extended
offset; the resulting address is unchanged.

## Real modules

All functions were explored, rather than selecting only a favorable function.
These totals sum emitted function code, not serialized artifact sizes.

| Module | Before bytes | After bytes | Changed-size function |
| --- | ---: | ---: | --- |
| onetimeauth | 39,568 | 39,560 | 12: 1392 -> 1384 |
| aead_aegis128l | 57,568 | 57,560 | 16: 1392 -> 1384 |
| pwhash_scrypt_ll | 49,928 | 49,920 | 14: 1392 -> 1384 |

Complete allocated-VCode output is byte-identical before and after for all
three modules. The comparison refactor therefore preserves instruction selection
and register allocation for these samples. Size savings occur during emission;
the previously inspected algorithm kernels do not shrink.

## Measurement method

The immutable before/after CLI binaries run serially, alternating pair order.
Each module receives one warmup pair and seven recorded cold pairs. Every run
uses an isolated artifact cache and verifies fresh compilation. No builds or
tests run concurrently with measurements. All samples, including warmups, are
retained. A separate fixed seven-pair onetimeauth phase run examines compiler
cost without substituting instrumented timings for the plain measurements.
The host is not isolated from user applications; confidence intervals quantify
sample variability and do not prove causality. Negative changes mean faster.

## Timing results

| Workload | Before median ms | After median ms | Median paired change | Paired 95% bootstrap interval |
| --- | ---: | ---: | ---: | --- |
| onetimeauth | 47.025 | 47.099 | +1.27% | [-2.25%, +5.83%] |
| aead_aegis128l | 794.338 | 786.323 | +0.20% | [-2.52%, +0.61%] |
| pwhash_scrypt_ll | 9517.547 | 9073.903 | -0.78% | [-2.77%, +0.78%] |

The paired statistic is the median of per-pair percentage changes, not the
percentage change between the two independently computed medians. Host drift
can make those statistics differ, including their signs. All three paired
intervals cross zero; these measurements establish neither a speedup nor a
slowdown. Guest-reported metric intervals also cross zero for all three modules.

Onetimeauth's separately instrumented compile medians are 38.427 -> 38.839 ms;
paired change +0.99%, interval [-3.10%, +1.89%]. This does not establish compiler
cost improvement or regression. No further timing repetitions were selected to
obtain a favorable result. The local code reduction and removal of duplicated
comparison matching are the grounds for retaining this change.

## Validation and evidence

- `moon info`, `moon fmt`, and strict native check including warning 73 pass;
  generated public interfaces are unchanged.
- All 2,605 native tests pass, including shared constants across value/branch
  comparisons, constant-left branch fallback and upper-bit controls.
- Fresh CLI core WAST: both engines pass 258/258 files and 62,563 assertions each.
- All 64 workload executions (including warmups and phase samples) succeed and
  verify fresh compilation.

[aarch64-constant-width-2026-09-29.json.gz](aarch64-constant-width-2026-09-29.json.gz)
contains all samples, input/binary hashes, exact commands, process snapshots,
phase measurements, the source patch, runners, assembly fixture and complete
before/after code-object and allocated-VCode output. Executables remain in
`target/constant-width-597/` locally and are identified by SHA-256 in the record.
