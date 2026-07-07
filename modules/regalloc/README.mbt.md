# regalloc

Target-independent register allocation algorithm.

`regalloc` models allocation programs, machine environments, live ranges,
allocation decisions, move resolution, spill planning, and verification without
depending on a concrete machine IR.

## Package

- `Milky2018/regalloc`: allocation data structures, allocator entry points,
  policy helpers, and verifier APIs.

## Boundary

This module should stay a pure algorithmic layer. Machine-IR-specific adapters
belong in modules such as `machv_regalloc`.
