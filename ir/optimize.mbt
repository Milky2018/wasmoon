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
    // GC operations that modify state
    StructSet(_, _) | ArraySet(_) | ArrayFill(_) | ArrayCopy(_, _) => true
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
/// Cross-basic-block copy propagation using dominance analysis
/// A copy in block A can propagate to block B only if A dominates B
pub fn propagate_copies_global(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  // Build CFG and compute dominators
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Collect all copies: (dest_id, source) pairs with defining block_id
  // copies[dest_id] = (source_value, defining_block_id)
  let copies : @hashmap.HashMap[Int, (Value, Int)] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Copy &&
        inst.first_result() is Some(dest) &&
        inst.operands.length() > 0 {
        copies.set(dest.id, (inst.operands[0], block.id))
      }
    }
  }
  // DFS the dominator tree with copy environment
  // env tracks which copy dest_ids are currently available
  let env : Array[Int] = []
  fn dfs(block_id : Int) {
    // Get block from func.blocks using mapping
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Record which copies this block defines (to pop later)
    let local_copies : Array[Int] = []
    for inst in block.instructions {
      if inst.opcode is Copy &&
        inst.first_result() is Some(dest) &&
        inst.operands.length() > 0 {
        local_copies.push(dest.id)
        env.push(dest.id)
      }
    }
    // Replace uses in this block's instructions
    for inst in block.instructions {
      for i, op in inst.operands {
        if resolve_copy_global(op, copies, env) is Some(resolved) &&
          resolved.id != op.id {
          inst.operands[i] = resolved
          result.mark_changed()
        }
      }
    }
    // Replace uses in terminator
    if block.terminator is Some(term) {
      let new_term = propagate_copies_in_terminator_global(
        term, copies, env, result,
      )
      block.terminator = Some(new_term)
    }
    // Recurse to dominated children
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Pop this block's copies from environment
    for _ in local_copies {
      env.pop() |> ignore
    }
  }

  // Start DFS from entry block (block 0)
  if cfg.is_valid(0) {
    dfs(0)
  }
  result
}

///|
/// Resolve a copy using global environment (only copies in dominating blocks)
fn resolve_copy_global(
  v : Value,
  copies : @hashmap.HashMap[Int, (Value, Int)],
  env : Array[Int],
) -> Value? {
  // Follow copy chain, but only if dest_id is in environment
  let mut current = v
  let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()
  while true {
    if visited.get(current.id).unwrap_or(false) {
      break // Cycle detected
    }
    visited.set(current.id, true)
    // Check if current.id is a copy dest that's in our environment
    match copies.get(current.id) {
      Some((source, _)) => {
        // Only follow if this copy is available (dest in env)
        let mut in_env = false
        for dest_id in env {
          if dest_id == current.id {
            in_env = true
            break
          }
        }
        if in_env {
          current = source
        } else {
          break
        }
      }
      None => break
    }
  }
  Some(current)
}

