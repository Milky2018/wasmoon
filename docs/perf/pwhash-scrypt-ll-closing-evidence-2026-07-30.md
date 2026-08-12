# `pwhash_scrypt_ll` Closing Evidence

> Historical methodology: this report measured cached execution after a
> warmup. New corpus sweeps must clear separate Wasmoon and Wasmtime caches per
> workload and invoke each engine exactly once, with no warmup or repeated
> aggregation.

This report closes the performance evidence required by ISS-266. It complements
the complete 70-workload matrix in
`docs/perf/algorithms-single-run-2026-07-24.md` with a current cached execution
pair, a fresh compilation trace, and final assembly metrics for the four
functions identified by ISS-261.

Ratios are Wasmoon divided by Wasmtime. Each runtime comparison below is one
direct measured pair after one warmup; it is not a median or average.

## Provenance

| Item | Value |
| --- | --- |
| Wasmoon commit | `ab7156330ca53f6a56b05c818c9ad59b2b700a13` |
| Host | Apple Silicon, `arm64`, `ARM64_T6031` |
| OS | Darwin 25.5.0, macOS arm64 |
| MoonBit | `moon 0.1.20260729 (55ee69c 2026-07-29)` |
| Wasmtime | `wasmtime 40.0.0 (68a6afd4f 2025-11-22)` |
| Benchmark shape | one warmup, one measured pair |
| Wasmoon cache | isolated; measured execution reused the warmup artifact |
| Compile metrics | schema v3, detailed per-function metrics enabled |

The cached execution pair produced:

| Measurement | Wasmoon | Wasmtime | Ratio |
| --- | ---: | ---: | ---: |
| Guest-reported value | 44,171,210,000 | 40,747,150,000 | 1.084032 |
| Process wall time | 8.840059 s | 8.157637 s | 1.083654 |

The measured pair performed zero fresh Wasmoon compilations. A separate run
with `WASMOON_PERF_METRICS=1` and `WASMOON_PERF_METRICS_DETAIL=1` compiled all
56 functions in 1,269,527 microseconds and emitted 54,488 bytes. This keeps the
compile cost separate from the cached runtime comparison.

## Assembly Evidence

The baseline values are the pre-fix measurements retained by ISS-261 through
ISS-265. Final values come from `explore --stage allocated-vcode` and the
schema-v3 compile metrics at the commit above. AArch64 machine instruction
counts are code bytes divided by four.

| Function | Baseline | Final |
| --- | --- | --- |
| `func_37` | 76 memory-base loads | 62 memory-base loads; 3,928 bytes / 982 machine instructions; 14 spills, 37 reloads |
| `func_41` | 72 memory-base loads; 13 spills, 56 reloads | 4 memory-base loads; 1,424 bytes / 356 machine instructions; 12 spills, 57 reloads |
| `func_42` | 24 memory-base loads; arithmetic loop: 126 instructions and 27 stack accesses | 1 memory-base load; 996 bytes / 249 machine instructions; arithmetic loop: 98 instructions and zero allocator spill/reload edits |
| `func_43` | 66 memory-base loads; 3,860 bytes / 965 machine instructions; 128 non-call branches | 66 memory-base loads; 3,668 bytes / 917 machine instructions; 85 non-call branches; 32 spills, 98 reloads |

`func_42` also has no stack-to-stack continuation-edge move. The final
`func_43` branch count is retained from the closing evidence for ISS-265; the
current code size remains within two instructions of that closing snapshot
despite later unrelated runtime work.

## Reproduction

The runtime pair used:

```sh
python3 scripts/benchmark_algorithms_parity.py \
  --wasmoon ./wasmoon \
  --wasmtime wasmtime \
  --workloads-dir <directory-containing-only-pwhash_scrypt_ll.wasm> \
  --summary-file /tmp/pwhash-current-summary.json \
  --markdown-file /tmp/pwhash-current-summary.md \
  --iterations 1 \
  --warmup 1 \
  --timeout-sec 300 \
  --value-ratio-threshold 1.15 \
  --wall-ratio-threshold 1.20
```

The assembly and compile records used:

```sh
./wasmoon explore examples/algorithms/pwhash_scrypt_ll.wasm \
  --stage allocated-vcode

WASMOON_PERF_METRICS=1 \
WASMOON_PERF_METRICS_DETAIL=1 \
WASMOON_PERF_METRICS_FILE=/tmp/pwhash-current-metrics.json \
./wasmoon run examples/algorithms/pwhash_scrypt_ll.wasm
```

## Residual Work

The complete 70-workload matrix records every direct ratio. Its two remaining
threshold exceedances are `aead_aegis128l` and `aead_aegis256`; ISS-364 tracks
that residual parity work independently of the completed Scrypt optimization.
The `onetimeauth2` value ratio remains unavailable because both engines
reported zero guest ticks, while its valid wall ratio is retained in the
matrix.
