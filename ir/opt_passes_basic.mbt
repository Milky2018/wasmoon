// IR Optimization Passes
// Implements target-independent optimizations on the high-level IR

///|
/// Result of an optimization pass
pub struct OptResult {
  mut changed : Bool // Whether the IR was modified
} derive(Eq)

///|
pub fn OptResult::new() -> OptResult {
  { changed: false }
}

///|
/// Mark that the IR was changed
pub fn OptResult::mark_changed(self : OptResult) -> Unit {
  self.changed = true
}

// ============ Dead Code Elimination ============

///|
/// Dead Code Elimination (DCE)
/// Removes instructions whose results are never used
pub fn eliminate_dead_code(func : Function) -> OptResult {
  let result = OptResult::new()
  // Build use counts for all values
  let use_counts = compute_use_counts(func)
  // Iterate until fixed point
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      // Remove dead instructions (iterate backwards to handle chains)
      let mut i = block.instructions.length() - 1
      while i >= 0 {
        let inst = block.instructions[i]
        if inst.first_result() is Some(v) {
          // If the result is never used and the instruction has no side effects
          if use_counts.get(v.id).unwrap_or(0) == 0 && !has_side_effects(inst) {
            // Remove this instruction
            block.instructions.remove(i) |> ignore
            // Decrement use counts for operands
            for op in inst.operands {
              let count = use_counts.get(op.id).unwrap_or(0)
              if count > 0 {
                use_counts.set(op.id, count - 1)
              }
            }
            changed = true
            result.mark_changed()
          }
        }
        i = i - 1
      }
    }
  }
  result
}

///|
/// Compute use counts for all values in a function
fn compute_use_counts(func : Function) -> @hashmap.HashMap[Int, Int] {
  let counts : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for block in func.blocks {
    // Count uses in instructions
    for inst in block.instructions {
      for op in inst.operands {
        let count = counts.get(op.id).unwrap_or(0)
        counts.set(op.id, count + 1)
      }
    }
    // Count uses in terminator
    if block.terminator is Some(term) {
      for v in get_terminator_uses(term) {
        let count = counts.get(v.id).unwrap_or(0)
        counts.set(v.id, count + 1)
      }
    }
  }
  counts
}

///|
/// Get values used by a terminator
fn get_terminator_uses(term : Terminator) -> Array[Value] {
  match term {
    Jump(_, args) => args
    Brz(cond, _, _) | Brnz(cond, _, _) => [cond]
    BrTable(index, _, _) => [index]
    Return(values) => values
    Trap(_) => []
  }
}

