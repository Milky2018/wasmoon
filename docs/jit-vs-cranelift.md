# Wasmoon JIT vs Cranelift: Comprehensive Comparison

This document provides a detailed comparison between Wasmoon's JIT compiler and Cranelift (Wasmtime's compiler backend).

## Architecture Overview

| Aspect | Wasmoon | Cranelift |
|--------|---------|-----------|
| **Language** | MoonBit | Rust |
| **Target Architectures** | AArch64 only | AArch64, x86_64, RISC-V, s390x |
| **IR Layers** | 2 (IR → VCode) | 2 (CLIF → VCode) |
| **Codebase Size** | ~75,000 lines | ~500,000+ lines |
| **DSL** | None (native MoonBit) | ISLE (custom DSL) |

---

## 1. IR Design

### Wasmoon IR (`ir/ir.mbt`)

```moonbit
pub struct Inst {
  results: Array[Value]
  mut opcode: Opcode
  operands: Array[Value]
}

pub struct Block {
  id: Int
  params: Array[(Value, Type)]  // SSA phi nodes
  instructions: Array[Inst]
  mut terminator: Terminator?
}
```

**Key characteristics:**
- Simple SSA representation with block parameters for phi nodes
- Instructions stored directly in blocks
- ~770 lines for core IR definitions

### Cranelift CLIF (`ir/dfg.rs`)

```rust
pub struct DataFlowGraph {
    insts: PrimaryMap<Inst, InstructionData>,
    blocks: PrimaryMap<Block, BlockData>,
    values: PrimaryMap<Value, ValueDataPacked>,
    value_lists: ValueListPool,  // Shared memory pool
    facts: SecondaryMap<Value, Option<Fact>>,  // PCC assertions
}
```

**Key characteristics:**
- Arena-based allocation with PrimaryMap
- Instructions stored separately from blocks, with Layout for ordering
- Shared ValueListPool for memory efficiency
- 16-byte packed instruction representation
- Proof-Carrying Code (PCC) support via facts

### Comparison

| Feature | Wasmoon | Cranelift |
|---------|---------|-----------|
| **Data Layout** | Array storage | PrimaryMap (arena) |
| **Instruction Storage** | Embedded in Block | Separate store + Layout |
| **Value Lists** | Per-instruction Array | Shared ValueListPool |
| **Type System** | Simple enum | Rich (scalar/vector/reference) |
| **Memory Efficiency** | Moderate | High (16-byte packing) |
| **Phi Nodes** | Block params | Block params |
| **PCC Support** | No | Yes |

**Recommendation:** Consider using FixedArray or arena allocation in Wasmoon to improve memory locality.

---

## 2. Optimization Framework

### Wasmoon E-Graph (`ir/egraph/`)

```moonbit
pub struct EGraph {
  classes: Map[Int, EClass]
  union_find: Map[Int, Int]
  hashcons: Map[ENode, Int]  // GVN
}

// 27 rule files, ~14,940 lines total
// e.g., rules_algebraic.mbt, rules_bitwise.mbt
```

**Characteristics:**
- Traditional e-graph saturation approach
- Rules written as MoonBit functions
- Ruleset rebuilt per block
- No match limits (potential explosion)

### Cranelift E-Graph (`egraph.rs` + ISLE)

```rust
pub struct EgraphPass<'a> {
    func: &'a mut Function,
    domtree: &'a DominatorTree,
    // ...
}

// Hard constraints
const MATCHES_LIMIT: usize = 5;
const ECLASS_ENODE_LIMIT: usize = 5;
```

**ISLE rule example** (`opts/arithmetic.isle`):
```lisp
;; x + 0 == x
(rule (simplify (iadd ty x (iconst_u ty 0)))
      (subsume x))

;; x / 2^n == x >> n
(rule (simplify_skeleton (udiv x (iconst_u ty (u64_extract_power_of_two d))))
      (ushr ty x (iconst_u ty (u64_ilog2 d))))
```

**Characteristics:**
- Single-pass optimization (not saturation)
- ISLE DSL compiles to Rust
- Hard limits prevent explosion
- Integrated GVN and store-to-load forwarding

### Comparison

| Feature | Wasmoon | Cranelift |
|---------|---------|-----------|
| **Approach** | Saturation iteration | Single-pass directional |
| **Rule Language** | MoonBit functions | ISLE DSL |
| **Match Limit** | None | 5 per call |
| **E-class Limit** | None | 5 nodes/class |
| **Rule Count** | ~296 rules | ~200+ rules |
| **Ruleset Rebuild** | Per block | Global singleton |
| **Performance** | May explode | Predictable |

**Recommendations:**
1. Add `MATCHES_LIMIT` and `ECLASS_NODE_LIMIT` constants
2. Use global ruleset singleton
3. Consider single-pass directional design

---

