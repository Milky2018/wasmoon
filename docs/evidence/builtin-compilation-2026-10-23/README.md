# Large builtin compilation: issue #575

This is local macOS ARM64 evidence for
[GitHub #575](https://github.com/Milky2018/wasmoon/issues/575), based on
`45611d6c20a34fa83d5db3eb466eabffe6ba8f92` plus the uncommitted repair.
It is not clean CI or release acceptance. See [local.json](local.json) for
input identity, observations, source hashes and validation scope.

## Exact reproduction

Core revision `7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1` was archived into an
owned OS temporary directory and built with:

```sh
MOON_WORK=off moon test builtin --target wasm-gc --debug --build-only \
  --include-skipped --target-dir "$owned_temp/input-build"
```

The resulting `builtin.blackbox_test.wasm` is 4,568,719 bytes, SHA256
`932992a2ea94328f723cace528eaaf9311d12e20d3be87fedc5d98a3f6c84305`,
matching the issue exactly. It has 9,612 defined functions and five function
imports. One frozen copy was used for every compiler comparison.

A standalone release executable called only the public
`compile_module(bytes, opt_level=2, enable_cancellation=true, on_progress=...)`.
Progress was flushed to distinguish a buffered log from a stopped compiler.
No Store was created, imports were not linked, and no guest was executed.
The published control resolved all twelve Wasmoon-family modules to 0.17.2;
the source control used isolated copies of the current workspace modules.

Processes were sampled for RSS every approximately 250 ms. A diagnostic
ceiling of 6 GiB and a 45-second deadline bounded the reproduction. Crossing
the ceiling terminates an incomplete run; it is not a successful compilation
or a measurement of its eventual peak memory.

| Compiler | Result | Process wall time | Highest sampled RSS |
| --- | --- | ---: | ---: |
| Published 0.17.2 | Stopped at RSS ceiling | 9.18 s | 6.41 GiB |
| Unmodified current source | Stopped at RSS ceiling | 10.49 s | 6.18 GiB |
| Repaired source | All 9,612 functions compiled | 11.14 s | 1.33 GiB |

These are diagnostic observations, not paired throughput estimates. Additional
completed runs also verify the complete returned artifact. The issue's 0.17.1
end-to-end execution comparison was not independently rerun here.

### Wasmtime compilation comparison

The exact input was regenerated and its SHA256 checked again. Wasmtime
49.0.1 (`46c23a87d`) compiled it in three fresh processes per collector:

```sh
wasmtime compile -C compiler=cranelift -C parallel-compilation=n -C cache=n \
  -C collector=drc -O opt-level=2 -W gc=y -W function-references=y \
  -W exceptions=y -W epoch-interruption=y -o "$owned_temp/output.cwasm" \
  "$owned_temp/builtin.blackbox_test.wasm"
```

| Collector | Median process wall time | Median peak RSS |
| --- | ---: | ---: |
| DRC | 4.24 s | 683.25 MiB |
| Copying | 4.51 s | 612.59 MiB |

All six compilations succeeded; each collector produced identical artifact
bytes across its three samples. This measures compilation only, without
instantiation or guest execution. Epoch interruption is enabled as a comparison
with Wasmoon's enabled cancellation checks, not as a claim that the two
mechanisms are identical. Both compilers use serial compilation.

Wasmtime RSS comes from macOS `/usr/bin/time -l` maximum resident set size;
the earlier Wasmoon RSS is a 250 ms sampled maximum. Wasmtime CLI time also
includes output serialization. Therefore the approximately 2.63x wall-time
and 2.00x RSS ratios against DRC are diagnostic comparisons, not a paired,
identical compiler-API benchmark. See [wasmtime.json](wasmtime.json). All
temporary source, build and serialized-artifact directories were removed.

## Established cause

Both failing controls reach function 9615, `____moonbit_init`, after compiling
9,610 of the 9,612 functions. Its backend work is inside the public `Lower`
progress interval: the public API reports `Regalloc` and `Codegen` only after
the backend call returns. The progress label alone cannot identify the
specific backend operation.

A native CPU sample identified repeated
`emit_gc_allocation -> emit_call -> emit_with_metadata -> update_function_roots`
lowering. A separate isolated counter probe established the multiplicative
growth: this function reserves 17,459 root slots, requiring 273 bitmap words.
Every safepoint used to emit a constant and a store for **each** word, even
when only 1–41 roots were live. At update 13,312, the native value table already
contained 3,872,443 entries, and compilation was still incomplete. The counter
probe independently crossed the same RSS ceiling.

The root-frame implementation was introduced in `4c03388b`. Its dense bitmap
emission scales with whole-function root capacity times safepoint count. The
large, allocation-heavy initializer exposes that generated-code expansion.
This reproduction runs no guest, so guest heap growth or a running guest
collector cannot explain it.

## Repair and invariants

Group adjacent equal bitmap words. Runs longer than four words use a native
indexed-store loop with an I32 block parameter; shorter runs retain the
straight-line stores. One-time frame initialization stays in the original
entry block because source lowering binds that entry after frame admission.

Every mask word is still overwritten, including zero words on sibling CFG
paths. The loop makes no call and contains no safepoint or reentry point, so
collection cannot observe a partially published mask. The frame layout,
root-slot assignment, precise live sets and runtime ABI are unchanged. This
does not cache a predecessor's bitmap or assume one CFG predecessor. Generated
work for repeated words is bounded by runs rather than expanded by run length;
arbitrary distinct bitmap words still require individual stores.

## Regression and validation

- A pre-fix failing lowering test uses 8,192 slots and 64 sparse safepoints.
  It bounds emitted stores, protecting against code expansion without a timing
  assertion. The original emitter exceeds the bound.
- Public JIT/Store tests at O0/O2/O3 force real collection with sparse sibling
  paths and dense masks spanning five full bitmap words. The dense case uses
  a tail call to retire the creator's frame, so its live objects depend on the
  callee's mask. Both collection and subsequent reclamation are
  asserted; the cases do not require hundreds of collecting allocations.
- x64 target selection and register allocation verify the generated loop and
  its block parameters. Actual machine-code execution here is ARM64.
- Native 3,068/3,068 and wasm 1,458/1,458 passed. Verification flags were
  `VCODE_REGALLOC_VALIDATION=1`, `WASMOON_GC_VERIFY=1` and
  `WASMOON_GC_ASSERT_BARRIER=1`.
- Fresh release CLI interpreter and JIT each passed all 258 upstream Core files
  and 62,563 assertions with those flags, with zero failures/errors.
- Fresh isolated ASan/UBSan passed 294/294, with both ASan positive controls
  detected. LSan is unavailable on this macOS host. Native C/runtime code is
  instrumented; JIT machine code and MoonBit runtime objects are excluded by
  the existing sanitizer harness.
- `moon info`, `moon fmt`, strict native/wasm checks, the module-boundary audit
  and 178 Python tests passed (54 existing platform skips).

All owned reproduction sources, dependency copies, binaries, samples, logs and
caches are temporary and removed after receipt extraction. `_build` contains
only ordinary Moon outputs. No CI, Windows/x64 execution, or execution of the
original 2,808-test builtin driver is claimed by this local receipt.