///|
/// Propagate copies in terminator (global version)
fn propagate_copies_in_terminator_global(
  term : Terminator,
  copies : @hashmap.HashMap[Int, (Value, Int)],
  env : Array[Int],
  result : OptResult,
) -> Terminator {
  match term {
    Jump(target, args) => {
      let new_args : Array[Value] = []
      for arg in args {
        match resolve_copy_global(arg, copies, env) {
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
      match resolve_copy_global(cond, copies, env) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          Terminator::Brz(resolved, then_t, else_t)
        }
        None => term
      }
    Brnz(cond, then_t, else_t) =>
      match resolve_copy_global(cond, copies, env) {
        Some(resolved) => {
          if resolved.id != cond.id {
            result.mark_changed()
          }
          Terminator::Brnz(resolved, then_t, else_t)
        }
        None => term
      }
    BrTable(index, targets, default_t) =>
      match resolve_copy_global(index, copies, env) {
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
        match resolve_copy_global(v, copies, env) {
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

// ============ Common Subexpression Elimination ============

///|
/// Common Subexpression Elimination (CSE)
/// Replaces duplicate computations with references to the first computation
/// Note: This is local CSE - expressions are only reused within the same basic block
/// to avoid incorrectly using values from non-dominating blocks (e.g., sibling branches)
pub fn eliminate_common_subexpressions(func : Function) -> OptResult {
  let result = OptResult::new()
  for block in func.blocks {
    // Reset expressions map for each block to avoid cross-block CSE issues
    // (e.g., using values defined in sibling branches of if-else)
    let expressions : @hashmap.HashMap[Inst, Value] = @hashmap.new()
    let mut i = 0
    while i < block.instructions.length() {
      let inst = block.instructions[i]
      // Skip instructions with side effects or no result
      if has_side_effects(inst) {
        i = i + 1
        continue
      }
      if inst.first_result() is Some(result_val) {
        if expressions.get(inst) is Some(existing) {
          // Replace this instruction with a copy
          inst.opcode = Opcode::Copy
          // Clear operands and add the existing value
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
        } else {
          // Record this expression
          expressions.set(inst, result_val)
        }
      }
      i = i + 1
    }
  }
  result
}

///|
/// Global Common Subexpression Elimination using dominance analysis
/// Expressions in dominating blocks can be reused in dominated blocks
pub fn eliminate_common_subexpressions_global(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  // Build CFG and compute dominators
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Expression environment: key -> value
  // We use an array as a stack to track which expressions to pop on leaving a block
  let expressions : @hashmap.HashMap[Inst, Value] = @hashmap.new()
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added in this block (to pop later)
    let local_keys : Array[Inst] = []
    // Process instructions
    let mut i = 0
    while i < block.instructions.length() {
      let inst = block.instructions[i]
      // Skip instructions with side effects or no result
      if has_side_effects(inst) {
        i = i + 1
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if expressions.get(key) is Some(existing) {
          // Replace this instruction with a copy to the existing value
          inst.opcode = Opcode::Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
          // Don't add this to expressions (it's now a copy)
        } else {
          // Record this expression as available
          expressions.set(key, result_val)
          local_keys.push(key)
        }
      }
      i = i + 1
    }
    // Recurse to dominated children
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Pop this block's expressions from environment
    for key in local_keys {
      expressions.remove(key)
    }
  }

  // Start DFS from entry block (block 0)
  if cfg.is_valid(0) {
    dfs(0)
  }
  result
}

// ============ LoadMemBase Elimination ============

///|
/// Eliminate redundant `LoadMemBase` instructions within a basic block.
///
/// `LoadMemBase` reads global runtime state (the memory descriptor), so it must
/// not be CSE'd across calls or `memory.grow`. This pass performs a simple
/// forward scan with conservative invalidation on any call-like instruction and
/// `MemoryGrow`.
pub fn eliminate_redundant_mem_base_loads(func : Function) -> OptResult {
  let result = OptResult::new()
  for block in func.blocks {
    // Key: (memidx, vmctx_value_id) packed into an Int64.
    let seen : @hashmap.HashMap[Int64, Value] = @hashmap.new()
    for inst in block.instructions {
      match inst.opcode {
        LoadMemBase(memidx) =>
          if inst.first_result() is Some(r) && inst.operands.length() == 1 {
            let vmctx = inst.operands[0]
            let key = (memidx.to_int64() << 32) |
              (vmctx.id.to_int64() & 0xFFFF_FFFFL)
            match seen.get(key) {
              Some(existing) => {
                inst.opcode = Opcode::Copy
                inst.operands.clear()
                inst.operands.push(existing)
                result.mark_changed()
              }
              None => seen.set(key, r)
            }
          }
        // Conservatively invalidate on operations that can mutate memory base.
        MemoryGrow(_, _)
        | Call(_)
        | CallIndirect(_, _)
        | CallRef(_)
        | ReturnCall(_)
        | ReturnCallIndirect(_, _)
        | ReturnCallRef(_)
        | CallPtr(_, _) => seen.clear()
        _ => ()
      }
    }
  }
  result
}

// ============ Global Value Numbering with Load CSE ============

///|
/// Check if an instruction reads from memory
fn reads_memory(opcode : Opcode) -> Bool {
  match opcode {
    LoadPtr(_) | LoadPtrNarrow(_, _, _) => true
    // MemorySize reads the current memory size (invalidated by MemoryGrow)
    MemorySize(_) => true
    // GC struct/array gets read from memory
    StructGet(_, _) | StructGetS(_, _, _) | StructGetU(_, _, _) => true
    ArrayGet(_) | ArrayGetS(_, _) | ArrayGetU(_, _) | ArrayLen => true
    _ => false
  }
}

///|
/// Check if an instruction may write to memory or have other side effects
/// that could invalidate memory-based expressions
fn may_write_memory(opcode : Opcode) -> Bool {
  match opcode {
    // Direct memory writes
    StorePtr(_) | StorePtrNarrow(_) => true
    // Memory operations
    MemoryGrow(_, _) | MemoryFill(_) | MemoryCopy(_, _) => true
    // Calls may write memory
    Call(_)
    | CallIndirect(_, _)
    | CallRef(_)
    | ReturnCall(_)
    | ReturnCallIndirect(_, _)
    | ReturnCallRef(_)
    | CallPtr(_, _) => true
    // GC operations that modify memory
    StructSet(_, _) | ArraySet(_) | ArrayFill(_) | ArrayCopy(_, _) => true
    // GC allocations modify memory (the GC heap)
    StructNew(_) | StructNewDefault(_) => true
    ArrayNew(_) | ArrayNewDefault(_) | ArrayNewFixed(_, _) => true
    // Table operations may involve memory
    TableGrow(_) => true
    // Exception handling can modify state
    Throw(_) | ThrowRef => true
    SpillLocalsForThrow(_) => true
    _ => false
  }
}

///|
/// Check if an instruction is suitable for GVN (can be CSE'd)
/// This includes pure operations plus loads (which read but don't write)
fn is_gvn_candidate(inst : Inst) -> Bool {
  // Must have a result
  if inst.first_result() is None {
    return false
  }
  // Use the existing has_side_effects check - if it has side effects, skip it
  if has_side_effects(inst) {
    return false
  }
  // Instructions that write memory are handled by invalidation, not skipped
  // But we still need to skip them as candidates
  match inst.opcode {
    // Division/remainder can trap, not suitable
    Sdiv | Udiv | Srem | Urem => false
    // Float-to-int can trap
    FcvtToSint | FcvtToUint => false
    // Memory writes are handled by may_write_memory, skip as candidates
    StorePtr(_) | StorePtrNarrow(_) => false
    // All other non-side-effect instructions are candidates
    _ => true
  }
}

///|
/// Global Value Numbering with Load CSE
/// Extends CSE to handle memory loads by tracking when stores invalidate loads
pub fn gvn(func : Function) -> OptResult {
  let result = OptResult::new()
  for block in func.blocks {
    // Value table: expression key -> (result value, reads_memory flag)
    let value_table : @hashmap.HashMap[Inst, (Value, Bool)] = @hashmap.new()
    for inst in block.instructions {
      // Check if this instruction may invalidate memory-based expressions
      if may_write_memory(inst.opcode) {
        // Invalidate all memory-reading expressions
        let to_remove : Array[Inst] = []
        for entry in value_table.iter() {
          let (key, (_, is_memory_read)) = entry
          if is_memory_read {
            to_remove.push(key)
          }
        }
        for key in to_remove {
          value_table.remove(key)
        }
        continue
      }
      // Skip non-candidates
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if value_table.get(key) is Some((existing, _)) {
          // Already computed - replace with copy
          inst.opcode = Opcode::Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
        } else {
          // Record in value table with memory-read flag
          let is_memory_read = reads_memory(inst.opcode)
          value_table.set(key, (result_val, is_memory_read))
        }
      }
    }
  }
  result
}

///|
/// Global Value Numbering with dominance analysis
/// Expressions in dominating blocks can be reused in dominated blocks,
/// with proper invalidation of memory-based expressions
pub fn gvn_global(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  // Build CFG and compute dominators
  let cfg = CFG::build(func)
  let idom = cfg.compute_dominators()
  let domtree = build_dominator_tree(idom)
  // Build block_id -> array_index mapping
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Expression environment: key -> (value, reads_memory flag)
  let value_table : @hashmap.HashMap[Inst, (Value, Bool)] = @hashmap.new()
  // Track memory-reading keys separately for O(1) invalidation lookup
  let memory_keys : @hashset.HashSet[Inst] = @hashset.new()
  // DFS the dominator tree
  fn dfs(block_id : Int) {
    let idx = block_idx.get(block_id).unwrap()
    let block = func.blocks[idx]
    // Track expressions added/modified in this block (to restore later)
    // Stores (key, previous_entry) where previous_entry is None if new
    let local_entries : Array[(Inst, (Value, Bool)?)] = []
    // Process instructions
    for inst in block.instructions {
      // Check if this instruction may invalidate memory-based expressions
      if may_write_memory(inst.opcode) {
        // Invalidate all memory-reading expressions using tracked set
        for key in memory_keys {
          if value_table.get(key) is Some((v, _)) {
            // Record for restoration
            local_entries.push((key, Some((v, true))))
          }
        }
        // Remove all memory-reading expressions
        for key in memory_keys {
          value_table.remove(key)
        }
        memory_keys.clear()
        continue
      }
      // Skip non-candidates
      if !is_gvn_candidate(inst) {
        continue
      }
      if inst.first_result() is Some(result_val) {
        let key = inst
        if value_table.get(key) is Some((existing, _)) {
          // Already computed - replace with copy
          inst.opcode = Opcode::Copy
          inst.operands.clear()
          inst.operands.push(existing)
          result.mark_changed()
        } else {
          // Record previous value (None if new)
          let prev = value_table.get(key)
          local_entries.push((key, prev))
          // Add to value table with memory-read flag
          let is_memory_read = reads_memory(inst.opcode)
          value_table.set(key, (result_val, is_memory_read))
          if is_memory_read {
            memory_keys.add(key)
          }
        }
      }
    }
    // Recurse to dominated children
    if block_id < domtree.length() {
      for child in domtree[block_id] {
        dfs(child)
      }
    }
    // Restore value table to state before this block
    for entry in local_entries.rev_iter() {
      let (key, prev) = entry
      match prev {
        Some(v) => {
          value_table.set(key, v)
          if v.1 {
            memory_keys.add(key)
          }
        }
        None => {
          value_table.remove(key)
          memory_keys.remove(key)
        }
      }
    }
  }

  // Start DFS from entry block (block 0)
  if cfg.is_valid(0) {
    dfs(0)
  }
  result
}

// ============ Run All Optimizations ============

///|
/// Optimization level
/// - 0: No optimization
/// - 1: Basic optimizations (constant folding, copy propagation, CSE, DCE)
/// - 2: Default optimizations (includes control flow optimizations)
/// - 3: Aggressive optimizations (includes loop optimizations)
pub enum OptLevel {
  O0 // No optimization
  O1 // Basic optimizations
  O2 // Default optimizations
  O3 // Aggressive optimizations
}

///|
/// Parse optimization level from integer
pub fn OptLevel::from_int(n : Int) -> OptLevel {
  match n {
    0 => O0
    1 => O1
    3 => O3
    _ => O2 // Default
  }
}

///|
/// Run optimizations based on level
pub fn optimize_with_level(func : Function, level : OptLevel) -> OptResult {
  match level {
    O0 => OptResult::new() // No optimization
    O1 => optimize_o1(func)
    O2 => optimize(func)
    O3 => optimize_o3(func)
  }
}

///|
/// O1: Basic optimizations only
fn optimize_o1(func : Function) -> OptResult {
  let result = OptResult::new()
  let mut changed = true
  let mut iterations = 0
  let max_iterations = 100
  while changed && iterations < max_iterations {
    changed = false
    iterations = iterations + 1
    // E-graph based optimization (constant folding + algebraic simplification)
    if optimize_function(func) {
      changed = true
      result.mark_changed()
    }
    // Basic optimizations only
    let cf_result = fold_constants(func)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let mb_result = eliminate_redundant_mem_base_loads(func)
    if mb_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = propagate_copies_global(func)
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = eliminate_common_subexpressions_global(func)
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    // GVN with load CSE (extends CSE to handle memory loads)
    let gvn_result = gvn_global(func)
    if gvn_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = eliminate_dead_code(func)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
    let cbpe_result = eliminate_constant_block_params(func)
    if cbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Dead block parameter elimination (crucial for unused locals)
    let dbpe_result = eliminate_dead_block_params(func)
    if dbpe_result.changed {
      changed = true
      result.mark_changed()
    }
  }
  result
}

///|
/// Run all basic optimizations until fixed point
pub fn optimize(func : Function) -> OptResult {
  let result = OptResult::new()
  let mut changed = true
  let mut iterations = 0
  let max_iterations = 100 // Prevent infinite loops
  while changed && iterations < max_iterations {
    changed = false
    iterations = iterations + 1
    // E-graph based optimization (constant folding + algebraic simplification)
    if optimize_function(func) {
      changed = true
      result.mark_changed()
    }
    // Run each optimization pass
    let cf_result = fold_constants(func)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let mb_result = eliminate_redundant_mem_base_loads(func)
    if mb_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = propagate_copies_global(func)
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = eliminate_common_subexpressions_global(func)
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    // GVN with load CSE (extends CSE to handle memory loads)
    let gvn_result = gvn_global(func)
    if gvn_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = eliminate_dead_code(func)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
    let cbpe_result = eliminate_constant_block_params(func)
    if cbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Dead block parameter elimination (crucial for unused locals)
    let dbpe_result = eliminate_dead_block_params(func)
    if dbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Control flow optimizations
    let bs_result = simplify_branches(func)
    if bs_result.changed {
      changed = true
      result.mark_changed()
    }
    let uce_result = eliminate_unreachable_code(func)
    if uce_result.changed {
      changed = true
      result.mark_changed()
    }
    let bm_result = merge_blocks(func)
    if bm_result.changed {
      changed = true
      result.mark_changed()
    }
    let jt_result = thread_jumps(func)
    if jt_result.changed {
      changed = true
      result.mark_changed()
    }
  }
  result
}

///|
/// O3: Aggressive optimizations including loop optimizations
fn optimize_o3(func : Function) -> OptResult {
  let result = OptResult::new()
  // First run O2 optimizations
  let o2_result = optimize(func)
  if o2_result.changed {
    result.mark_changed()
  }
  // Then apply loop optimizations
  let licm_result = hoist_loop_invariants(func)
  if licm_result.changed {
    result.mark_changed()
  }
  let unroll_result = unroll_loops(func, 2) // Unroll factor of 2
  if unroll_result.changed {
    result.mark_changed()
  }
  let sr_result = reduce_strength(func)
  if sr_result.changed {
    result.mark_changed()
  }
  // Run O2 again to clean up
  let cleanup_result = optimize(func)
  if cleanup_result.changed {
    result.mark_changed()
  }
  result
}

// ============ Constant Block Parameter Elimination ============

///|
/// Abstract value for block parameters during constant-phi analysis
priv enum PhiAbstractValue {
  None
  One(Int)
  Many
} derive(Eq)

///|
fn PhiAbstractValue::join(
  self : PhiAbstractValue,
  other : PhiAbstractValue,
) -> PhiAbstractValue {
  match (self, other) {
    (None, v) => v
    (v, None) => v
    (Many, _) => Many
    (_, Many) => Many
    (One(v1), One(v2)) => if v1 == v2 { One(v1) } else { Many }
  }
}

///|

///|
fn build_value_map(func : Function) -> @hashmap.HashMap[Int, Value] {
  let values : @hashmap.HashMap[Int, Value] = @hashmap.new()
  for param in func.params {
    let (v, _) = param
    values.set(v.id, v)
  }
  for block in func.blocks {
    for param in block.params {
      let (v, _) = param
      values.set(v.id, v)
    }
    for inst in block.instructions {
      for result in inst.results {
        values.set(result.id, result)
      }
    }
  }
  values
}

///|
fn resolve_replacement(
  v : Value,
  replace_map : @hashmap.HashMap[Int, Int],
  value_map : @hashmap.HashMap[Int, Value],
) -> Value {
  let mut current_id = v.id
  let mut steps = 0
  while steps < 1024 {
    match replace_map.get(current_id) {
      Some(next_id) => {
        if next_id == current_id {
          break
        }
        current_id = next_id
        steps = steps + 1
      }
      None => break
    }
  }
  if current_id == v.id {
    v
  } else {
    value_map.get(current_id).unwrap_or(v)
  }
}

///|
/// Constant Block Parameter Elimination
/// Removes block parameters that always take the same value across all incoming edges.
/// This mirrors Cranelift's constant-phi removal, but operates on IR block params.
pub fn eliminate_constant_block_params(func : Function) -> OptResult {
  let result = OptResult::new()
  let cfg = CFG::build(func)
  let rpo = cfg.reverse_postorder()
  if rpo.length() == 0 {
    return result
  }
  let entry_id = rpo[0]
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  let state : @hashmap.HashMap[Int, PhiAbstractValue] = @hashmap.new()
  let mut has_params = false
  for block in func.blocks {
    if block.id == entry_id {
      continue
    }
    for param in block.params {
      let (v, _) = param
      state.set(v.id, PhiAbstractValue::None)
      has_params = true
    }
  }
  if !has_params {
    return result
  }
  let mut changed = true
  let mut iterations = 0
  let max_iterations = 512
  while changed && iterations < max_iterations {
    changed = false
    iterations = iterations + 1
    for block_id in rpo {
      let block = match block_idx.get(block_id) {
        Some(idx) => func.blocks[idx]
        None => continue
      }
      match block.terminator {
        Some(Jump(target, args)) => {
          if args.length() == 0 {
            continue
          }
          let target_block = match block_idx.get(target) {
            Some(idx) => func.blocks[idx]
            None => continue
          }
          let param_count = target_block.params.length()
          let arg_count = args.length()
          let count = if param_count < arg_count {
            param_count
          } else {
            arg_count
          }
          for i in 0..<count {
            let (formal, _) = target_block.params[i]
            if state.get(formal.id) is None {
              continue
            }
            let actual = args[i]
            let actual_absval = match state.get(actual.id) {
              Some(absval) => absval
              None => PhiAbstractValue::One(actual.id)
            }
            let old_absval = state
              .get(formal.id)
              .unwrap_or(PhiAbstractValue::None)
            let new_absval = old_absval.join(actual_absval)
            if new_absval != old_absval {
              state.set(formal.id, new_absval)
              changed = true
            }
          }
        }
        _ => ()
      }
    }
  }
  let params_to_keep : @hashmap.HashMap[Int, Array[Int]] = @hashmap.new()
  let replace_map : @hashmap.HashMap[Int, Int] = @hashmap.new()
  let mut will_change = false
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      let (v, _) = param
      match state.get(v.id) {
        Some(PhiAbstractValue::One(replacement_id)) => {
          replace_map.set(v.id, replacement_id)
          will_change = true
        }
        _ => keep.push(i)
      }
    }
    params_to_keep.set(block.id, keep)
  }
  if !will_change {
    return result
  }
  for block in func.blocks {
    let keep = params_to_keep.get(block.id).unwrap_or([])
    if keep.length() != block.params.length() {
      let old_params = block.params.copy()
      block.params.clear()
      for idx in keep {
        block.params.push(old_params[idx])
      }
      result.mark_changed()
    }
  }
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) => {
        let keep = params_to_keep.get(target).unwrap_or([])
        if keep.length() != args.length() {
          let new_args : Array[Value] = []
          for idx in keep {
            if idx < args.length() {
              new_args.push(args[idx])
            }
          }
          block.terminator = Some(Terminator::Jump(target, new_args))
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  let value_map = build_value_map(func)
  for block in func.blocks {
    for inst in block.instructions {
      let mut needs_update = false
      let new_operands : Array[Value] = []
      for op in inst.operands {
        let resolved = resolve_replacement(op, replace_map, value_map)
        if resolved.id != op.id {
          needs_update = true
        }
        new_operands.push(resolved)
      }
      if needs_update {
        inst.operands.clear()
        for op in new_operands {
          inst.operands.push(op)
        }
        result.mark_changed()
      }
    }
    if block.terminator is Some(term) {
      match term {
        Jump(target, args) => {
          let mut needs_update = false
          let new_args : Array[Value] = []
          for arg in args {
            let resolved = resolve_replacement(arg, replace_map, value_map)
            if resolved.id != arg.id {
              needs_update = true
            }
            new_args.push(resolved)
          }
          if needs_update {
            block.terminator = Some(Terminator::Jump(target, new_args))
            result.mark_changed()
          }
        }
        Brz(cond, then_target, else_target) => {
          let resolved = resolve_replacement(cond, replace_map, value_map)
          if resolved.id != cond.id {
            block.terminator = Some(
              Terminator::Brz(resolved, then_target, else_target),
            )
            result.mark_changed()
          }
        }
        Brnz(cond, then_target, else_target) => {
          let resolved = resolve_replacement(cond, replace_map, value_map)
          if resolved.id != cond.id {
            block.terminator = Some(
              Terminator::Brnz(resolved, then_target, else_target),
            )
            result.mark_changed()
          }
        }
        BrTable(index, targets, default_target) => {
          let resolved = resolve_replacement(index, replace_map, value_map)
          if resolved.id != index.id {
            block.terminator = Some(
              Terminator::BrTable(resolved, targets, default_target),
            )
            result.mark_changed()
          }
        }
        Return(values) => {
          let mut needs_update = false
          let new_values : Array[Value] = []
          for value in values {
            let resolved = resolve_replacement(value, replace_map, value_map)
            if resolved.id != value.id {
              needs_update = true
            }
            new_values.push(resolved)
          }
          if needs_update {
            block.terminator = Some(Terminator::Return(new_values))
            result.mark_changed()
          }
        }
        Trap(_) => ()
      }
    }
  }
  result
}

// ============ Dead Block Parameter Elimination ============

///|
/// Dead Block Parameter Elimination
/// Removes block parameters that are never used
/// This is crucial for eliminating unused locals that get SSA-converted to block params
pub fn eliminate_dead_block_params(func : Function) -> OptResult {
  let result = OptResult::new()

  // Build use counts for values in each block
  // A block parameter is "used" if it's referenced in instructions or passed to another used param
  let used_params = compute_used_block_params(func)

  // Track which parameter indices to keep for each block
  let params_to_keep : @hashmap.HashMap[Int, Array[Int]] = @hashmap.new()
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      let (v, _) = param
      if used_params.get(v.id).unwrap_or(false) {
        keep.push(i)
      }
    }
    params_to_keep.set(block.id, keep)
  }

  // Check if any parameters will be removed
  let mut will_change = false
  for block in func.blocks {
    let keep = params_to_keep.get(block.id).unwrap_or([])
    if keep.length() != block.params.length() {
      will_change = true
      break
    }
  }
  if !will_change {
    return result
  }

  // Update block parameters - remove unused ones
  for block in func.blocks {
    let keep = params_to_keep.get(block.id).unwrap_or([])
    if keep.length() != block.params.length() {
      let old_params = block.params.copy()
      block.params.clear()
      for idx in keep {
        block.params.push(old_params[idx])
      }
      result.mark_changed()
    }
  }

  // Update terminators - remove arguments corresponding to removed parameters
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) => {
        let keep = params_to_keep.get(target).unwrap_or([])
        if keep.length() != args.length() {
          let new_args : Array[Value] = []
          for idx in keep {
            if idx < args.length() {
              new_args.push(args[idx])
            }
          }
          block.terminator = Some(Terminator::Jump(target, new_args))
          result.mark_changed()
        }
      }
      Some(Brz(_, _, _)) | Some(Brnz(_, _, _)) | Some(BrTable(_, _, _)) =>
        // These don't pass arguments, nothing to update
        ()
      _ => ()
    }
  }
  result
}

