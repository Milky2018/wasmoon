# T8 Constant/Mask Materialization Measurement

- Base commit measured: cdf6a50
- Branch: milky/optimization-jit-closure

## Runtime (5-run median)
- AEAD: Wasmoon 2.98s vs Wasmtime 0.75s => 3.9733x
- Benchmark: Wasmoon 0.25s vs Wasmtime 0.28s => 0.8929x

## Compile-profile delta vs T7
- module_compile_us: 2181088 -> 2166947 (-0.65%)
- regalloc_us_total: 1646744 -> 1633414 (-0.81%)
- optimize_us_total: 187838 -> 187177 (-0.35%)
- lower_us_total: 316576 -> 315636 (-0.30%)
- emit_us_total: 26085 -> 26892 (3.09%)
- hot func_56 regalloc_us: 1517050 -> 1501794 (-1.01%)

## Raw files
- `wasmoon_aead_times.txt`
- `wasmtime_aead_times.txt`
- `wasmoon_benchmark_times.txt`
- `wasmtime_benchmark_times.txt`
- `wasmoon_aead_perf.json`
- `wasmoon_aead_stdout.txt`
