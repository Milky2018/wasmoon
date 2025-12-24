# WebAssembly GC Implementation Plan

## Overview

This document outlines the plan for implementing WebAssembly GC (Garbage Collection) proposal in wasmoon.

## Main Challenges

### 1. Type System Extension

Current state: `ValueType` has GC type variants (`AnyRef`, `ExnRef`, etc.), but `Value` enum lacks object representation.

Challenges:
- Support struct and array type definitions
- Type subtyping relationships (struct inheritance, array covariance)
- Recursive type groups (rec groups) - partially implemented
- Type equivalence - infrastructure exists

### 2. Object Heap Management

Current state: No general object heap, only exception instance storage (can serve as reference pattern).

Challenges:
- Design object memory layout (type header, field storage)
- Object allocator
- Field read/write operations
- Implement GC algorithm (mark-sweep or other)

### 3. New Instructions (~30+)

**struct operations**: `struct.new`, `struct.new_default`, `struct.get`, `struct.get_s`, `struct.get_u`, `struct.set`

**array operations**: `array.new`, `array.new_default`, `array.new_fixed`, `array.new_data`, `array.new_elem`, `array.get`, `array.get_s`, `array.get_u`, `array.set`, `array.len`, `array.fill`, `array.copy`, `array.init_data`, `array.init_elem`

**type casting**: `ref.cast`, `ref.test`, `br_on_cast`, `br_on_cast_fail`

**other**: `any.convert_extern`, `extern.convert_any`, `i31.new`, `i31.get_s`, `i31.get_u`

### 4. JIT Compiler Support

Current state: Complete AArch64 backend exists, reference types map to I64.

Challenges:
- Code generation for object allocation
- Code generation for field access
- Code generation for type checking and casting
- GC safepoints handling

### 5. Parser Modification

Current state: `wat/parser.mbt:2340-2347` parses struct/array but replaces with placeholders.

Challenges:
- Parse field types, mutability correctly
- Parse array element types
- Parse type inheritance relationships

---

## Implementation Phases

### Phase 1: Type System Foundation

**Goal**: Support struct/array type definitions and storage

- [ ] Extend `types/types.mbt` to add:
  - `StructType { fields: Array[FieldType] }`
  - `ArrayType { element: FieldType }`
  - `FieldType { mutable: Bool, type: StorageType }`
  - `StorageType = I8 | I16 | ValueType`
- [ ] Modify `wat/parser.mbt` to correctly parse struct/array
- [ ] Update `validator/` to validate new type definitions
- [ ] Add WAST test cases

### Phase 2: Object Runtime

**Goal**: Implement object allocation and field access

- [ ] Add `heap.mbt` in `runtime/`:
  - `GCObject` structure (type index + field array)
  - `GCHeap` to manage object storage
  - Allocation/access API
- [ ] Extend `Value` enum to add `GCRef(Int)` variant
- [ ] Update `Store` to integrate object heap

### Phase 3: Interpreter Support

**Goal**: Execute GC instructions in interpreter

- [ ] Implement struct instructions in `executor/`:
  - `struct.new`, `struct.new_default`
  - `struct.get`, `struct.set`
- [ ] Implement array instructions:
  - `array.new`, `array.new_default`, `array.new_fixed`
  - `array.get`, `array.set`, `array.len`
- [ ] Implement type casting instructions:
  - `ref.cast`, `ref.test`
  - `br_on_cast`, `br_on_cast_fail`
- [ ] Implement i31 related instructions

### Phase 4: GC Algorithm

**Goal**: Implement garbage collection

- [ ] Implement simple mark-sweep GC:
  - Mark phase: traverse from root set (stack, globals, tables)
  - Sweep phase: reclaim unmarked objects
- [ ] Add GC trigger points (check on object allocation)

### Phase 5: JIT Support

**Goal**: JIT compile GC instructions

- [ ] Extend IR to support object operations
- [ ] Implement VCode lowering:
  - Object allocation calls
  - Field access code
  - Type checking code
- [ ] Handle GC safepoints

### Phase 6: Polish and Testing

- [ ] Run WebAssembly GC spec tests
- [ ] Performance optimization
- [ ] Edge case handling

---

## Priority

| Phase | Complexity | Dependencies |
|-------|------------|--------------|
| Phase 1 Type System | Medium | None |
| Phase 2 Object Runtime | High | Phase 1 |
| Phase 3 Interpreter | Medium | Phase 2 |
| Phase 4 GC | High | Phase 2, 3 |
| Phase 5 JIT | High | Phase 1-4 |
| Phase 6 Polish | Medium | Phase 1-5 |

---

## References

- [WebAssembly GC Proposal](https://github.com/WebAssembly/gc)
- [GC Overview](https://github.com/WebAssembly/gc/blob/main/proposals/gc/Overview.md)
- [Chrome WasmGC Blog](https://developer.chrome.com/blog/wasmgc)
- [V8 WasmGC Porting Guide](https://v8.dev/blog/wasm-gc-porting)