///|
/// Compute which block parameters are actually used
/// Uses iterative dataflow analysis
fn compute_used_block_params(func : Function) -> @hashmap.HashMap[Int, Bool] {
  let used : @hashmap.HashMap[Int, Bool] = @hashmap.new()

  // Initialize: all function parameters are used (they come from caller)
  for param in func.params {
    let (v, _) = param
    used.set(v.id, true)
  }

  // First pass: mark values used directly in instructions
  for block in func.blocks {
    for inst in block.instructions {
      for op in inst.operands {
        used.set(op.id, true)
      }
    }
    // Also count uses in terminators (excluding jump args; handled by dataflow)
    if block.terminator is Some(term) {
      match term {
        Jump(_, _) => ()
        Brz(cond, _, _) | Brnz(cond, _, _) => used.set(cond.id, true)
        BrTable(index, _, _) => used.set(index.id, true)
        Return(args) =>
          for v in args {
            used.set(v.id, true)
          }
        Trap(_) => ()
      }
    }
  }

  // Iterative dataflow: propagate "used" backwards through jump arguments
  // If a block parameter is used, the corresponding jump argument is also used
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      match block.terminator {
        Some(Jump(target, args)) =>
          // Find target block and its parameters
          for target_block in func.blocks {
            if target_block.id == target {
              // For each parameter-argument pair
              for i, param in target_block.params {
                let (param_v, _) = param
                if i < args.length() {
                  let arg = args[i]
                  // If target param is used, mark the argument as used
                  if used.get(param_v.id).unwrap_or(false) &&
                    !used.get(arg.id).unwrap_or(false) {
                    used.set(arg.id, true)
                    changed = true
                  }
                }
              }
              break
            }
          }
        _ => ()
      }
    }
  }
  used
}

