# Baseline Artifacts

This directory stores compile-performance baseline snapshots.

## Recommended workflow

1. Build or refresh `./wasmoon`.
2. Run:

```bash
python3 scripts/collect_perf_baseline.py --out-dir docs/perf/baselines/latest
```

The default mode uses `wasmoon run` on curated `.wasm` workloads. Use
`--subcommand test` only when you intentionally benchmark WAST test mode.

For repeatable CI/nightly checks with regression thresholds:

```bash
python3 scripts/run_perf_benchmarks.py \
  --out-dir target/perf-benchmarks/latest \
  --iterations 3 \
  --warmup 1 \
  --baseline docs/perf/baselines/linux-amd64/perf-summary.json
```

To refresh the committed amd64 baseline file, copy:

```bash
cp target/perf-benchmarks/latest/summary.json docs/perf/baselines/linux-amd64/perf-summary.json
```

3. Inspect `summary.md` and selected `*.metrics.json` files.
4. For a versioned snapshot, copy `latest/` to a dated directory, for example:

```bash
cp -R docs/perf/baselines/latest docs/perf/baselines/2026-02-06-amd64-step1
```

## What to commit

- Commit only reviewed snapshots used for comparisons.
- Keep local scratch runs in `latest/`.
- Keep architecture-specific threshold baselines under `linux-amd64/` and
  `darwin-arm64/` (or other explicit arch folders).
