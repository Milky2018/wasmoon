# Baseline Lock (2026-02-09, darwin-arm64)

## Revisions
- Wasmoon: `e45fec3` (branch `main` at capture time)
- Wasmtime/Cranelift: `68a6afd4f`

## Preparation
- Rebuilt binaries before measurements:
  - `./install.sh`

## Commands
- AEAD runtime:
  - `./wasmoon run examples/aead_aegis128l.wasm`
  - `wasmtime run examples/aead_aegis128l.wasm`
- Benchmark runtime:
  - `./wasmoon run examples/benchmark.wasm`
  - `wasmtime run examples/benchmark.wasm`
- Explore artifacts:
  - `./wasmoon explore examples/aead_aegis128l.wasm --func 9`
  - `wasmtime explore examples/aead_aegis128l.wasm -o <html>`
- Wasmoon perf json:
  - `WASMOON_PERF_METRICS=1 WASMOON_PERF_METRICS_FILE=<json> ./wasmoon run examples/aead_aegis128l.wasm`

All runtime medians below are from 5 runs measured with `/usr/bin/time -p`.

## Results
- AEAD (`examples/aead_aegis128l.wasm`)
  - Wasmoon median: `3.40s`
  - Wasmtime median: `0.87s`
  - Ratio: `3.91x` (Wasmoon slower)
- Benchmark (`examples/benchmark.wasm`)
  - Wasmoon median: `0.37s`
  - Wasmtime median: `0.40s`
  - Ratio: `0.93x` (Wasmoon faster)

## Wasmoon compile profile (single AEAD run)
- `module_compile_us`: `2437757`
- `function_count`: `63`
- `optimize_us_total`: `398329`
- `regalloc_us_total`: `1693016`
- `emit_us_total`: `26739`

## Artifacts
- `wasmoon_aead_runs.txt`
- `wasmtime_aead_runs.txt`
- `wasmoon_benchmark_runs.txt`
- `wasmtime_benchmark_runs.txt`
- `wasmoon_aead_perf.json`
- `wasmoon_aead_func9.explore.txt`
- `wasmtime_aead.explore.html`
