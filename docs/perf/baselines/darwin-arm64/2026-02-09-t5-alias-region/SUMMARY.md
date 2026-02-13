# T5 Alias Region Precision Measurement

- Base commit measured: 0e12344
- Branch: milky/optimization-jit-closure

## Runtime (5-run median)
- AEAD: Wasmoon 3.12s vs Wasmtime 0.74s => 4.2162x
- Benchmark: Wasmoon 0.25s vs Wasmtime 0.28s => 0.8929x

## Compile-profile delta vs T4
- module_compile_us: 2265912 -> 2242089 (-1.05%)
- regalloc_us_total: 1551624 -> 1532695 (-1.22%)
- optimize_us_total: 379200 -> 380838 (+0.43%)
- lower_us_total: 307208 -> 302691 (-1.47%)
- emit_us_total: 24350 -> 22610 (-7.15%)

## Hot function focus (func_56)
- regalloc_us: 1427085 -> 1413289 (-0.97%)
- spills: 148 -> 148
- reloads: 676 -> 676

## Raw files
- `wasmoon_aead_times.txt`
- `wasmtime_aead_times.txt`
- `wasmoon_benchmark_times.txt`
- `wasmtime_benchmark_times.txt`
- `wasmoon_aead_perf.json`
- `wasmoon_aead_stdout.txt`
