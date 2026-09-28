# Cold CLI startup attribution, 2026-09-28

## Result and decision

The repeated Wasmtime 49.0.1 comparison confirms a substantial cold CLI wall-time
penalty on the short workloads. Separate Wasmoon phase captures attribute most
of those commands to fresh compilation, not instance creation or cache writes.
This investigation therefore targets compilation rather than redesigning WASI
startup, caching, HTTP scheduling or the interpreter.

Retained one small allocator optimization: materialize preferred registers only,
then visit remaining physical registers lazily in the original machine order.
Successful early probes no longer construct the unused default-register suffix.
Both normal allocation and second-chance allocation preserve candidate ordering,
class filtering, conflict policy and generated artifacts. Marks describe the
preferred prefix and are cleared with that prefix before reuse. No public API,
package dependency, allocation policy, unchecked memory access or cache change
is introduced.

Two independent 21-pair full-compilation rounds support modest improvements on
four of six inputs. **The separate 21-pair CLI comparison does not establish an
end-to-end speedup on any input:** all its intervals include zero. There is no
established peak-RSS improvement. This is a small compile-time saving, not a
solution to the overall Wasmtime gap.

## Measurement contract

Parent source: `9a0efe42` (Wasmtime reference refresh). The baseline CLI adds only
the opt-in command-phase collector; the candidate adds the allocator change.
Both ordinary binaries have detailed metrics disabled. The collector is inactive
in ordinary runs and does not change cache policy when enabled. The comparison
with Wasmtime therefore describes the instrumentable baseline, not a claim that
instrumentation has exactly zero cost compared with the parent binary.

Host: Apple M3 Max, macOS 26.7 arm64. Moon 0.1.20260920 and
moonc 0.10.14+7d59c7ec9. Reference: official Wasmtime 49.0.1 / Cranelift 0.136.1.
Every run starts a fresh process with empty artifact caches; executable and
filesystem pages are warmed. Wasmtime uses `-C parallel-compilation=n`.
No build, test or profiler overlaps any measurement round.

The six inputs were selected before repeated sampling from ISS-588's 70-module
snapshot: `auth` and `onetimeauth` are short startup-heavy cases;
`aead_chacha20poly1305` has both wall-time and guest-metric gaps; `generichash` is
a medium case; `aead_aegis128l` and `xchacha20` are longer near-parity controls.
This is a diagnostic sample, not a random or comprehensive corpus estimate.

- Reference comparison: 15 pairs per workload, alternating engine order, with
  all warmups retained. Ordinary measurements include process wall time and
  `/usr/bin/time` peak RSS.
- Separate diagnostic passes: three command-phase captures and one detailed
  compiler capture per workload/build. Compiler detail bypasses cache handling
  and is never included in ordinary medians.
- Candidate compilation: two fixed rounds of 21 AB/BA pairs per input, reversing
  workload order in round two. The existing fixture times the entire public
  `compile_module` call; artifact encoding/writing is outside its timed region.
  This eager compile path is not substituted for CLI compilation time.
- Candidate CLI: 21 ordinary pairs per workload plus retained warmups and separate
  phase/compiler diagnostics. Complete persisted artifact hashes must match.
- Confidence intervals are fixed-seed paired bootstrap intervals of the median
  percentage change. They describe these samples, are not adjusted for multiple
  comparisons, and are not guarantees for other machines or x64.

All ordinary and diagnostic samples completed successfully. Guest numeric stdout
is retained as a guest-defined metric, **not interpreted as seconds**. Wasmtime's
internal compile/execution times are unknown here. Process RSS includes the
runtime, compiler, guest and mappings; it is not temporary compiler allocation.

## Repeated reference comparison

Positive paired wall change means Wasmoon takes longer. RSS is decimal MB.

| Workload | Wasmoon wall ms | Wasmtime wall ms | Paired wall change, 95% interval | Wasmoon / Wasmtime RSS MB |
| --- | ---: | ---: | ---: | ---: |
| auth | 60.40 | 33.17 | +83.53% [+81.66%, +85.51%] | 18.69 / 23.48 |
| onetimeauth | 43.30 | 25.48 | +71.71% [+67.11%, +74.02%] | 17.96 / 23.13 |
| aead_chacha20poly1305 | 72.71 | 43.78 | +66.55% [+66.15%, +67.62%] | 19.20 / 23.94 |
| generichash | 119.10 | 90.05 | +32.59% [+32.14%, +35.99%] | 19.17 / 24.56 |
| aead_aegis128l | 769.16 | 753.92 | +2.12% [+1.76%, +2.95%] | 19.15 / 24.25 |
| xchacha20 | 1524.89 | 1451.96 | +5.49% [+5.32%, +5.75%] | 27.15 / 27.05 |

## Wasmoon phase attribution

These are medians from separate diagnostic runs, not a subtraction from the
ordinary wall medians above. Phase durations partition entry to `run_wasm`
through its return. Export invocation includes host calls; instantiation includes
any Wasm start function. Executable startup, argument parsing, report writing
and some final destruction are outside the command interval. Individual medians
need not sum to a median total.

