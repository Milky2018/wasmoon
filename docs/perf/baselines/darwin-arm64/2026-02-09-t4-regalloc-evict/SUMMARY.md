# T4 Regalloc Eviction Alignment Measurement

- Base commit measured: e5a8e97
- Branch: milky/optimization-jit-closure

## Runtime (5-run median)
- AEAD: Wasmoon 3.09s vs Wasmtime 0.74s => 4.1757x
- Benchmark: Wasmoon 0.25s vs Wasmtime 0.28s => 0.8929x

## Compile-profile delta vs T3
- module_compile_us: 2347776 -> 2265912 (-3.49%)
- regalloc_us_total: 1614310 -> 1551624 (-3.88%)
- optimize_us_total: 391229 -> 379200 (-3.07%)
- lower_us_total: 312714 -> 307208 (-1.76%)
- emit_us_total: 25754 -> 24350 (-5.45%)

## Hot function focus (func_56)
- regalloc_us: 1488177 -> 1427085 (-4.11%)
- spills: 148 -> 148
- reloads: 676 -> 676

## Raw files
- `wasmoon_aead_times.txt`
- `wasmtime_aead_times.txt`
- `wasmoon_benchmark_times.txt`
- `wasmtime_benchmark_times.txt`
- `wasmoon_aead_perf.json`