///|
/// Check if an instruction has side effects
fn has_side_effects(inst : Inst) -> Bool {
  match inst.opcode {
    // StorePtr has side effects (modifies memory)
    StorePtr(_) | StorePtrNarrow(_) => true
    // LoadPtr has side effects (can trap on null pointer)
    LoadPtr(_) | LoadPtrNarrow(_, _, _) => true
    // Calls may have side effects
    Call(_)
    | CallIndirect(_)
    | CallRef(_)
    | ReturnCall(_)
    | ReturnCallIndirect(_, _)
    | ReturnCallRef(_) => true
    // Memory operations that modify global state
    MemoryGrow(_, _) | MemoryFill(_) | MemoryCopy(_, _) => true
    // Memory base reads global state and must not be CSE'd across calls/grow
    LoadMemBase(_) => true
    // MemorySize reads global state that can change (invalidated by MemoryGrow)
    // Must not be CSE'd across MemoryGrow calls
    MemorySize(_) => true
    // Table operations that modify global state
    TableGrow(_) => true
    // NOTE: GlobalGet, GlobalSet are desugared via FuncEnvironment to LoadPtr/StorePtr
    // Division/remainder can trap on divide-by-zero or overflow (INT_MIN / -1)
    Sdiv | Udiv | Srem | Urem => true
    // Float-to-int conversion can trap on NaN or out-of-range values
    FcvtToSint | FcvtToUint => true
    // GC operations that allocate memory - each call allocates a new object
    StructNew(_) | StructNewDefault(_) => true
    ArrayNew(_) | ArrayNewDefault(_) | ArrayNewFixed(_, _) => true
    // GC segment ops can allocate and/or trap (bounds checks, dropped segments, etc.)
    ArrayNewData(_, _) | ArrayNewElem(_, _) => true
    // GC operations that modify state
    StructSet(_, _) | ArraySet(_) | ArrayFill(_) | ArrayCopy(_, _) => true
    ArrayInitData(_, _) | ArrayInitElem(_, _) => true
    // GC read operations can trap on null reference
    StructGet(_, _) | StructGetS(_, _, _) | StructGetU(_, _, _) => true
    ArrayGet(_) | ArrayGetS(_, _) | ArrayGetU(_, _) | ArrayLen => true
    // GC type check operations can trap
    RefCast(_, _) => true
    // CallPtr can have side effects (calls arbitrary functions)
    CallPtr(_, _) => true
    // Exception handling operations - TryTableBegin calls setjmp which returns
    // different values on normal entry vs exception catch, so it's not pure
    TryTableBegin(_) | TryTableEnd(_) => true
    // Throw operations have control flow side effects
    Throw(_) | ThrowRef => true
    // GetExceptionTag reads global exception state
    GetExceptionTag => true
    // Spill/restore locals interact with exception handling state
    SpillLocalsForThrow(_) | GetSpilledLocal(_) => true
    // Other instructions are pure
    _ => false
  }
}

// ============ Constant Folding ============

///|
/// Constant Folding
/// Evaluates constant expressions at compile time
pub fn fold_constants(func : Function) -> OptResult {
  let result = OptResult::new()
  // Map from value id to constant value (if known)
  let constants : @hashmap.HashMap[Int, ConstValue] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      // First, record any constant instruction
      match inst.opcode {
        Iconst(v) =>
          match inst.first_result() {
            Some(r) =>
              if r.ty is I32 {
                constants.set(r.id, ConstValue::I32(v.to_int()))
              } else {
                constants.set(r.id, ConstValue::I64(v))
              }
            None => ()
          }
        Fconst(v) =>
          match inst.first_result() {
            Some(r) =>
              if r.ty is F32 {
                // F32 bits are packed in the lower 32 bits of the Double's bit representation
                // Extract them directly to preserve NaN payloads
                let f32_bits = v.reinterpret_as_int64().to_int()
                constants.set(
                  r.id,
                  ConstValue::F32(Float::reinterpret_from_int(f32_bits)),
                )
              } else {
                constants.set(r.id, ConstValue::F64(v))
              }
            None => ()
          }
        _ => ()
      }
      // Then try to fold the instruction
      if try_fold_constant(inst, constants) is Some(const_val) &&
        inst.first_result() is Some(v) {
        constants.set(v.id, const_val)
        // Replace instruction with constant
        inst.opcode = const_val.to_opcode()
        // Clear operands since this is now a constant
        inst.operands.clear()
        result.mark_changed()
      }
    }
  }
  result
}

///|
/// Constant value representation
priv enum ConstValue {
  I32(Int)
  I64(Int64)
  F32(Float)
  F64(Double)
}

///|
/// Convert constant value to opcode
fn ConstValue::to_opcode(self : ConstValue) -> Opcode {
  match self {
    I32(v) => Opcode::Iconst(v.to_int64())
    I64(v) => Opcode::Iconst(v)
    F32(v) => {
      // Pack F32 bits into Double's bit representation to preserve NaN payloads
      let f32_bits = v.reinterpret_as_int().to_int64()
      Opcode::Fconst(f32_bits.reinterpret_as_double())
    }
    F64(v) => Opcode::Fconst(v)
  }
}

