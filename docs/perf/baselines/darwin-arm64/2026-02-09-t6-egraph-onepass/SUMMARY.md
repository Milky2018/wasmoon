# T6 EGraph Scheduling/Bounds Measurement

- Base commit measured: 1672442
- Branch: milky/optimization-jit-closure

## Runtime (5-run median)
- AEAD: Wasmoon 2.90s vs Wasmtime 0.74s => 3.9189x
- Benchmark: Wasmoon 0.25s vs Wasmtime 0.28s => 0.8929x

## Compile-profile delta vs T5
- module_compile_us: 2242089 -> 2090723 (-6.75%)
- regalloc_us_total: 1532695 -> 1581312 (+3.17%)
- optimize_us_total: 380838 -> 176581 (-53.63%)
- lower_us_total: 302691 -> 307445 (+1.57%)
- emit_us_total: 22610 -> 22238 (-1.65%)
- hot func_56 regalloc_us: 1413289 -> 1459932 (+3.30%)

## Raw files
- `wasmoon_aead_times.txt`
- `wasmtime_aead_times.txt`
- `wasmoon_benchmark_times.txt`
- `wasmtime_benchmark_times.txt`
- `wasmoon_aead_perf.json`
- `wasmoon_aead_stdout.txt`
