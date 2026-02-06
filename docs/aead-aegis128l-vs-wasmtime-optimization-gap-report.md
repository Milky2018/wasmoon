# Wasmoon vs Wasmtime (Cranelift) Optimization Gap Report

## 1. Executive Summary

For `examples/aead_aegis128l.wasm`, Wasmoon is currently much slower than Wasmtime on the same machine.

- `./wasmoon run examples/aead_aegis128l.wasm` -> `real 8.44s`
- `wasmtime run examples/aead_aegis128l.wasm` -> `real 0.76s`

This is an ~`11.1x` end-to-end gap in this run.

### Status Update (2026-02-06)

After the first optimization batch in this branch, local re-measurement is:

- `./wasmoon run examples/aead_aegis128l.wasm` -> `real 3.51s`
- `wasmtime run examples/aead_aegis128l.wasm` -> `real 0.75s`

Current gap is ~`4.7x` (down from ~`11.1x`).

Key implemented improvements:

1. Fixed egraph false-positive `changed` signaling for no-op opcode rewrites.
2. Added optimization loop stall detection and reduced max iteration budget.
3. Removed duplicate IR optimization in `run`/`explore` lowering path.
4. Replaced lowering-time defining-inst linear scans with O(1) lookup cache.
5. Changed amd64 regalloc output validation to lazy context formatting on error path.

The primary bottleneck in Wasmoon is **compile-time work before first execution**, not only generated-code runtime quality:

- Wasmoon JIT compile time for this module: `7.43s` (`7425283us`)
- Compile time is about `88%` of total wall time in this run.

The largest root cause found is that Wasmoon optimization repeatedly hits a 100-iteration cap for most functions (61/63), with egraph reported as changed every round.

## 2. Scope and Method

This report compares:

1. Wasmoon source in `/Users/zhengyu/Documents/projects/wasmoon`
2. Wasmtime/Cranelift source in `/Users/zhengyu/Documents/projects/wasmtime/wasmtime`
3. `explore` outputs for function index 9 (`_start`) from both tools

### Revisions analyzed

- Wasmoon commit: `d44ddf3007e8ac10fa49d4bfd5742d7ef6639157`
- Wasmtime commit: `68a6afd4f925724fd359c13a27fac5a6163d12f4`

### Important note on printed numeric output

The final printed number from this program is time-dependent, so output values between runs/tools are not a correctness indicator for this performance comparison.

## 3. Reproduced Runtime Evidence

### 3.1 End-to-end runtime

- Wasmoon:
  - Command: `/usr/bin/time -p ./wasmoon run examples/aead_aegis128l.wasm`
  - Observed: `real 8.44`, `user 8.36`, `sys 0.05`
- Wasmtime:
  - Command: `/usr/bin/time -p wasmtime run examples/aead_aegis128l.wasm`
  - Observed: `real 0.76`, `user 0.74`, `sys 0.00`

### 3.2 Wasmoon JIT compile metrics

From:

- `WASMOON_PERF_METRICS=1 WASMOON_PERF_METRICS_FILE=/tmp/wasmoon_aead_perf.json ./wasmoon run examples/aead_aegis128l.wasm`

Key metrics:

- `module_compile_us`: `7425283`
- functions compiled: `63`

Stage totals:

- `optimize_us`: `5157799` (`69.46%` of module compile)
- `lower_us`: `1217600` (`16.40%`)
- `regalloc_us`: `1015088` (`13.67%`)
- `emit_us`: `29760` (`0.40%`)

Interpretation: startup is dominated by optimize + lower + regalloc, not emission.

### 3.3 Optimization loop behavior

From `/tmp/wasmoon_aead_perf.json`:

- egraph rounds histogram:
  - `1` round: `2` functions
  - `100` rounds: `61` functions

Additional aggregate:

- egraph pass invocations: `6102`
- total egraph pass time: `3365740us`

This indicates most functions optimize until the hard cap, not fixed-point convergence.