///|
/// Try to fold an instruction to a constant
fn try_fold_constant(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  match inst.opcode {
    // Constants are already folded
    Iconst(_) | Fconst(_) => None
    // Binary integer operations
    Iadd => fold_binary_int(inst, constants, fn(a, b) { a + b })
    Isub => fold_binary_int(inst, constants, fn(a, b) { a - b })
    Imul => fold_binary_int(inst, constants, fn(a, b) { a * b })
    Sdiv => fold_sdiv(inst, constants)
    Udiv => fold_udiv(inst, constants)
    // Bitwise operations
    Band => fold_binary_int(inst, constants, fn(a, b) { a & b })
    Bor => fold_binary_int(inst, constants, fn(a, b) { a | b })
    Bxor => fold_binary_int(inst, constants, fn(a, b) { a ^ b })
    Ishl => fold_ishl(inst, constants)
    Sshr => fold_sshr(inst, constants)
    Ushr => fold_ushr(inst, constants)
    Srem => fold_srem(inst, constants)
    Urem => fold_urem(inst, constants)
    // Float operations
    Fadd => fold_binary_float(inst, constants, fn(a, b) { a + b })
    Fsub => fold_binary_float(inst, constants, fn(a, b) { a - b })
    Fmul => fold_binary_float(inst, constants, fn(a, b) { a * b })
    Fdiv => fold_binary_float(inst, constants, fn(a, b) { a / b })
    // Comparisons
    Icmp(cc) => fold_icmp(inst, constants, cc)
    _ => None
  }
}

///|
/// Get constant value for a value
fn get_const(
  v : Value,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  constants.get(v.id)
}

///|
/// Fold binary integer operation
fn fold_binary_int(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Int64, Int64) -> Int64,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(I32(va)), Some(I32(vb))) =>
      Some(ConstValue::I32(op(va.to_int64(), vb.to_int64()).to_int()))
    (Some(I64(va)), Some(I64(vb))) => Some(ConstValue::I64(op(va, vb)))
    _ => None
  }
}

///|
/// Fold binary float operation
fn fold_binary_float(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Double, Double) -> Double,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(F32(va)), Some(F32(vb))) =>
      Some(
        ConstValue::F32(
          op(va.to_double(), vb.to_double()) |> Float::from_double,
        ),
      )
    (Some(F64(va)), Some(F64(vb))) => Some(ConstValue::F64(op(va, vb)))
    _ => None
  }
}

///|
/// Fold integer comparison
fn fold_icmp(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  cc : IntCC,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(I32(va)), Some(I32(vb))) => {
      let result = eval_icmp_i32(cc, va, vb)
      Some(ConstValue::I32(if result { 1 } else { 0 }))
    }
    (Some(I64(va)), Some(I64(vb))) => {
      let result = eval_icmp_i64(cc, va, vb)
      Some(ConstValue::I32(if result { 1 } else { 0 }))
    }
    _ => None
  }
}

///|
fn fold_ishl(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => Some(ConstValue::I32(a << (b % 32)))
    (Some(I64(a)), Some(I64(b))) =>
      Some(ConstValue::I64(a << (b.to_int() % 64)))
    _ => None
  }
}

///|
fn fold_sshr(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => Some(ConstValue::I32(a >> (b % 32)))
    (Some(I64(a)), Some(I64(b))) =>
      Some(ConstValue::I64(a >> (b.to_int() % 64)))
    _ => None
  }
}

///|
fn fold_ushr(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) => {
      let shift = b % 32
      let result = (a.reinterpret_as_uint() >> shift)
        |> UInt::reinterpret_as_int
      Some(ConstValue::I32(result))
    }
    (Some(I64(a)), Some(I64(b))) => {
      let shift = b.to_int() % 64
      let result = (a.reinterpret_as_uint64() >> shift).reinterpret_as_int64()
      Some(ConstValue::I64(result))
    }
    _ => None
  }
}

