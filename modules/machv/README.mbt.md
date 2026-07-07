# machv

Reusable virtual-register machine IR.

`machv` models low-level machine code before final register allocation and
emission. It provides virtual registers, physical-register descriptions,
machine instructions, blocks, ABI data, target ISA descriptors, printing, and
verification helpers.

## Packages

- `Milky2018/machv`: root facade for machine functions and common helpers.
- `Milky2018/machv/abi`: ABI locations, registers, calling-convention data,
  and runtime-context layout abstractions.
- `Milky2018/machv/instr`: virtual machine instruction and terminator model.
- `Milky2018/machv/block`: basic-block representation.
- `Milky2018/machv/isa`: generic ISA descriptions and target selection.
- `Milky2018/machv/isa/aarch64`, `Milky2018/machv/isa/amd64`: target-specific
  register descriptions.

## Boundary

`machv` should remain independent from Wasmoon. Product-specific runtime
symbols, WASI, VMContext fields, and native FFI glue belong in embedding
modules such as `wasmoon_jit`.
