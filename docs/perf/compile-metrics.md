# Compile-Time Metrics and Baseline Workflow

This document defines the machine-readable compile-time metrics used by Wasmoon
performance work, and how to capture reproducible baselines.

## Goals

- Track compile-time behavior at module, function, and pass granularity.
- Provide a stable JSON schema that CI and local scripts can consume.
- Keep runtime overhead zero unless metrics are explicitly enabled.

## Enabling Metrics

Metrics are opt-in via environment variables:

- `WASMOON_PERF_METRICS=1`
  - Enables metrics collection in the JIT compile pipeline.
- `WASMOON_PERF_METRICS_FILE=<path>`
  - Optional output file path.
  - Default: `target/wasmoon-perf-metrics.json`.

Example:

```bash
WASMOON_PERF_METRICS=1 ./wasmoon test spec/f32.wast
```

## Collected Data

Collection starts in `cli/main/run.mbt` during `compile_module_to_jit(...)`.

### Module-level fields

- `schema_version`
- `expected_functions`
- `module_compile_us`
- `functions[]`

### Per-function fields

- Identity:
  - `func_idx`, `func_name`, `opt_level`
- IR size:
  - `ir_insts_before`, `ir_insts_after`
- Stage time:
  - `optimize_us`, `lower_us`, `regalloc_us`, `emit_us`
- Codegen pressure indicators:
  - `code_size`
  - `spill_slots`, `spills`, `reloads`, `reg_moves`, `spill_to_spill`
- Pass list:
  - `ir_passes[]`

### Per-pass fields (`ir_passes[]`)

- `name`
- `duration_us`
- `before_insts`, `after_insts`, `changed`
- Optional e-graph stats:
  - `egraph_classes`, `egraph_nodes`, `egraph_rule_apps`

## Baseline Capture Script

Use:

```bash
python3 scripts/collect_perf_baseline.py
```

Default behavior:

- Runs a curated workload set:
  - `examples/core3.wasm`
  - `examples/benchmark.wasm`
  - `examples/stream.wasm`
  - `examples/box_easy2.wasm`
- Executes `./wasmoon run <workload>` with metrics enabled.
- Writes artifacts under `docs/perf/baselines/latest/` by default.

Key options:

- `--wasmoon <path>`: choose binary path
- `--out-dir <dir>`: choose output directory
- `--timeout-sec <n>`: per-workload timeout
- `--subcommand run|test`: choose workload execution mode
- `--workload <path>`: repeatable custom workload list

The script exits non-zero when:

- any workload exits non-zero, or
- metrics file is missing for any workload.

## Artifact Layout

For each workload:

- `<sanitized>.metrics.json`
- `<sanitized>.stdout.log`
- `<sanitized>.stderr.log`

Aggregate files:

- `summary.json`
- `summary.md`

## CI Integration Guidance

- Keep compile metrics opt-in in normal CI to avoid noise.
- Add a dedicated perf workflow/job for baseline refresh and regression checks.
- Parse `summary.json` and selected metrics JSON files for trend checks.

## Notes

- Metrics collection is designed to be side-effect free when disabled.
- Pass-level counters are recorded in `ir/opt_driver.mbt`.
- E-graph aggregate stats are collected via `optimize_function_with_stats(...)`.