///|
fn fold_sdiv(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else if a == -2147483648 && b == -1 {
        None
      } else {
        Some(ConstValue::I32(a / b))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else if a == -9223372036854775808L && b == -1L {
        None
      } else {
        Some(ConstValue::I64(a / b))
      }
    _ => None
  }
}

///|
fn fold_udiv(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else {
        let result = (a.reinterpret_as_uint() / b.reinterpret_as_uint())
          |> UInt::reinterpret_as_int
        Some(ConstValue::I32(result))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        let result = (a.reinterpret_as_uint64() / b.reinterpret_as_uint64())
          |> UInt64::reinterpret_as_int64
        Some(ConstValue::I64(result))
      }
    _ => None
  }
}

///|
fn fold_srem(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else {
        Some(ConstValue::I32(a % b))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        Some(ConstValue::I64(a % b))
      }
    _ => None
  }
}

///|
fn fold_urem(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  match
    (
      get_const(inst.operands[0], constants),
      get_const(inst.operands[1], constants),
    ) {
    (Some(I32(a)), Some(I32(b))) =>
      if b == 0 {
        None
      } else {
        let result = (a.reinterpret_as_uint() % b.reinterpret_as_uint())
          |> UInt::reinterpret_as_int
        Some(ConstValue::I32(result))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        let result = (a.reinterpret_as_uint64() % b.reinterpret_as_uint64())
          |> UInt64::reinterpret_as_int64
        Some(ConstValue::I64(result))
      }
    _ => None
  }
}

///|
/// Evaluate i32 comparison
fn eval_icmp_i32(cc : IntCC, a : Int, b : Int) -> Bool {
  match cc {
    Eq => a == b
    Ne => a != b
    Slt => a < b
    Sle => a <= b
    Sgt => a > b
    Sge => a >= b
    Ult => a.reinterpret_as_uint() < b.reinterpret_as_uint()
    Ule => a.reinterpret_as_uint() <= b.reinterpret_as_uint()
    Ugt => a.reinterpret_as_uint() > b.reinterpret_as_uint()
    Uge => a.reinterpret_as_uint() >= b.reinterpret_as_uint()
  }
}

///|
/// Evaluate i64 comparison
fn eval_icmp_i64(cc : IntCC, a : Int64, b : Int64) -> Bool {
  match cc {
    Eq => a == b
    Ne => a != b
    Slt => a < b
    Sle => a <= b
    Sgt => a > b
    Sge => a >= b
    Ult => a.reinterpret_as_uint64() < b.reinterpret_as_uint64()
    Ule => a.reinterpret_as_uint64() <= b.reinterpret_as_uint64()
    Ugt => a.reinterpret_as_uint64() > b.reinterpret_as_uint64()
    Uge => a.reinterpret_as_uint64() >= b.reinterpret_as_uint64()
  }
}

// ============ Copy Propagation ============

///|
/// Copy Propagation
/// Replaces uses of copied values with the original value
/// Note: This is local copy propagation - only propagates within the same basic block
/// to avoid incorrectly using values from non-dominating blocks (e.g., sibling branches)
pub fn propagate_copies(func : Function) -> OptResult {
  let result = OptResult::new()
  // Process each block independently to avoid cross-block copy propagation issues
  for block in func.blocks {
    // Map from copy destination to copy source (local to this block)
    let copies : @hashmap.HashMap[Int, Value] = @hashmap.new()
    // First pass: collect copy instructions in this block
    for inst in block.instructions {
      if inst.opcode is Copy &&
        inst.first_result() is Some(dest) &&
        inst.operands.length() > 0 {
        copies.set(dest.id, inst.operands[0])
      }
    }
    // Second pass: replace uses of copied values in this block
    for inst in block.instructions {
      for i, op in inst.operands {
        if resolve_copy(op, copies) is Some(resolved) && resolved.id != op.id {
          inst.operands[i] = resolved
          result.mark_changed()
        }
      }
    }
    // Also update terminator operands
    if block.terminator is Some(term) {
      let new_term = propagate_copies_in_terminator(term, copies, result)
      block.terminator = Some(new_term)
    }
  }
  result
}

