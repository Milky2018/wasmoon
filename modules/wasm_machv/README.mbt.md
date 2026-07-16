# Wasm MachV Lowering

`Milky2018/wasm_machv` validates WebAssembly-specific MilkIR extensions and
lowers them into target-neutral MachV. It does not select AArch64 or AMD64
instructions, apply a native ABI, or depend on the Wasmoon runtime.

The embedding environment supplies opaque internal function identities and,
as later operation families are migrated, the semantic runtime capabilities
required by WebAssembly memory, tables, GC, and exceptions.
