# MilkIR optimization

This package owns the target-independent optimization pipeline. It consumes
`@milkir.Function` and mutates its authoritative DFG without copying it into
another expression graph. It is part of the `Milky2018/milkir` module.

Import both packages in the caller's `moon.pkg`:

```moonbit nocheck
///|
import {
  "Milky2018/milkir",
  "Milky2018/milkir/optimize",
}
```

Call `@optimize.optimize(func)` for O2, or
`@optimize.optimize_with_level(func, level)` with `O0`, `O1`, `O2` or `O3`.
The returned `OptResult.changed` reports whether a transformation changed the
function. Input must already satisfy MilkIR's SSA and block-parameter contracts.

See the [module guide](../README.mbt.md#optimization) for an executable example,
optimization-level contracts and checked loop-unrolling limits, and the
[optimizer design](../../../docs/milkir-optimizer.md) for implementation details.

The public surface consists of pipeline entry points, level/result types,
instruction counting and an optional embedder-owned metrics sink. Rules, value
numbering tables, analysis caches and candidate transactions remain private.
