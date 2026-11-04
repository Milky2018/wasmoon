# Performance notes

Keep maintained explanations, workload identities, reproduction commands and
small reviewed conclusions here. Full profiles, machine-code/IR dumps, generated
HTML, individual samples and benchmark caches belong in auto-cleaned OS
temporary directories or CI artifacts, not in the source tree or `_build`.
`_build` is reserved for Moon tool outputs.

Historical Markdown reports retain their original dates, revisions and scope.
Generated outputs removed during 0.18.0 preparation remain available in
[Git history](https://github.com/Milky2018/wasmoon/tree/f31c1166d42da776e30841e08e6824f004585c7e/docs/perf).
Existing links to those outputs pin that revision. Their measurements are not
reinterpreted as evidence for the current release.

Useful maintained entry points:

- [parse_double GC contracts and deferred work](parse-double-gc.md)
- [GC array bulk operations](gc-array-bulk-2026-10-22.md)
- [Typed allocation throughput](runtime-throughput.md)
- [Unsigned wide multiplication](wide-multiply.md)
- [Store callable lookup](callable-lookup.md)
- [Runtime repair for #567](issue567-runtime-repair-2026-10-21.md)
- [Compiler metrics](compile-metrics.md)
- [Historical baseline summaries](baselines/README.md)

For algorithm comparisons use `scripts/benchmark_algorithms_parity.py` with
fresh independent caches and `-C parallel-compilation=n` for Wasmtime. Record
invocation, compilation, whole-process time and RSS separately, including each
timer's boundary. Preserve workload assertions and disclose toolchain, source
revision and dirty-source status. A single workload is not an engine-wide
performance claim.