## 4. Explore Output Comparison (`_start`, func index 9)

### 4.1 Wasmoon explore (`./wasmoon explore ... --func 9`)

From `/tmp/wasmoon_aead_start_explore.txt`:

- instruction count: `2868`
- code span: `11472` bytes
- regalloc stats:
  - `spillslots: 22 (176 bytes)`
  - `reloads=272`
  - `spills=113`
  - `reg_moves=191`

Approx mnemonic-level counts:

- loads: `671`
- stores: `241`
- calls (`bl` + `blr`): `90`

### 4.2 Wasmtime explore (`wasmtime explore ... -o ...`)

From `/tmp/wasmtime_aead_asm.json` (extracted from explorer HTML):

- instruction count: `2422`
- code span: `9688` bytes

Approx mnemonic-level counts:

- loads: `523`
- stores: `192`
- calls (`bl` + `blr`): `90`

### 4.3 Delta summary (`_start`)

Compared to Wasmtime, Wasmoon `_start` has:

- `+18.4%` instruction count (`2868 / 2422`)
- `+18.4%` code span (`11472 / 9688`)
- `+28.3%` load ops (`671 / 523`)
- `+25.5%` store ops (`241 / 192`)

Interpretation: Wasmoon generated code for this hot function has materially higher memory traffic and register pressure.

## 5. Source-Level Findings

### 5.1 Wasmoon still compiles all functions before execution

In `compile_module_to_jit`, Wasmoon loops through all module code bodies:

- `/Users/zhengyu/Documents/projects/wasmoon/cli/main/run.mbt:1075`

```moonbit
for i, _ in mod_.codes {
  ...
}
```

Debug output confirms full-module compile before `_start` call:

- `JIT: Compiled 63/63 functions`

This behavior is eager full-module compilation.

### 5.2 Wasmtime also defaults to eager module compilation, but compiles in parallel

Wasmtime module creation compiles module code:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/runtime/module.rs:248`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/runtime/module.rs:251`

Compilation pipeline uses parallel compilation for inputs:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/compile.rs:550`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/compile.rs:562`

Default optimization level is speed-oriented:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/config.rs:280`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/config.rs:1348`

Conclusion: Wasmtime is eager too, but has significantly more optimized compile pipeline and parallelization.

### 5.3 Wasmoon optimization loop likely over-runs due changed-flag semantics

Wasmoon optimization loop cap:

- `/Users/zhengyu/Documents/projects/wasmoon/ir/opt_driver.mbt:142`
- `/Users/zhengyu/Documents/projects/wasmoon/ir/opt_driver.mbt:205`

Both O1 and full optimize loops allow up to 100 iterations.

Inside egraph rewrite application:

- `/Users/zhengyu/Documents/projects/wasmoon/ir/egraph_builder.mbt:493`
- `/Users/zhengyu/Documents/projects/wasmoon/ir/egraph_builder.mbt:496`

`changed` is set true whenever `Some(new_op)` is returned, without checking whether `new_op` equals current opcode. This can keep optimization in a pseudo-changed state and drive repeated rounds to the cap.

This behavior matches observed data (61/63 functions at 100 rounds).

### 5.4 Potential duplicate optimization in lowering path

In module compile flow:

- Phase 2 already runs `@ir.optimize_with_level(...)`:
  - `/Users/zhengyu/Documents/projects/wasmoon/cli/main/run.mbt:1104`

Then lowering calls `@ir.optimize_function(ir_func)` again:

- `/Users/zhengyu/Documents/projects/wasmoon/vcode/lower/lower.mbt:771`

If both are active for the same function, this likely duplicates optimization work and amplifies startup compile time.

### 5.5 Cranelift optimization pass structure is bounded and staged differently

Cranelift optimize pipeline runs a staged flow and calls egraph pass once in optimize when opt level is not none:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/context.rs:151`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/context.rs:185`

Cranelift egraph has hard limits:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/egraph.rs:76`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/cranelift/codegen/src/egraph.rs:79`