| Workload | Compile ms | Instantiate ms | Cache write/report ms | JIT load/setup ms | Export invocation ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| auth | 48.869 | 0.101 | 0.472 | 0.891 | 4.105 |
| onetimeauth | 36.737 | 0.102 | 0.478 | 0.720 | 0.217 |
| aead_chacha20poly1305 | 47.480 | 0.121 | 0.495 | 0.902 | 19.723 |
| generichash | 46.000 | 0.114 | 0.493 | 0.757 | 65.136 |
| aead_aegis128l | 54.619 | 0.112 | 0.511 | 0.823 | 702.104 |
| xchacha20 | 115.012 | 0.149 | 0.819 | 1.948 | 1443.055 |

Detailed compiler captures place register allocation at approximately 34–37%
of module compilation and optimization at 24–28%. Bundle allocation is the
largest named register-allocation subphase (about 4.5–17.8 ms across these
captures). It is nested inside allocation, not additional time to add to it.
`acyclic_optimize` is the largest optimization pass. This points to allocator
and optimizer work rather than host setup as the next deeper investigation.

## Candidate evidence

Negative change means faster. All 504 measured full compilations produce
identical complete artifacts per input. All 252 measured CLI runs also produce
identical persisted artifacts per input; CLI compilation uses its actual
reachability mask rather than the eager fixture. Warmup and phase captures
are additional to these counts.

| Workload | Compile round 1 | Compile round 2 | CLI wall |
| --- | ---: | ---: | ---: |
| auth | -0.60% [-1.09%, -0.38%] | -1.46% [-2.04%, -0.67%] | -0.19% [-0.88%, +1.00%] |
| onetimeauth | -1.26% [-2.39%, -0.04%] | -1.53% [-2.74%, +0.27%] | -0.04% [-1.20%, +0.78%] |
| aead_chacha20poly1305 | -0.67% [-1.21%, -0.29%] | -1.89% [-2.80%, -1.13%] | -0.83% [-1.91%, +0.09%] |
| generichash | -1.03% [-1.47%, -0.23%] | -1.77% [-2.37%, -0.41%] | -0.31% [-0.99%, +0.40%] |
| aead_aegis128l | -1.61% [-2.91%, -0.54%] | -2.97% [-3.98%, -1.55%] | -0.13% [-0.84%, +0.61%] |
| xchacha20 | -0.87% [-1.61%, -0.24%] | -1.42% [-2.43%, +0.11%] | -0.38% [-1.54%, +0.70%] |

The change is retained for the bounded removal of unused work and repeatable
full-compilation benefit on four workloads. `onetimeauth` and `xchacha20` have
second-round compile intervals crossing zero. The CLI result remains inconclusive
for every input. No additional sampling was used to seek a favorable CLI result.
Neither reduced allocation bytes nor lower peak memory is claimed.

## Validation and reproduction

- Native warning-denied check, generated interfaces and formatting pass.
- 2,586 native tests pass, including allocator and both target backend tests.
- Core WAST: 258/258 files per engine.
- Full misc (including high-memory): 692 assertion-bearing passes and 72
  script-only executions; zero failures, timeouts or exclusions.
- Python harness tests: 178, including four new evidence-contract tests; 54 skip.
- Module boundary check passes; no public interface changes.
- CLI smoke checks verify fresh compilation, a subsequent cache hit without a
  `compile` phase, and a trapped invocation with a closed invocation phase.

```bash
python3 scripts/benchmark_startup.py --wasmtime "$HOME/.cargo/bin/wasmtime" \
  --output target/startup-reference
python3 scripts/benchmark_compiler_memory.py \
  --before /path/to/compiler-before --after /path/to/compiler-candidate \
  --repetitions 21 --output target/compiler-pairs \
  examples/algorithms/auth.wasm examples/algorithms/onetimeauth.wasm \
  examples/algorithms/aead_chacha20poly1305.wasm examples/algorithms/generichash.wasm \
  examples/algorithms/aead_aegis128l.wasm examples/algorithms/xchacha20.wasm
python3 scripts/benchmark_startup.py --before /path/to/wasmoon-before \
  --wasmoon ./wasmoon --repetitions 21 --output target/startup-candidate
```

[Compressed raw evidence](cli-startup-2026-09-28.json.gz) retains every reference
and CLI sample, complete detailed captures, both compiler rounds, executable and
input hashes, and the candidate patch. Local raw logs/artifacts remain under
`target/startup-589`. After formatting, a final rebuild has a different executable hash; all six
untimed acceptance runs reproduce the exact artifacts from both measured builds.
The final executable hash and those results are retained separately, and do not
replace or relabel the measured samples. The ordinary CLI collector's private
helper stays in the
commands package because it describes private `run_wasm` control flow, not a
reusable compiler or public metrics API. The separate external HTTP contract
work remains ISS-571 and is not claimed as resolved here.