///|
/// Alias/copy canonicalization pass.
/// Resolves visible copy chains along the dominator tree and rewrites operands
/// to canonical values (Cranelift analogue: `resolve_all_aliases()`).
pub fn canonicalize_aliases(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  // Build CFG and compute dominators.
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping.
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Active alias environment for the current dominator-tree path.
  let aliases : @hashmap.HashMap[Int, Value] = @hashmap.new()
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track aliases introduced in this block so we can pop on exit.
    let local_aliases : Array[Int] = []
    for inst in block.instructions {
      // Canonicalize operands through currently visible alias chain.
      for i, op in inst.operands {
        if resolve_copy(op, aliases) is Some(resolved) && resolved.id != op.id {
          inst.operands[i] = resolved
          result.mark_changed()
        }
      }
      // If this instruction defines a copy, make its destination an alias.
      if inst.opcode is Copy &&
        inst.first_result() is Some(dest) &&
        inst.operands.length() > 0 {
        aliases.set(dest.id, inst.operands[0])
        local_aliases.push(dest.id)
      }
    }
    // Canonicalize terminator operands as well.
    if block.terminator is Some(term) {
      let new_term = propagate_copies_in_terminator(term, aliases, result)
      block.terminator = Some(new_term)
    }
    // Recurse into dominated children.
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Pop this block's aliases.
    for id in local_aliases {
      aliases.remove(id)
    }
  }

  // Start DFS from entry block (block 0).
  if cfg.is_valid(0) {
    dfs(0)
  }
  result
}

///|
/// Cross-basic-block copy propagation using dominance analysis
/// Compatibility wrapper around `canonicalize_aliases`.
pub fn propagate_copies_global(func : Function) -> OptResult {
  canonicalize_aliases(func)
}

///|
/// Resolve a value through copy chain
fn resolve_copy(v : Value, copies : @hashmap.HashMap[Int, Value]) -> Value? {
  // Follow copy chain (with cycle detection)
  let mut current = v
  let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()
  while true {
    if visited.get(current.id).unwrap_or(false) {
      break // Cycle detected
    }
    visited.set(current.id, true)
    match copies.get(current.id) {
      Some(source) => current = source
      None => break
    }
  }
  Some(current)
}

///|
/// Propagate copies in terminator
fn propagate_copies_in_terminator(
  term : Terminator,
  copies : @hashmap.HashMap[Int, Value],
  result : OptResult,
) -> Terminator {
  match term {
    Jump(target, args) => {
      let new_args : Array[Value] = []
      for arg in args {
        match resolve_copy(arg, copies) {
          Some(resolved) => {
            if resolved.id != arg.id {
              result.mark_changed()
            }
            new_args.push(resolved)
          }
          None => new_args.push(arg)
        }
      }
      Terminator::Jump(target, new_args)
    }
    Brz(cond, then_t, else_t) =>
      match resolve_copy(cond, copies) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          Terminator::Brz(resolved, then_t, else_t)
        }
        None => term
      }
    Brnz(cond, then_t, else_t) =>
      match resolve_copy(cond, copies) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          Terminator::Brnz(resolved, then_t, else_t)
        }
        None => term
      }
    BrTable(index, targets, default_t) =>
      match resolve_copy(index, copies) {
        Some(resolved) => {
          if resolved.id != index.id {
            result.mark_changed()
          }
          Terminator::BrTable(resolved, targets, default_t)
        }
        None => term
      }
    Return(values) => {
      let new_values : Array[Value] = []
      for v in values {
        match resolve_copy(v, copies) {
          Some(resolved) => {
            if resolved.id != v.id {
              result.mark_changed()
            }
            new_values.push(resolved)
          }
          None => new_values.push(v)
        }
      }
      Terminator::Return(new_values)
    }
    Trap(_) => term
  }
}
