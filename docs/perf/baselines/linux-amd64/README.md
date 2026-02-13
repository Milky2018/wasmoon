# Linux amd64 Baseline

Place `perf-summary.json` in this directory for CI/nightly regression checks:

```bash
cp target/perf-benchmarks/latest/summary.json docs/perf/baselines/linux-amd64/perf-summary.json
```

Nightly perf CI also runs a Wasmoon-vs-Wasmtime parity guardrail for:

- `examples/aead_aegis128l.wasm`
- `examples/benchmark.wasm`

and stores reports under `target/perf-benchmarks/parity/`.
