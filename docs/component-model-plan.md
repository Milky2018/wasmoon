# Component Model Plan (MVP)

This document proposes a staged plan to add WebAssembly Component Model support
in Wasmoon while keeping the existing core Wasm pipeline intact.

## Goals

- Parse and validate component binaries and text format inputs.
- Instantiate components that embed or reference core Wasm modules.
- Support canonical ABI adapters (lift/lower) for basic value types.
- Provide a CLI surface for running and testing component inputs.

## Non-goals (for MVP)

- Full async/futures support.
- Resource types beyond basic handles.
- Complete WIT package manager integration.
- Advanced optimization of adapters or cross-component inlining.

## Architecture Alignment

Component model will be layered above the existing core Wasm pipeline:

```
component parser -> component validator -> component runtime/linker
                                 |               |
                                 v               v
                           core wasm parser  runtime/executor/JIT
```

Key idea: component instantiation produces core Wasm modules and adapters that
reuse the existing runtime and execution stacks.

## Proposed Packages (high-level)

- `component/`: AST + IR for component definitions.
- `component_parser/`: binary + text parsing for component model.
- `component_validator/`: type checking, aliasing rules, canonical ABI rules.
- `component_runtime/`: linker/instantiator, adapter dispatch, host bindings.
- `component_types/`: canonicalized type system and WIT mapping.

(Exact package names to be finalized after first parser prototype.)

## Staged Plan

### Phase 0: Scope + CLI Surface

- Add a design doc (this file) and an initial CLI flag plan.
- Decide on file detection: explicit subcommand vs. auto-detect.
- Decide on where component code lives in the repo tree.

### Phase 1: Parsing + IR

- Implement component AST and binary parser for core component sections:
  - type, import/export, alias, component/module, instance, canon, start.
- Add WIT parsing for a minimal subset required by canonical ABI mapping.
- Provide a round-trip dump utility for debugging.

### Phase 2: Validation

- Validate type correctness for component definitions and instantiation.
- Validate canonical ABI lifting/lowering constraints.
- Validate alias/import/export/instance dependency ordering.

### Phase 3: Runtime + Linker

- Instantiate component graphs, resolve imports/exports, build core modules.
- Implement canonical ABI adapters (lift/lower) for basic types.
- Bridge adapters to core Wasm functions and host bindings.
- Ensure compatibility with interpreter and JIT call paths.

### Phase 4: CLI + Tests

- Add `wasmoon component <command>` (exact names TBD).
- Add fixtures and spec tests (component-model WAST/WIT sources).
- Add targeted regression tests for canonical ABI conversions.

## Open Questions

- Binary component format detection (magic/version) vs. explicit CLI flag.
- WIT parsing strategy: minimal in-tree parser vs. external generator.
- Host binding model: map to existing WASI import style or new interface.
- JIT interaction: whether to JIT adapters or keep them in interpreter.

## Success Criteria (MVP)

- Load and instantiate component binaries with nested core modules.
- Execute an exported component function that uses lift/lower.
- Run a small suite of component spec tests in CI.
