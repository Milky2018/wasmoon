# Compile-Time Metrics and Baseline Workflow

This document defines the machine-readable compile-time metrics used by Wasmoon
performance work, and how to capture reproducible baselines.

## Goals

- Track compile-time behavior at module, function, and pass granularity.
- Provide a stable JSON schema that CI and local scripts can consume.
- Keep runtime overhead negligible unless metrics are explicitly enabled.

## Enabling Metrics

Metrics are opt-in via environment variables:

- `WASMOON_PERF_METRICS=1`
  - Enables metrics collection in the JIT compile pipeline.
  - Bypasses the run JIT cache so every report describes an actual compilation.
- `WASMOON_PERF_METRICS_DETAIL=1`
  - Adds per-pass optimization, compiler subphase, and register-allocation
    details.
- `WASMOON_PERF_METRICS_FILE=<path>`
  - Optional output file path.
  - Default: `target/wasmoon-perf-metrics.json`.

Example:

```bash
WASMOON_PERF_METRICS=1 ./wasmoon test spec/f32.wast
```

## Collected Data

Collection starts in `cmd/wasmoon/run.mbt` during `compile_module_to_jit(...)`.

### Module-level fields

- `schema_version` (`7` for direct acyclic rewrite attribution)
- `expected_functions`
- `module_compile_us`
- `compile_subphases[]` for module preparation when detailed metrics are
  enabled. Each entry names `parent: "module"`; the derived
  `module_orchestration` entry closes the difference between module time,
  preparation, and complete function jobs.
- `functions[]`

### Per-function fields

- Identity:
  - `func_idx`, `func_name`, `opt_level`
- IR size:
  - `ir_insts_before`, `ir_insts_after`
- Detailed aggregate:
  - `function_compile_us`: complete serial function-job time, used to derive
    orchestration work outside the named compiler stages.
- Stage time:
  - `optimize_us`: MilkIR optimization.
  - `lower_us`: streaming MilkIR-to-native-target construction, including
    embedding ABI elaboration and instruction selection.
  - `target_lower_us`: selected-VCode verification and sealing after streaming
    construction completes.
  - `regalloc_us`: production VCode register allocation.
  - `frame_plan_us`: target frame planning.
  - `emit_us`: final code-object emission.
- Codegen pressure indicators:
  - `code_size`
  - `spill_slots`, `spills`, `reloads`, `reg_moves`, `spill_to_spill`
- Pass list:
  - `compile_subphases[]` when detailed metrics are enabled. This attributes
    frontend translation, semantic validation/construction/cleanup sealing,
    embedding ABI and target-context preparation, streamed target construction,
    selected-VCode validation or trusted sealing, flat allocation-input
    normalization, generic allocation input validation, and artifact packaging.
    Detailed external validation further splits into common and ISA phases
    under `target_vcode_validation`. The `parent` field identifies
    whether a subphase reconciles against `function_compile_us`, `lower_us`, or
    `target_lower_us`; derived `semantic_orchestration`,
    `target_orchestration`, and `function_orchestration` entries close observer
    and function-level remainders. `regalloc_orchestration` performs the same
    reconciliation for `regalloc_phases[]`.
  - `ir_passes[]`
  - `regalloc_phases[]` when detailed metrics are enabled.

All microsecond fields use JSON strings because their in-memory type is `Int64`.
For sequential compilation, the sum of per-function stage times is an attributed
lower bound on `module_compile_us`; frontend translation, manifest construction,
and orchestration account for the remainder and must not be double-counted into
one of the target stages.

Producers record these top-level fields through `FunctionCompileStage`, and the
`TargetCompileEvent` observer maps events to that enum with an exhaustive match.
String names exist only in the exported JSON schema and in the open-ended
`regalloc_phases` detail list; an unknown top-level stage cannot be silently
ignored.

Allocation counters describe the final VCode allocation. Edge transfers are
classified by their source and destination: register-to-stack is a spill,
stack-to-register is a reload, register-to-register is a register move, and
stack-to-stack is `spill_to_spill`.

### Per-pass fields (`ir_passes[]`)

- `name`
- `duration_us`
- `before_insts`, `after_insts`, `changed`
- Optional acyclic-rewrite stats:
  - `rewrite_attempts`: MilkIR instructions dispatched to the direct rewriter
  - `rewrite_apps`: successful local rewrites
  - `rewrite_created_insts`: new MilkIR instructions created by rewrites
- Optional bounded-work stats:
  - `work_done`, `budget_exhausted`
  - For `acyclic_optimize`, these describe the bounded precise-memory prefix;
    direct rewrites and cheap value numbering still visit the complete
    reachable dominator tree.

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

## Repeatable Benchmark Runner (with thresholds)

Use:

```bash
python3 scripts/run_perf_benchmarks.py
```

This runner is a manual diagnostic tool:

- Repeats each workload (`--iterations`, default `5`) with warmup runs.
- Collects medians for:
  - wall-clock `elapsed_ms`,
  - `module_compile_us`,
  - total emitted `code_size`.
- Optionally compares against a baseline summary (`--baseline`) and fails when
  regressions exceed configured thresholds:
  - `--threshold-elapsed-pct` (default `15`)
  - `--threshold-compile-pct` (default `15`)
  - `--threshold-code-size-pct` (default `5`)

Example:

```bash
python3 scripts/run_perf_benchmarks.py \
  --out-dir target/perf-benchmarks/latest \
  --iterations 3 \
  --warmup 1 \
  --baseline docs/perf/baselines/linux-amd64/perf-summary.json
```

The repository does not use historical backend comparisons as CI acceptance
gates. Baseline comparison remains available for local investigations.

## Artifact Layout

For each workload:

- `<sanitized>.metrics.json`
- `<sanitized>.stdout.log`
- `<sanitized>.stderr.log`

Aggregate files:

- `summary.json`
- `summary.md`

## Automation Guidance

- Keep compile metrics opt-in in normal CI to avoid noise.
- Treat `summary.json` as diagnostic evidence rather than a merge gate.

## Notes

- Metrics collection is designed to be side-effect free when disabled.
- Pass-level counters are recorded in `modules/milkir/optimize/driver.mbt`.
- Acyclic rewrite/GVN aggregate stats are emitted through the optional metrics
  sink in `modules/milkir/optimize/metrics.mbt`; embeddings install the sink
  through `@optimize.install_optimization_metrics_sink(...)`.