Wasmoon also defines Cranelift-style egraph limits (`5/5`) in:

- `/Users/zhengyu/Documents/projects/wasmoon/ir/egraph/egraph.mbt:1796`

However, overall driver-level repeated rounds in Wasmoon still produce high total optimize cost.

### 5.6 Runtime memory initialization advantage in Wasmtime

Wasmtime enables memory-init COW by default and attempts static initialization transforms:

- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/config.rs:2010`
- `/Users/zhengyu/Documents/projects/wasmtime/wasmtime/crates/wasmtime/src/compile.rs:1091`

Wasmoon active data initialization performs explicit data copies during instantiation:

- `/Users/zhengyu/Documents/projects/wasmoon/executor/instantiate.mbt:1135`
- `/Users/zhengyu/Documents/projects/wasmoon/runtime/memory.mbt:453`

This is another startup-time gap contributor, especially for data-heavy modules.

## 6. What Is Missing vs What Looks Wrong

### 6.1 Missing optimizations / mechanisms

1. Parallel function compilation in Wasmoon JIT compile path.
2. Wasmtime-style static memory init / COW initialization path.
3. Some backend code quality heuristics (observed as higher load/store counts and spill activity in `_start`).

### 6.2 Likely wrong or suboptimal behavior

1. Optimization loop convergence signaling appears incorrect (frequent 100-round behavior).
2. Possible double optimization (driver + lowering) on the same IR function.

## 7. Prioritized Optimization Plan

### P0 (highest impact, low-to-medium risk)

1. **Fix changed detection in egraph rewrite application**
   - Only set changed when opcode/operands actually differ.
   - Add counters for no-op rewrites.

2. **Tighten optimization loop termination policy**
   - Stop early if no material change in instruction graph.
   - Keep cap, but expect most functions << 100 rounds.

3. **Remove duplicate optimization in lowering path (or gate by flag)**
   - Ensure IR optimize runs exactly once per function in normal compile path.

Expected impact: large startup compile-time reduction.

### P1 (high impact)

4. **Parallelize per-function compile in `compile_module_to_jit`**
   - Keep deterministic output ordering by collecting results then committing in index order.

5. **Compile-time profiling guardrails in CI**
   - Fail CI if optimize rounds regress (e.g., too many functions hitting max rounds).

Expected impact: shorter wall time on multicore hosts.

### P2 (medium impact)

6. **Lowering/codegen parity pass for hot patterns**
   - Focus on reducing memory traffic and register pressure in `_start`-like hot blocks.
   - Validate against `explore` diffs: load/store count, code span, spill stats.

7. **Data initialization optimization path**
   - Evaluate static initialization and potential COW-backed startup strategy.

Expected impact: further startup + runtime wins for larger modules.

## 8. Suggested Acceptance Targets

For this workload (`examples/aead_aegis128l.wasm`) on the same machine/config:

1. Reduce module compile time by at least `40%`.
2. Reduce functions hitting 100 optimize rounds from `61` to near `0`.
3. Reduce `_start` code span and memory ops toward Wasmtime baseline:
   - code span: from `11472` closer to `9688`
   - loads/stores: reduce from `671/241` significantly.

## 9. Reproduction Commands

```bash
# Runtime
/usr/bin/time -p ./wasmoon run examples/aead_aegis128l.wasm
/usr/bin/time -p wasmtime run examples/aead_aegis128l.wasm

# Wasmoon compile profile
WASMOON_PERF_METRICS=1 \
WASMOON_PERF_METRICS_FILE=/tmp/wasmoon_aead_perf.json \
./wasmoon run examples/aead_aegis128l.wasm

# Explore outputs
./wasmoon explore examples/aead_aegis128l.wasm --func 9 > /tmp/wasmoon_aead_start_explore.txt
wasmtime explore examples/aead_aegis128l.wasm -o /tmp/wasmtime_aead_explore.html
```