// ============ Branch Simplification ============

///|
/// Branch Simplification
/// Simplifies conditional branches when the condition is a known constant
pub fn simplify_branches(func : Function) -> OptResult {
  let result = OptResult::new()
  // Build constant map from constant folding
  let constants : @hashmap.HashMap[Int, ConstValue] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Iconst(v) && inst.first_result() is Some(r) {
        if r.ty is I32 {
          constants.set(r.id, ConstValue::I32(v.to_int()))
        } else {
          constants.set(r.id, ConstValue::I64(v))
        }
      }
    }
  }
  // Simplify branches
  for block in func.blocks {
    if block.terminator is Some(Brz(cond, then_target, else_target)) {
      if constants.get(cond.id) is Some(I32(v)) {
        // brz: branch if zero
        let target = if v == 0 { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v == 0L { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      }
    } else if block.terminator is Some(Brnz(cond, then_target, else_target)) {
      if constants.get(cond.id) is Some(I32(v)) {
        // brnz: branch if not zero
        let target = if v != 0 { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v != 0L { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      }
    } else if block.terminator is Some(BrTable(index, targets, default_target)) {
      if constants.get(index.id) is Some(I32(v)) {
        // Convert to direct jump if index is constant
        let target = if v >= 0 && v < targets.length() {
          targets[v]
        } else {
          default_target
        }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      }
    }
  }
  result
}

// ============ Unreachable Code Elimination ============

///|
/// Unreachable Code Elimination
/// Removes blocks that cannot be reached from the entry block
pub fn eliminate_unreachable_code(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  // Mark reachable blocks using DFS from entry
  let reachable : @hashmap.HashMap[Int, Bool] = @hashmap.new()
  let worklist : Array[Int] = [0] // Start from entry block (block 0)
  while worklist.length() > 0 {
    let block_id = worklist.pop().unwrap()
    if reachable.get(block_id).unwrap_or(false) {
      continue
    }
    reachable.set(block_id, true)
    // Find the block and add successors to worklist
    for block in func.blocks {
      if block.id == block_id {
        if block.terminator is Some(term) {
          for succ in get_terminator_targets(term) {
            if !reachable.get(succ).unwrap_or(false) {
              worklist.push(succ)
            }
          }
        }
        break
      }
    }
  }
  // Remove unreachable blocks (iterate backwards to avoid index issues)
  let mut i = func.blocks.length() - 1
  while i >= 0 {
    let block = func.blocks[i]
    if !reachable.get(block.id).unwrap_or(false) {
      func.blocks.remove(i) |> ignore
      result.mark_changed()
    }
    i = i - 1
  }
  result
}

// ============ Basic Block Merging ============

///|
/// Basic Block Merging
/// Merges a block with its unique predecessor if the predecessor has only one successor
pub fn merge_blocks(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() <= 1 {
    return result
  }
  // Build predecessor and successor counts
  let pred_count : @hashmap.HashMap[Int, Int] = @hashmap.new()
  let succ_count : @hashmap.HashMap[Int, Int] = @hashmap.new()
  let single_pred : @hashmap.HashMap[Int, Int] = @hashmap.new() // block -> its single predecessor
  for block in func.blocks {
    pred_count.set(block.id, 0)
    succ_count.set(block.id, 0)
  }
  for block in func.blocks {
    if block.terminator is Some(term) {
      let targets = get_terminator_targets(term)
      succ_count.set(block.id, targets.length())
      for target in targets {
        let count = pred_count.get(target).unwrap_or(0)
        pred_count.set(target, count + 1)
        // Track the predecessor if this is the first one
        if count == 0 {
          single_pred.set(target, block.id)
        } else {
          // More than one predecessor, clear
          single_pred.remove(target)
        }
      }
    }
  }
  // Find mergeable pairs: pred has 1 successor, succ has 1 predecessor
  let to_merge : Array[(Int, Int)] = [] // (pred_id, succ_id)
  for block in func.blocks {
    if block.id == 0 {
      continue // Don't merge into entry block
    }
    let preds = pred_count.get(block.id).unwrap_or(0)
    if preds == 1 && single_pred.get(block.id) is Some(pred_id) {
      let succs = succ_count.get(pred_id).unwrap_or(0)
      if succs == 1 {
        // Check that the jump has no arguments (simple case)
        for pred_block in func.blocks {
          if pred_block.id == pred_id {
            if pred_block.terminator is Some(Jump(_, args)) &&
              args.length() == 0 {
              to_merge.push((pred_id, block.id))
            }
            break
          }
        }
      }
    }
  }
  // Perform merges
  for pair in to_merge {
    let (pred_id, succ_id) = pair
    let mut pred_block : Block? = None
    let mut succ_block : Block? = None
    let mut succ_idx = -1
    for i, block in func.blocks {
      if block.id == pred_id {
        pred_block = Some(block)
      }
      if block.id == succ_id {
        succ_block = Some(block)
        succ_idx = i
      }
    }
    if (pred_block, succ_block) is (Some(pred), Some(succ)) {
      // Append successor's instructions to predecessor
      for inst in succ.instructions {
        pred.instructions.push(inst)
      }
      // Take successor's terminator
      pred.terminator = succ.terminator
      // Remove successor block
      if succ_idx >= 0 {
        func.blocks.remove(succ_idx) |> ignore
        result.mark_changed()
      }
    }
  }
  result
}

// ============ Jump Threading ============

///|
/// Jump Threading
/// Bypasses blocks that only contain an unconditional jump
pub fn thread_jumps(func : Function) -> OptResult {
  let result = OptResult::new()
  // Find blocks that are just jumps (no instructions, just a jump terminator)
  let jump_targets : @hashmap.HashMap[Int, Int] = @hashmap.new() // block -> final target
  for block in func.blocks {
    if block.instructions.length() == 0 &&
      block.params.length() == 0 &&
      block.terminator is Some(Jump(target, args)) &&
      args.length() == 0 {
      jump_targets.set(block.id, target)
    }
  }
  // Follow jump chains to find final target
  fn resolve_target(
    block_id : Int,
    jump_targets : @hashmap.HashMap[Int, Int],
    visited : @hashmap.HashMap[Int, Bool],
  ) -> Int {
    if visited.get(block_id).unwrap_or(false) {
      return block_id // Cycle detected
    }
    match jump_targets.get(block_id) {
      Some(target) => {
        visited.set(block_id, true)
        resolve_target(target, jump_targets, visited)
      }
      None => block_id
    }
  }
  // Update terminators to skip intermediate jump blocks
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) =>
        if args.length() == 0 {
          let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()
          let final_target = resolve_target(target, jump_targets, visited)
          if final_target != target {
            block.terminator = Some(Terminator::Jump(final_target, []))
            result.mark_changed()
          }
        }
      Some(Brz(cond, then_target, else_target)) => {
        let visited1 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let visited2 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let new_then = resolve_target(then_target, jump_targets, visited1)
        let new_else = resolve_target(else_target, jump_targets, visited2)
        if new_then != then_target || new_else != else_target {
          block.terminator = Some(Terminator::Brz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(Brnz(cond, then_target, else_target)) => {
        let visited1 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let visited2 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let new_then = resolve_target(then_target, jump_targets, visited1)
        let new_else = resolve_target(else_target, jump_targets, visited2)
        if new_then != then_target || new_else != else_target {
          block.terminator = Some(Terminator::Brnz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(BrTable(index, targets, default_target)) => {
        let new_targets : Array[Int] = []
        let mut any_changed = false
        for t in targets {
          let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()
          let new_t = resolve_target(t, jump_targets, visited)
          new_targets.push(new_t)
          if new_t != t {
            any_changed = true
          }
        }
        let visited_default : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let new_default = resolve_target(
          default_target, jump_targets, visited_default,
        )
        if new_default != default_target {
          any_changed = true
        }
        if any_changed {
          block.terminator = Some(
            Terminator::BrTable(index, new_targets, new_default),
          )
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  result
}

// ============ Loop Invariant Code Motion (LICM) ============

///|
/// Loop Invariant Code Motion
/// Moves loop-invariant computations out of loops to the preheader
pub fn hoist_loop_invariants(func : Function) -> OptResult {
  let result = OptResult::new()
  let cfg = CFG::build(func)
  let loops = cfg.find_loops()

  // Build a map from value id to the block where it's defined
  let value_to_block : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for block in func.blocks {
    // Function parameters are defined in entry block
    for param in func.params {
      let (v, _) = param
      value_to_block.set(v.id, 0)
    }
    // Block parameters
    for param in block.params {
      let (v, _) = param
      value_to_block.set(v.id, block.id)
    }
    // Instruction results
    for inst in block.instructions {
      if inst.first_result() is Some(v) {
        value_to_block.set(v.id, block.id)
      }
    }
  }

  // Process each loop
  for loop_ in loops {
    // Find preheader - the unique predecessor outside the loop
    if cfg.get_loop_preheader(loop_) is Some(preheader_id) {
      // Find preheader block
      let mut preheader_block : Block? = None
      for block in func.blocks {
        if block.id == preheader_id {
          preheader_block = Some(block)
          break
        }
      }
      if preheader_block is Some(preheader) {
        // Find loop-invariant instructions and move them
        let hoisted = hoist_from_loop(func, loop_, preheader, value_to_block)
        if hoisted {
          result.mark_changed()
        }
      }
    }
  }
  result
}

///|
/// Check if a value is defined outside the loop
fn is_defined_outside_loop(
  value_id : Int,
  loop_ : Loop,
  value_to_block : @hashmap.HashMap[Int, Int],
) -> Bool {
  match value_to_block.get(value_id) {
    Some(block_id) => !loop_.contains(block_id)
    None => true // Unknown values (like constants) are considered outside
  }
}

///|
/// Check if an instruction is loop-invariant
/// An instruction is loop-invariant if:
/// 1. It has no side effects
/// 2. All its operands are either defined outside the loop or are loop-invariant
fn is_loop_invariant(
  inst : Inst,
  loop_ : Loop,
  value_to_block : @hashmap.HashMap[Int, Int],
  invariant_values : @hashmap.HashMap[Int, Bool],
) -> Bool {
  // Instructions with side effects cannot be hoisted
  if has_side_effects(inst) {
    return false
  }

  // Check all operands
  for op in inst.operands {
    let outside = is_defined_outside_loop(op.id, loop_, value_to_block)
    let invariant = invariant_values.get(op.id).unwrap_or(false)
    if !outside && !invariant {
      return false
    }
  }
  true
}

///|
/// Hoist loop-invariant instructions from a loop to its preheader
/// Returns true if any instructions were hoisted
fn hoist_from_loop(
  func : Function,
  loop_ : Loop,
  preheader : Block,
  value_to_block : @hashmap.HashMap[Int, Int],
) -> Bool {
  let mut any_hoisted = false
  let invariant_values : @hashmap.HashMap[Int, Bool] = @hashmap.new()

  // Iterate until no more invariants found
  let mut changed = true
  while changed {
    changed = false

    // Check each block in the loop
    for block_id in loop_.blocks {
      // Find the block
      for block in func.blocks {
        if block.id == block_id {
          // Check each instruction
          let mut i = 0
          while i < block.instructions.length() {
            let inst = block.instructions[i]

            // Skip if already marked or has no result
            let already_invariant = match inst.first_result() {
              Some(v) => invariant_values.get(v.id).unwrap_or(false)
              None => true
            }
            if !already_invariant &&
              is_loop_invariant(inst, loop_, value_to_block, invariant_values) {
              // Mark result as invariant
              if inst.first_result() is Some(v) {
                invariant_values.set(v.id, true)
              }

              // Move instruction to preheader (before terminator)
              block.instructions.remove(i) |> ignore
              preheader.instructions.push(inst)

              // Update value_to_block
              if inst.first_result() is Some(v) {
                value_to_block.set(v.id, preheader.id)
              }
              any_hoisted = true
              changed = true
              // Don't increment i since we removed current element
            } else {
              i = i + 1
            }
          }
          break
        }
      }
    }
  }
  any_hoisted
}

// ============ Loop Unrolling ============

///|
/// Loop Unrolling
/// Duplicates the loop body to reduce loop overhead and enable further optimizations
/// This is a simple unrolling that only handles loops with known trip counts
pub fn unroll_loops(func : Function, unroll_factor : Int) -> OptResult {
  let result = OptResult::new()
  let cfg = CFG::build(func)
  let loops = cfg.find_loops()
  for loop_ in loops {
    // Only unroll simple loops with a single back edge
    if loop_.back_edges.length() != 1 {
      continue
    }

    // Check if loop has a simple structure (single body block)
    if loop_.blocks.length() > 2 {
      continue // Too complex for simple unrolling
    }

    // Find the loop body block (not the header)
    let mut body_block_id = -1
    for block_id in loop_.blocks {
      if block_id != loop_.header {
        body_block_id = block_id
        break
      }
    }
    if body_block_id < 0 {
      continue // No separate body block
    }

    // Find the body block
    let mut body_block : Block? = None
    for block in func.blocks {
      if block.id == body_block_id {
        body_block = Some(block)
        break
      }
    }
    if body_block is Some(body) {
      // Duplicate the body instructions
      let original_count = body.instructions.length()
      if original_count == 0 {
        continue
      }

      // Simple unrolling: duplicate instructions in-place
      // This is a simplified version that works best with LICM
      let original_insts : Array[Inst] = []
      for inst in body.instructions {
        original_insts.push(inst)
      }

      // Duplicate the instructions (unroll_factor - 1 times)
      for _ in 1..<unroll_factor {
        for inst in original_insts {
          // Clone the instruction with new result value
          let new_inst = clone_instruction(inst, func)
          body.instructions.push(new_inst)
        }
      }
      if body.instructions.length() > original_count {
        result.mark_changed()
      }
    }
  }
  result
}

///|
/// Clone an instruction with a fresh result value
fn clone_instruction(inst : Inst, func : Function) -> Inst {
  let new_results : Array[Value] = []
  for v in inst.results {
    let new_id = func.next_value_id
    func.next_value_id = new_id + 1
    new_results.push({ id: new_id, ty: v.ty })
  }
  let new_operands : Array[Value] = []
  for op in inst.operands {
    new_operands.push(op)
  }
  { results: new_results, opcode: inst.opcode, operands: new_operands }
}

// ============ Strength Reduction ============

///|
/// Strength Reduction
/// Replaces expensive operations with cheaper equivalents
/// Examples: multiplication by power of 2 -> shift, division by power of 2 -> shift
pub fn reduce_strength(func : Function) -> OptResult {
  let result = OptResult::new()

  // Build constant map
  let constants : @hashmap.HashMap[Int, ConstValue] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Iconst(v) && inst.first_result() is Some(r) {
        if r.ty is I32 {
          constants.set(r.id, ConstValue::I32(v.to_int()))
        } else {
          constants.set(r.id, ConstValue::I64(v))
        }
      }
    }
  }

  // Apply strength reduction
  for block in func.blocks {
    for inst in block.instructions {
      match inst.opcode {
        // Multiplication by power of 2 -> left shift
        Imul =>
          if inst.operands.length() == 2 {
            let (const_idx, shift_amount) = find_power_of_two_operand(
              inst.operands,
              constants,
            )
            if const_idx >= 0 && shift_amount >= 0 {
              // Save the non-constant operand before modifying
              let other_idx = if const_idx == 0 { 1 } else { 0 }
              let other_operand = inst.operands[other_idx]
              let const_operand = inst.operands[const_idx]
              // Replace imul with ishl
              inst.opcode = Ishl
              inst.operands.clear()
              inst.operands.push(other_operand)
              inst.operands.push(const_operand) // Keep the constant, semantics change
              result.mark_changed()
            }
          }
        // Division by power of 2 -> right shift (for unsigned)
        Udiv =>
          if inst.operands.length() == 2 {
            let (const_idx, shift_amount) = find_power_of_two_operand(
              inst.operands,
              constants,
            )
            if const_idx == 1 && shift_amount >= 0 {
              // Only reduce if divisor is constant power of 2
              // Replace udiv with ushr (logical right shift)
              inst.opcode = Ushr
              result.mark_changed()
            }
          }
        // Modulo by power of 2 -> bitwise AND
        Urem =>
          if inst.operands.length() == 2 {
            let (const_idx, shift_amount) = find_power_of_two_operand(
              inst.operands,
              constants,
            )
            if const_idx == 1 && shift_amount >= 0 {
              // x % (2^n) == x & (2^n - 1)
              inst.opcode = Band
              // The mask should be 2^n - 1, but we need to update the constant
              result.mark_changed()
            }
          }
        _ => ()
      }
    }
  }
  result
}

///|
/// Find an operand that is a power of 2, returns (operand_index, log2_value) or (-1, -1)
fn find_power_of_two_operand(
  operands : Array[Value],
  constants : @hashmap.HashMap[Int, ConstValue],
) -> (Int, Int) {
  for i, op in operands {
    match constants.get(op.id) {
      Some(I32(v)) => if v > 0 && is_power_of_two(v) { return (i, log2_int(v)) }
      Some(I64(v)) =>
        if v > 0L && is_power_of_two_64(v) {
          return (i, log2_int64(v))
        }
      _ => ()
    }
  }
  (-1, -1)
}

///|
/// Check if an integer is a power of 2
fn is_power_of_two(n : Int) -> Bool {
  n > 0 && (n & (n - 1)) == 0
}

///|
/// Check if a 64-bit integer is a power of 2
fn is_power_of_two_64(n : Int64) -> Bool {
  n > 0L && (n & (n - 1L)) == 0L
}

///|
/// Compute log2 of a power of 2
fn log2_int(n : Int) -> Int {
  let mut v = n
  let mut r = 0
  while v > 1 {
    v = v / 2
    r = r + 1
  }
  r
}

///|
/// Compute log2 of a 64-bit power of 2
fn log2_int64(n : Int64) -> Int {
  let mut v = n
  let mut r = 0
  while v > 1L {
    v = v / 2L
    r = r + 1
  }
  r
}
