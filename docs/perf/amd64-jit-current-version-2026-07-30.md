# AMD64 JIT Current-Version Compile Trend

This report supplies the native Linux AMD64 evidence required by ISS-212. It
records current-version compile time and emitted size only; it does not compare
against the deleted legacy backend and is not a CI performance threshold.

## Provenance

| Item | Value |
| --- | --- |
| Wasmoon commit | `2fd4e5c3dab8bd5f0d6eb25e2088d49509d57615` |
| CI run | `30548552945` |
| Artifact | `amd64-current-version-compile-trend` |
| Host | GitHub Actions Linux AMD64, `x86_64` |
| OS | Ubuntu runner, Linux 6.17.0-1020-azure |
| MoonBit | `moon 0.1.20260724 (5f1406a 2026-07-24)` |
| MoonBit compiler | `moonc v0.10.5+5e7afb0c0 (2026-07-27)` |
| Python | 3.12.3 |
| Benchmark shape | one warmup, three measured compilations |
| Timeout | 180 seconds per invocation |

The runner enabled `WASMOON_PERF_METRICS` for every invocation. Each reported
`module_compile_us` therefore comes from a fresh current-version JIT
compilation rather than an artifact-cache hit.

## Summary

All five retained workloads completed every warmup and measured invocation
with exit code zero.

| Workload | Mode | Compile median | Wall median | Emitted code |
| --- | --- | ---: | ---: | ---: |
| `examples/benchmark.wasm` | run | 2,678 us | 514 ms | 910 B |
| `examples/algorithms/aead_aegis128l.wasm` | run | 2,961,756 us | 5,877 ms | 173,140 B |
| `spec/const.wast` | test | 101 us | 314 ms | 16 B |
| `spec/int_exprs.wast` | test | 291 us | 31 ms | 134 B |
| `spec/float_exprs.wast` | test | 347 us | 214 ms | 147 B |

The wall measurements include CLI startup, parsing, validation, compilation,
instantiation, and guest execution or assertions. They are retained for
provenance and must not be interpreted as compile time.

## Raw Samples

| Workload | Sample | Wall | Compile | Code |
| --- | --- | ---: | ---: | ---: |
| `benchmark.wasm` | warmup | 515 ms | 2,869 us | 910 B |
| `benchmark.wasm` | run 0 | 514 ms | 2,643 us | 910 B |
| `benchmark.wasm` | run 1 | 515 ms | 4,159 us | 910 B |
| `benchmark.wasm` | run 2 | 465 ms | 2,678 us | 910 B |
| `aead_aegis128l.wasm` | warmup | 5,731 ms | 2,909,839 us | 173,140 B |
| `aead_aegis128l.wasm` | run 0 | 5,829 ms | 2,975,019 us | 173,140 B |
| `aead_aegis128l.wasm` | run 1 | 5,877 ms | 2,961,756 us | 173,140 B |
| `aead_aegis128l.wasm` | run 2 | 5,880 ms | 2,958,598 us | 173,140 B |
| `const.wast` | warmup | 565 ms | 114 us | 16 B |
| `const.wast` | run 0 | 314 ms | 110 us | 16 B |
| `const.wast` | run 1 | 264 ms | 97 us | 16 B |
| `const.wast` | run 2 | 715 ms | 101 us | 16 B |
| `int_exprs.wast` | warmup | 31 ms | 303 us | 134 B |
| `int_exprs.wast` | run 0 | 114 ms | 264 us | 134 B |
| `int_exprs.wast` | run 1 | 31 ms | 346 us | 134 B |
| `int_exprs.wast` | run 2 | 15 ms | 291 us | 134 B |
| `float_exprs.wast` | warmup | 114 ms | 376 us | 147 B |
| `float_exprs.wast` | run 0 | 214 ms | 364 us | 147 B |
| `float_exprs.wast` | run 1 | 164 ms | 347 us | 147 B |
| `float_exprs.wast` | run 2 | 314 ms | 340 us | 147 B |

The stable code-size values across all four samples provide a deterministic
secondary signal that the same current backend configuration was measured.

## Interpretation

The small workloads retain a low-hundreds-of-microseconds compiler trend, while
AEGIS128L exposes a roughly three-second current AMD64 compile path. The report
does not define an arbitrary pass/fail ratio; it gives future work a native
AMD64 baseline with exact source, toolchain, corpus, and raw samples.

An earlier diagnostic attempt also completed compilation for `core3.wasm` and
`pwhash_scrypt_ll.wasm`, but both subsequently trapped in the AMD64 JIT at the
same machine-code offset. Those executions are excluded from the successful
trend table and tracked as the P0 correctness issue ISS-365. Their compile
metrics are not used to hide or downgrade the runtime defect.

## Reproduction

The retained commands were:

```sh
python3 scripts/run_perf_benchmarks.py \
  --wasmoon ./wasmoon \
  --out-dir target/amd64-compile-trend-run \
  --iterations 3 \
  --warmup 1 \
  --timeout-sec 180 \
  --workload examples/benchmark.wasm \
  --workload examples/algorithms/aead_aegis128l.wasm

python3 scripts/run_perf_benchmarks.py \
  --wasmoon ./wasmoon \
  --out-dir target/amd64-compile-trend-test \
  --subcommand test \
  --iterations 3 \
  --warmup 1 \
  --timeout-sec 180 \
  --workload spec/const.wast \
  --workload spec/int_exprs.wast \
  --workload spec/float_exprs.wast
```

Together with
`docs/perf/aarch64-jit-current-version-2026-07-23.md`, this provides retained
current-version compile evidence for both supported native targets.
