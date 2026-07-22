# MachV Migration Result

The migration established one target-neutral semantic MachV layer followed by
independent AArch64 and x64 Target VCode pipelines.

## Final pipeline

```text
MilkIR
  -> semantic MachV
  -> AArch64 Target VCode or x64 Target VCode
  -> generic register allocator adapter
  -> target frame planning
  -> target machine-code emitter
  -> unlinked code object
  -> Wasmoon JIT integration
```

Semantic MachV owns typed values, CFG, calls, effects, traps, safepoints, and
target-neutral operations. It does not contain target conditions, registers,
addressing modes, or encodings.

Each target owns its instruction type, verifier, ABI legalization, allocation
policy, frame layout, encoding, relocations, and linker. The generic
`machv/vcode` package supplies the typed container and allocation side tables;
`machv_regalloc` exposes that representation directly through the reusable
allocator's read-only `FunctionView`, without copying the CFG or inspecting
target instructions.

Wasmoon enters native compilation through `wasmoon_jit`. The product layer
provides VMContext field paths, runtime symbols, v9 artifact production and
installation, and entry/hostcall trampolines, while reusable compiler modules
remain independent of Wasmoon.

## Migration outcome

- AArch64 and x64 production JIT compilation both pass through semantic MachV
  and their respective Target VCode pipelines.
- Both production targets explicitly use the verified backtracking allocator;
  `SinglePass` is not a runtime fallback.
- Diagnostics and `explore --stage machv` use the same semantic path as
  production compilation.
- The retired shared target-opcode backend, its compatibility adapters, and
  its allocation/emission packages were removed in the x64 cutover.
- Target code objects carry bytes, relocations, frame size, traps, safepoints,
  and stack-map information across the product boundary.

This document replaces the pre-migration coupling inventory recorded by
[ISS-184](../issues/ISS-184.md).

The migration is validated against the current architecture's correctness,
ABI, metadata, artifact, and dependency contracts. Retired backends are not
rebuilt as performance or code-size acceptance baselines.
