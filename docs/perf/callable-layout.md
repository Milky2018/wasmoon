# Compact bound-callable storage

Tracking: [ISS-682](../../issues/ISS-682.md), part of PR582.

## Cause and ownership

Module bodies already have a transactional code installation. Their context
bindings previously installed one tiny leaf per function:36 bytes on ARM64,
23 bytes on x64, rounded to a whole executable page. Actual ARM64 entries are
16 KiB apart. A public64-target dispatch control returns every expected value
before the change but fails a4KiB address-span bound.

`NativeCallableBatch` writes the existing absolute context/target instructions
into one immutable installation, with16-byte entry alignment. It retains the
context and owns the installation plus entry offsets. Zero targets stay absent.
There is no global pool, writable shared page, target cache or new machine ABI.
Standalone bindings retain their existing API. Target bodies remain borrowed;
their owner must outlive the binding, as before. JITModule releases the batch
through its existing Store callable-owner/deferred-close protocol. Host-import
trampolines remain separate; this change only covers context bindings.

## Paired measurements

Five alternating serial cold pairs compare frozen release binaries on macOS
ARM64: parent eed13b42, SHA256 prefix3120a077bdf5; candidate0f0595811dc5.
No concurrent build, test or profiler runs. Generated controls assert the sum
of every call and expose mutable state capable of changing a table entry.
Each process uses an independent empty compilation cache.

|100million checked calls|Parent invocation|Packed invocation|
|---|---:|---:|
|1target|669.729 ms|676.151 ms|
|2targets|679.830 ms|677.883 ms|
|64targets|1357.725 ms|702.166 ms|

The64-target installation falls336 ->144 us and whole-process peak RSS
8.04 ->7.00 MB. One/two targets have no stable execution benefit. The same
64-target control takes228.573 ms in optimized V8; Wasmtime cold wall is
239.767 ms, a different boundary from the invocation timer. This is a scoped
layout gain, not general execution parity.

Original randombytes/metamorphic/stream invocation changes by less than0.4%;
installation medians improve563 ->393 /861 ->626 /723 ->526 us. Compiler-only
medians remain essentially unchanged. Regenerate controls with
`scripts/benchmark_indirect_calls.py`; raw samples/builds/caches are temporary.

## Validation boundary

The public layout regression exercises all64 entries through actual indirect
calls. A binding API regression covers empty batches, holes, invalid indices,
whole-batch idempotent release and an unaffected standalone installation.
Existing cross-context, table mutation, retained-owner, tail/hidden-result and
resource regressions remain required. Local ordinary and verified native pass
3115/3115; wasm1464/1464 and strict checks pass. Core258/62563 and Component59/1385 per engine pass with all three verification
flags and zero skips. Fresh isolated macOS ASan/UBSan320, event loop and both
ASan controls pass on explicitly dirty eed13b42-based sources. Boundary, MSVC
bridge, C44 and Python180(54 existing platform skips) pass. Linux LSan and
Windows/x64 execution remain separate CI gates. The final release CLI matches
the measured hash.
