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

3. Inspect `summary.md` and selected `*.metrics.json` files.
4. For a versioned snapshot, copy `latest/` to a dated directory, for example:

```bash
cp -R docs/perf/baselines/latest docs/perf/baselines/2026-02-06-amd64-step1
```

## What to commit

- Commit only reviewed snapshots used for comparisons.
- Keep local scratch runs in `latest/`.
