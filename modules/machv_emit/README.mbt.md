# machv_emit

Reusable MachV machine-code emitter.

`machv_emit` turns allocated MachV functions into machine-code objects and
relocation/fixup metadata. It is intended for embedders that want to supply
their own runtime-symbol resolution and executable-memory policy.

## Packages

- `Milky2018/machv_emit`: machine-code objects, emission entry points,
  stack-frame handling, relocation/fixup metadata, and target dispatch.
- `Milky2018/machv_emit/isaregs`: emitter-facing ISA register helpers.

## Boundary

Emitters should produce code plus symbolic metadata. Wasmoon-specific runtime
helper lookup, JIT context ownership, and native FFI glue belong in
`wasmoon_jit`.
