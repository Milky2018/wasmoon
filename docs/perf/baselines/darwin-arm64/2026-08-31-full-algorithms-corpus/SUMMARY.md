# Full Algorithms Corpus Sweep History

This snapshot records the first full cold-cache corpus check after the recent
AEGIS-focused compiler work. It is retained as test history because the result
shows why a single-workload improvement is not sufficient evidence of general
compiler improvement.

## Provenance

| Item | Value |
|---|---|
| Report timestamp (UTC) | `2026-08-31T13:17:53Z` |
| Report timestamp (Asia/Shanghai) | `2026-08-31T21:17:53+08:00` |
| Source commit tested | `4fb81da08b1899dff5ee9b6d1ff40d4e7da5da66` |
| Branch | `dev` |
| Host | Apple Silicon, `arm64`, Darwin `25.5.0`, macOS `26.5.2` (`25F84`) |
| Wasmoon | `0.12.6` |
| Wasmtime | `40.0.0` (`68a6afd4f`, 2025-11-22) |
| Workloads | All 70 `examples/algorithms/*.wasm` workloads selected by the runner |
| Runner schema | `3` |

The source report was generated with:

```bash
python3 scripts/benchmark_algorithms_parity.py \
  --wasmoon ./wasmoon \
  --wasmtime wasmtime \
  --summary-file _build/algorithms-corpus-sweep.ZxxFyr/summary.json \
  --markdown-file _build/algorithms-corpus-sweep.ZxxFyr/summary.md
```

The committed JSON preserves every workload, command, output, duration, cache
observation, and ratio from the generated report. Machine-specific temporary
paths were replaced mechanically with `<sweep-artifacts>`; no measurements or
statuses were changed.

Raw generated artifact checksums before path sanitization:

| Artifact | SHA-256 |
|---|---|
| `summary.json` | `be530fe896d4c7f8c2515c27ffb40a1db701f4252156be88a3493a26a66fc46d` |
| `summary.md` | `3f2d5d85c23e733683572bab1f101b0ff669b7e1e01942be1a064e3c894c31c6` |

## Method

> Historical comparability note: this snapshot allowed Wasmtime's default
> parallel function compilation. It remains valid as the recorded observation
> at the timestamp above, but its cold wall ratios are not directly comparable
> with future corpus sweeps. The corpus runner now requires
> `-C parallel-compilation=n` so both compiler measurements use serial function
> compilation.

- Each engine was invoked once per workload, with no warmup.
- Wasmoon and Wasmtime used separate cold caches for every workload.
- Engine order alternated by workload.
- The timeout was 300 seconds per invocation.
- A guest-value ratio above `1.05` or a process-wall ratio above `2.0` was
  classified as a performance gap. Both ratios are `Wasmoon / Wasmtime`, so a
  value above one favors Wasmtime.
- This is a screening sweep and historical checkpoint, not a statistically
  stable benchmark: one sample does not quantify variance, and some workloads
  use randomized inputs.

## Result

| Metric | Result |
|---|---:|
| Workloads completed | 70 / 70 |
| Engine invocations exiting zero | 140 / 140 |
| Timeouts | 0 |
| Invocations with non-empty stderr | 0 |
| Fresh Wasmoon compilations observed | 70 / 70 |
| Fresh Wasmtime compilations observed | 70 / 70 |
| Workloads below both gap thresholds | 39 |
| Workloads classified as performance gaps | 31 |
| Guest-value gaps | 11 |
| Process-wall gaps | 26 |
| Workloads in both gap sets | 6 |

Corpus aggregates:

| Metric | Result |
|---|---:|
| Guest-value ratio geometric mean | 0.8939 |
| Guest-value ratio median | 0.9640 |
| Process-wall ratio geometric mean | 1.5560 |
| Process-wall ratio median | 1.2946 |
| Total Wasmoon process wall time | 957.955 s |
| Total Wasmtime process wall time | 972.948 s |
| Ratio of aggregate wall totals | 0.9846 |

The aggregate wall total is dominated by a few long-running workloads and
therefore hides the fixed-cost gap visible in the equal-workload geometric
mean. Both summaries are recorded; neither should be used alone.

### AEGIS-128L checkpoint

| Metric | Wasmoon | Wasmtime | Ratio |
|---|---:|---:|---:|
| Guest-reported value | 3,942,350,000 | 3,805,905,000 | 1.0359 |
| Process wall | 0.8726 s | 0.7823 s | 1.1154 |

AEGIS-128L is below both configured gap thresholds, but 31 other corpus
workloads are not. In particular, 11 workloads still exceed the guest-value
threshold and 26 exceed the cold process-wall threshold. This demonstrates
that AEGIS-only success does not establish corpus-wide performance health and
that using AEGIS as the sole optimization target creates a substantial
overfitting risk.

This snapshot does **not** prove that each earlier optimization caused a corpus
regression: it has no matching pre-change, full-corpus sample. It does prove
that the single AEGIS result was an inadequate acceptance gate. Future
compiler-performance work should keep focused benchmarks for diagnosis, but
must also compare an unchanged-output, cold-cache corpus checkpoint before a
general improvement is claimed.

## Artifacts

- `wasmtime-parity-summary.json`: complete machine-readable report with
  temporary paths sanitized.
- `wasmtime-parity-summary.md`: complete generated workload table and gap list,
  with artifact paths updated for this snapshot.
