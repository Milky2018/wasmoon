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

For an optional local comparison against a reviewed snapshot:

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
- Keep architecture-specific diagnostic snapshots under `linux-amd64/` and
  `darwin-arm64/` (or other explicit arch folders).

## Algorithm corpus sweeps

Run the algorithms corpus through the dedicated cold-cache runner:

```bash
python3 scripts/benchmark_algorithms_parity.py \
  --wasmoon ./wasmoon \
  --wasmtime wasmtime
```

The runner must invoke Wasmtime with `-C parallel-compilation=n`. Wasmoon
currently compiles module functions serially, so allowing Wasmtime's default
parallel compilation would mix parallel throughput with serial cold-compilation
latency and overstate the compiler gap. Keep the Wasmtime serial setting for
all future corpus sweeps and any baseline derived from them. If parallel
throughput is measured separately, label it as a distinct experiment and do
not compare it directly with the serial corpus history.

## Compilation and cache evidence

Algorithm benchmark schema 4 separates `freshly_compiled`, `cache_hit`,
`cache_write_succeeded`, and `cache_files_changed`. Wasmoon reports the first
three through the opt-in `WASMOON_JIT_CACHE_REPORT` JSON file; reporting does not
turn on performance instrumentation or disable the JIT cache. A fresh compile
can succeed even when saving its artifact fails. A cache hit performs no write,
so `cache_write_succeeded` is null. Missing or malformed runtime evidence leaves
compilation outcomes null and marks a measurement error (`--strict` exits nonzero).
Wasmtime has no equivalent signal in this runner: compilation/hit/write outcomes
remain null, with filesystem changes recorded separately. Both engines still
start with empty isolated cache directories, once per workload, and Wasmtime
parallel compilation remains disabled.

Older summaries used cache-file changes as `freshly_compiled`. That field is
not direct compilation evidence in schema 3 or earlier; existing historical
reports are preserved, not retroactively relabeled as measured compilations.

Persistent Wasmoon filenames hash the existing complete cache identity with
SHA-256 and retain the artifact format prefix and `.cwasm` suffix. Artifact
compatibility is still checked before loading. Old cache names are not reused.
Run `python3 scripts/run_jit_cache.py` to verify cold writes, warm hits, corrupt
artifact recovery, write failures, and unavailable cache directories using a
real CLI process. The same gate runs on Linux, macOS, and Windows Clang/MSVC.
