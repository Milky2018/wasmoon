# T9 Runtime Init Path Measurement

- Base commit measured: aec1432
- Branch: milky/optimization-jit-closure

## Runtime (5-run median)
- AEAD: Wasmoon 2.93s vs Wasmtime 0.74s => 3.9595x
- Benchmark: Wasmoon 0.25s vs Wasmtime 0.28s => 0.8929x

## Compile-profile delta vs T8
- module_compile_us: 2166947 -> 2124649 (-1.95%)
- regalloc_us_total: 1633414 -> 1599498 (-2.08%)
- optimize_us_total: 187177 -> 183530 (-1.95%)
- lower_us_total: 315636 -> 313681 (-0.62%)
- emit_us_total: 26892 -> 24075 (-10.48%)
- hot func_56 regalloc_us: 1501794 -> 1474094 (-1.84%)

## Raw files
- `wasmoon_aead_times.txt`
- `wasmtime_aead_times.txt`
- `wasmoon_benchmark_times.txt`
- `wasmtime_benchmark_times.txt`
- `wasmoon_aead_perf.json`
- `wasmoon_aead_stdout.txt`
