# Historical performance baselines

Dated subdirectories retain reviewed Markdown summaries with the original
workload, revision, platform and comparison limits. Raw generated reports,
HTML, IR and individual samples are available in
[Git history](https://github.com/Milky2018/wasmoon/tree/f31c1166d42da776e30841e08e6824f004585c7e/docs/perf/baselines);
they are not retained in the current source distribution.

Do not copy new benchmark output into this directory. Use an auto-cleaned OS
temporary directory for reports, profiles and caches. Retain only a compact
reviewed conclusion when it helps explain a lasting implementation decision.
See the [performance recording policy](../README.md).

## Algorithm comparison contract

Use `scripts/benchmark_algorithms_parity.py` with one cold serial compilation per
engine and workload. It requires Wasmtime `-C parallel-compilation=n`, separate
empty caches, asserted outputs and distinct guest-value and whole-process wall
ratios. Historical warm-cache or parallel-compiler comparisons keep their
original limitations; they are not directly comparable with current cold serial
measurements.

The runtime's opt-in `WASMOON_JIT_CACHE_REPORT` distinguishes fresh compilation,
cache hits and cache-write success. File creation alone does not establish
compilation. Cache identities and artifact versions remain validated before
loading. Run `python3 scripts/run_jit_cache.py` to verify cold/warm behavior,
corrupt-artifact recovery and unavailable cache directories.