## 3. Register Allocation

### Wasmoon (`vcode/regalloc/`)

```moonbit
struct BacktrackingAllocator {
  ranges: LiveRangeSet
  bundles: BundleSet
  queue: Array[QueueEntry]  // Priority queue
  int_regs: Array[@abi.PReg]
  // ...
}

// ~4000 lines of MoonBit code
```

**Algorithm:** Ion-style backtracking allocator
- Live interval analysis
- Bundle merging (copy coalescing)
- Spill weight priority queue
- Supports backtracking and eviction

### Cranelift (regalloc2 external crate)

```rust
// Uses regalloc2 0.13.3 crate
let regalloc_result = regalloc2::run(
    &vcode,
    vcode.abi.machine_env(),
    &RegallocOptions {
        algorithm: Algorithm::Ion,  // or Fastalloc
        validate_ssa: true,
        // ...
    }
)?;
```

**Algorithm options:**
- **Ion** (backtracking): Better code quality
- **Fastalloc** (single-pass): Faster compilation

### Comparison

| Feature | Wasmoon | Cranelift |
|---------|---------|-----------|
| **Implementation** | Built-in | External crate (regalloc2) |
| **Algorithm** | Ion-style | Ion / Fastalloc selectable |
| **Code Size** | ~4000 lines | ~20,000+ lines (regalloc2) |
| **Validation** | None | Optional Checker |
| **Constraint System** | Simple | Full operand constraints |
| **SSA Destruction** | Manual | Automatic |

**Recommendation:** Wasmoon's allocator is fairly complete. Consider adding a Fastalloc option for debug builds.

---

## 4. Instruction Selection

### Wasmoon Lowering (`vcode/lower/`)

```moonbit
pub fn lower_function(ir_func: @ir.Function) -> @regalloc.VCodeFunction {
  let ctx = LoweringContext::new(ir_func)
  for block in ir_func.blocks {
    for inst in block.instructions {
      lower_instruction(ctx, inst)  // Hand-written pattern matching
    }
  }
  ctx.vcode_func
}

// ~8000 lines of MoonBit code (including patterns.mbt)
```

### Cranelift ISLE (`isa/aarch64/lower.isle`)

```lisp
;; Integer add - base case
(rule iadd_base_case -1
      (lower (has_type (fits_in_64 ty) (iadd x y)))
      (add ty x y))

;; Integer add - immediate right operand
(rule iadd_imm12_right 4
      (lower (has_type (fits_in_64 ty) (iadd x (imm12_from_value y))))
      (add_imm ty x y))

;; Multiply-add fusion
(rule iadd_imul_right 7
      (lower (has_type (fits_in_64 ty) (iadd x (imul y z))))
      (madd ty y z x))
```

**ISLE characteristics:**
- Declarative rules
- Priority system (higher number = higher priority)
- Compile-time type checking
- Automatically generates decision trees

### Comparison

| Feature | Wasmoon | Cranelift |
|---------|---------|-----------|
| **Style** | Imperative MoonBit | Declarative ISLE DSL |
| **Pattern Matching** | Hand-written if/match | Auto decision tree |
| **Rule Priority** | Code order | Explicit numeric priority |
| **Maintainability** | Moderate | High (declarative) |
| **Verifiability** | Low | High (can be formalized) |
| **Code Size** | ~8000 lines | ~140,000 lines ISLE |

**Recommendation:** Long-term, consider developing an ISLE-like DSL for MoonBit.

---

## 5. Code Emission

### Wasmoon Emit (`vcode/emit/`)

```moonbit
pub fn emit_function(func: @regalloc.VCodeFunction) -> Bytes {
  let buffer = Buffer::new()
  emit_prologue(buffer, func)
  for block in func.blocks {
    for inst in block.instructions {
      emit_instruction(buffer, inst)  // Direct encoding
    }
  }
  emit_epilogue(buffer, func)
  buffer.to_bytes()
}

// ~5400 lines of MoonBit code
```

### Cranelift Emit

```rust
impl MachInstEmit for Inst {
    fn emit(&self, state: &mut EmitState, buffer: &mut MachBuffer) {
        match self {
            Inst::AluRRR { alu_op, rd, rn, rm, .. } => {
                // Encoding logic
            }
            // ...
        }
    }
}
```

### Comparison

| Feature | Wasmoon | Cranelift |
|---------|---------|-----------|
| **Instruction Count** | ~100 | ~300+ |
| **SIMD** | Basic | Full SVE/NEON |
| **Code Size** | ~5400 lines | ~15000+ lines |
| **Relocations** | Simple | Full (ELF/Mach-O) |
| **Debug Info** | None | Optional DWARF |

---

## 6. Runtime/FFI

### Wasmoon (`jit/jit_ffi/`)

