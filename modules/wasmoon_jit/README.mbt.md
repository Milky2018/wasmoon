# wasmoon_jit

Wasmoon-specific JIT integration and native runtime glue.

`wasmoon_jit` connects the reusable compiler infrastructure to Wasmoon's
runtime embedding. It owns VMContext layout details, native runtime helpers,
cwasm artifacts, trampolines, WASI bridge glue, and integration planning for
loading generated code into Wasmoon.

## Packages

- `Milky2018/wasmoon_jit`: runtime layout, JIT integration planning,
  trampolines, native glue, runtime symbols, and helper APIs.
- `Milky2018/wasmoon_jit/cwasm`: serialized precompiled-code artifacts.
- `Milky2018/wasmoon_jit/perf`: optional JIT performance metrics.
- `Milky2018/wasmoon_jit/jit_ffi`: native stubs used by the JIT runtime.

## Boundary

This module is intentionally Wasmoon-owned. Generic compiler infrastructure
should remain in `milkir`, `machv`, `regalloc`, `machv_regalloc`,
`machv_emit`, and target modules.
