# Allocation snapshot experiment

The current VCode input adapter is already non-owning. The remaining ISS-450
boundary still adopts a generic allocation plan and builds VCode transfer records;
ISS-451 still concerns broader compilation storage reuse. Neither is complete.

A bounded candidate replaced internal calls to `instruction_operand_at` and
`value_type(value_at(...))` in `Allocation::for_function_with_storage` with direct
reads of the same package-owned arrays. The public accessors construct owner
handles and complete operand snapshots, although the allocation builder only
needs operand values and value types. No allocation policy or validation was
removed. This candidate was measured and then discarded.

Seven alternating-order pairs per workload followed one warmup pair. Each process
used a unique empty JIT cache; compilation was serial. The baseline executable
was built from runtime/compiler sources at `471b24cc`. Metrics instrumentation was
enabled in both variants. On macOS ARM64:

| Workload | Before median compile | Candidate median compile | Median paired change |
| --- | ---: | ---: | ---: |
| AEGIS-128L | 66,888 us | 65,257 us | -1.17% |
| AEGIS-256 | 66,858 us | 68,950 us | +3.20% |

Per-function code sizes, spill slots, spills, reloads and register moves matched
in every run. Guest output is elapsed time, so equality of stdout is not a
correctness oracle. Paired change is the median of within-pair ratios, not the
ratio of the two independently calculated medians.

The mixed results do not justify a performance claim or retaining the candidate.
They also do not establish that it causes a universal regression: several phases
changed together, consistent with run-to-run noise. The production implementation
is unchanged. The next larger experiment should address the plan/result boundary
or retained compilation storage and must again demonstrate end-to-end benefit.

[Raw paired samples, phase totals, invariants, program/binary hashes and measurement script](allocation-snapshots-2026-09-16.json)
record the complete bounded experiment. This closes ISS-539's measurement task;
ISS-450 and ISS-451 remain open/deferred according to their separate criteria.
