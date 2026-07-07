# isa_target

Generic ISA lowering from MilkIR to MachV.

This module contains reusable lowering infrastructure shared by concrete
machine targets. It translates `Milky2018/milkir` functions into
`Milky2018/machv` virtual-register machine functions, with target-specific
details supplied by target modules.

## Packages

- `Milky2018/isa_target/lower`: core lowering pipeline from MilkIR to MachV.
- `Milky2018/isa_target/lower/peephole`: post-lowering machine-level cleanup
  and peephole utilities.

## Boundary

`isa_target` is compiler infrastructure. It should not own embedding-specific
runtime helper addresses, Wasmoon host functions, or native FFI resolution.
