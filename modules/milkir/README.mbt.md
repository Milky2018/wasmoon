# milkir

Reusable Cranelift-like SSA intermediate representation.

`milkir` provides compiler IR data structures, builders, verification, CFG
helpers, printing, and optimization passes. It is intended as a reusable
middle-end layer for MoonBit compiler projects.

## Package

- `Milky2018/milkir`: SSA values, blocks, instructions, terminators,
  signatures, `IRBuilder`, verification, CFG utilities, and optimization
  drivers.

## Boundary

`milkir` is generic compiler infrastructure. It should not depend on Wasmoon
runtime concepts, VMContext layouts, WASI, or machine-code emission.
