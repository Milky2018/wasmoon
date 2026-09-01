# Wasm native lowering

`Milky2018/wasm_native` validates WebAssembly-specific MilkIR extensions and
streams target-neutral native operations into an AArch64 or x64 target sink.
It does not own a second function graph, select concrete instructions, or
depend on the Wasmoon runtime.

The embedding environment supplies opaque internal function identities and,
as later operation families are migrated, the semantic runtime capabilities
required by WebAssembly memory, tables, GC, and exceptions.

`lower_to_sink` also requires a short-lived `WasmValidationContext` supplied
by the Wasm frontend adapter. It resolves linked function signatures and
module-local type, table, aggregate, tag, memory, and segment contracts before
instruction selection. The context is not retained by the lowering stream.
