# Core runtime regressions

Run the local cross-instance corpus in both engines:

```sh
python3 scripts/run_all_wast.py --dir tests/core --rec
```

The bulk-memory inputs formerly under `myspec/` retain their table initialization,
copy/fill and memory initialization assertions. `fixtures/test_add.wat` and
`fixtures/test_if_add.wat` are standalone arithmetic output probes moved out of
`examples/`; they are CLI inputs, not additional WAST trials.

`callable-context.wast` checks shared globals, callee GC context, cross-module
type identity, bounded native tail calls, precise caller roots during
callee allocation, and exception tags whose module-local indices differ.
The native test `callable_ownership_test.mbt` additionally checks executable
retention until Store retirement after explicit module closure.

`atomic-rmw-operations.wast` covers every RMW operation and width, checking
both the old value and neighboring memory bytes. `trap-kinds.wast` distinguishes
memory, table, array, null-reference, cast, alignment, and conversion failures.
`array-dropped-segments.wast` verifies empty-array allocation and zero-length
bounds checks after dropping data and element segments, including table.init.
These fixtures also pass Wasmtime 40 with GC, function references, threads,
and memory64 enabled.

`atomic-address-boundaries.wast` checks notify bounds without a memory load,
non-shared wait rejection, imported shared memory metadata, and memory64
effective-address overflow. Enable memory64 as well when running it in Wasmtime.
