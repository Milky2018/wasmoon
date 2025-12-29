# Wasmoon Architecture

Wasmoon is a WebAssembly runtime written in MoonBit with JIT compilation support for AArch64.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         wasmoon CLI                             │
├─────────────────────────────────────────────────────────────────┤
│  WAT Parser    │  WAST Parser   │  Binary Parser (cwasm)        │
├─────────────────────────────────────────────────────────────────┤
│                      Validator                                  │
├─────────────────────────────────────────────────────────────────┤
│                       Runtime                                   │
├────────────────────────┬────────────────────────────────────────┤
│      Interpreter       │              JIT Compiler              │
│      (executor)        │  ┌──────────────────────────────────┐  │
│                        │  │  IR → VCode → Machine Code       │  │
│                        │  │  (ir)  (vcode)    (jit)          │  │
│                        │  └──────────────────────────────────┘  │
└────────────────────────┴────────────────────────────────────────┘
```

## Package Structure

### Frontend (Parsing)

| Package | Description |
|---------|-------------|
| `wat/` | WAT (WebAssembly Text) parser |
| `wast/` | WAST (WebAssembly Script) parser for testing |
| `cwasm/` | Binary WebAssembly parser |
| `parser/` | Common parser utilities |

### Validation

| Package | Description |
|---------|-------------|
| `validator/` | WebAssembly module validation |
| `types/` | Type definitions (ValType, FuncType, etc.) |

### Execution

| Package | Description |
|---------|-------------|
| `runtime/` | Runtime structures (Module, Instance, Store, Memory, Table, Global) |
| `executor/` | Interpreter implementation |

### JIT Compilation

| Package | Description |
|---------|-------------|
| `ir/` | Intermediate representation (SSA-based IR) |
| `vcode/` | Virtual code generation and register allocation |
| `jit/` | Machine code emission and FFI |

### Other

| Package | Description |
|---------|-------------|
| `wasi/` | WASI (WebAssembly System Interface) implementation |
| `disasm/` | Disassembler for debugging |
| `main/` | CLI entry point |
| `testsuite/` | Test suite |

## Execution Flow

### Interpreter Mode

1. Parse WAT/WASM → AST
2. Validate module
3. Instantiate module (create runtime structures)
4. Execute instructions directly via interpreter

### JIT Mode

1. Parse WAT/WASM → AST
2. Validate module
3. Lower to IR (SSA form)
4. Optimize IR (DCE, CSE, constant folding)
5. Lower to VCode (virtual instructions)
6. Register allocation
7. Emit machine code (AArch64)
8. Execute native code

## Key Design Decisions

### SSA-based IR

The IR uses Static Single Assignment form for easier optimization:
- Each value is defined exactly once
- Phi nodes handle control flow merges
- Enables standard optimizations (DCE, CSE, constant propagation)

### VCode (Virtual Code)

VCode is a low-level IR designed for efficient code generation:
- Virtual registers (infinite)
- Platform-specific instructions
- Linear scan register allocation
- Direct mapping to machine instructions

### ABI Compatibility

The JIT uses a custom ABI compatible with the C FFI:
- X0: callee VMContext
- X1: caller VMContext
- X2-X7: integer parameters
- V0-V7: float parameters
- X19: cached VMContext (callee-saved)

See [jit-abi.md](jit-abi.md) for details.
