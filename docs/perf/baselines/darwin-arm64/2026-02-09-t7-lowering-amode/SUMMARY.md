# T7 Lowering/AMode Measurement

- Base commit measured: cdf6a50
- Branch: milky/optimization-jit-closure

## Runtime (5-run median)
- AEAD: Wasmoon 2.99s vs Wasmtime 0.75s => 3.9867x
- Benchmark: Wasmoon 0.25s vs Wasmtime 0.28s => 0.8929x

## Compile-profile delta vs T6
- module_compile_us: 2090723 -> 2181088 (4.32%)
- regalloc_us_total: 1581312 -> 1646744 (4.14%)
- optimize_us_total: 176581 -> 187838 (6.37%)
- lower_us_total: 307445 -> 316576 (2.97%)
- emit_us_total: 22238 -> 26085 (17.30%)
- hot func_56 regalloc_us: 1459932 -> 1517050 (3.91%)

## Raw files
- `wasmoon_aead_times.txt`
- `wasmtime_aead_times.txt`
- `wasmoon_benchmark_times.txt`
- `wasmtime_benchmark_times.txt`
- `wasmoon_aead_perf.json`
- `wasmoon_aead_stdout.txt`