```moonbit
pub struct JITContext {
  ctx: @jit_ffi.JITContext
  trampoline_cache: Map[Int64, ExecCode]
}

// C FFI for:
// - Executable memory allocation
// - Trap handling
// - Function table management
```

### Cranelift

```rust
// Integrated via wasmtime-runtime crate
// Decoupled from Cranelift, can be used with any backend
```

### Comparison

| Feature | Wasmoon | Cranelift |
|---------|---------|-----------|
| **Runtime Coupling** | Tight | Loose |
| **Trap Handling** | setjmp/longjmp | Signal handling |
| **Memory Management** | Simple mmap | Complex pooling |
| **Thread Safety** | __thread variables | Full TLS |

---

## 7. Compilation Pipeline

### Wasmoon Pipeline

```
WASM → IR Translation → E-Graph Opt → Lowering → RegAlloc → Emit
         (translator)   (egraph_builder) (lower/)  (regalloc/) (emit/)
```

### Cranelift Pipeline

```
WASM → CLIF → Legalize → Mid-End Opt → Lowering (ISLE) → RegAlloc2 → Emit
              (legalize)  (egraph.rs)   (lower.isle)     (external)
```

---

## 8. Performance and Scalability

| Dimension | Wasmoon | Cranelift |
|-----------|---------|-----------|
| **Compile Speed** | Moderate | Fast (single-pass design) |
| **Code Quality** | Good | Very Good |
| **Multi-target** | AArch64 only | 4 targets |
| **Modularity** | Moderate | High (trait abstractions) |
| **Test Coverage** | WAST tests | Filetests + Fuzzing |

---

## 9. Key Differences Summary

### Wasmoon Strengths

1. **Language Consistency**: All MoonBit, no FFI boundaries within compiler
2. **Simplicity**: Smaller codebase, easier to understand
3. **GC Integration**: Native support for MoonBit GC types

### Cranelift Strengths

1. **ISLE DSL**: Declarative instruction selection, highly maintainable
2. **Hard Limits**: Prevents optimization explosion
3. **Multi-target**: Supports 4 architectures
4. **Maturity**: 10+ years of production use
5. **Tooling**: regalloc2 as independent crate

---

## 10. Improvement Recommendations

### Short-term (Low Hanging Fruit)

1. **E-Graph Limits** (`ir/egraph/egraph.mbt`):
   ```moonbit
   let ECLASS_NODE_LIMIT : Int = 5
   let MATCHES_LIMIT : Int = 5
   let REWRITE_DEPTH_LIMIT : Int = 5
   ```

2. **Global Ruleset Singleton** (`ir/egraph/rules_all.mbt`):
   ```moonbit
   let global_indexed_ruleset : Ref[IndexedRuleSet?] = { val: None }

   pub fn get_global_ruleset() -> IndexedRuleSet {
     match global_indexed_ruleset.val {
       Some(rs) => rs
       None => {
         let rs = build_indexed_ruleset()
         global_indexed_ruleset.val = Some(rs)
         rs
       }
     }
   }
   ```

3. **Constant Cache in E-Class** (`ir/egraph/egraph.mbt`):
   ```moonbit
   struct EClass {
     nodes: Array[ENode]
     const_value: Int64?  // O(1) constant lookup
   }
   ```

### Medium-term

4. **Single-Pass Optimization**: Replace saturation with single-pass directional design
5. **Fastalloc Option**: Add fast allocator for debug builds
6. **More Targets**: Consider x86_64 support

### Long-term

7. **MoonBit ISLE**: Develop declarative instruction selection DSL
8. **PCC Support**: Add Proof-Carrying Code infrastructure
9. **Profile-Guided**: Add PGO support

---

## Appendix: Code Size Comparison

### Wasmoon

| Component | Files | Lines | Purpose |
|-----------|-------|-------|---------|
| **IR** | 13 | 13,957 | SSA representation & translation |
| IR/EGraph | 27 | 14,940 | Equality saturation optimization |
| **VCode** | 19 | 33,557 | Virtual code & lowering |
| VCode/RegAlloc | 13 | ~4,000 | Register allocation |
| VCode/Emit | 11 | ~5,400 | AArch64 code generation |
| **JIT** | 19 | 5,248 | Execution & runtime |
| **Total** | ~92 | ~75,000 | Complete JIT implementation |

### Cranelift

| Component | Approximate Lines |
|-----------|-------------------|
| IR Core | ~4,000 |
| E-graph/Opts | ~10,000 |
| ISLE Compiler | ~15,000 |
| AArch64 Backend | ~50,000 |
| regalloc2 | ~20,000 |
| **Total** | ~500,000+ |

---

## References

- Cranelift source: `wasmtime/cranelift/`
- Wasmoon source: `wasmoon/`
- ISLE documentation: `cranelift/isle/README.md`
- regalloc2: External crate for register allocation
