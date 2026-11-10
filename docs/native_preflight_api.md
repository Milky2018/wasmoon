# Migration from the Native Preflight API

The unused `Milky2018/wasmoon/preflight` package is retired. It maintained a
separate, x64-only compilation probe that no repository runtime or CLI consumed.
This is a source API removal; external callers must migrate.

For binary parsing and WebAssembly validation, use
`Milky2018/wasm_core/parser.parse_module` and
`Milky2018/wasm_core/validator.validate_module`. Both report structured errors.

For native compilation checks, use the production frontend and
`wasmoon_jit.NativeCompiler::compile_wasm_body_artifact_function` with the
intended target and embedding context. See the
[library migration guidance](../modules/wasmoon/README.mbt.md#library-usage).
Compilation produces code objects; installation and execution remain separate
operations. There is no second preflight pipeline or stage-report vocabulary.
