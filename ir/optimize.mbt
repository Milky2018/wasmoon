// IR Optimization Passes
// Implements target-independent optimizations on the high-level IR

///|
/// Result of an optimization pass
pub(all) struct OptResult {
  mut changed : Bool // Whether the IR was modified
}

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
        match inst.result {
          Some(v) =>
            // If the result is never used and the instruction has no side effects
            if use_counts.get(v.id).unwrap_or(0) == 0 &&
              not(has_side_effects(inst)) {
              // Remove this instruction
              let _ = block.instructions.remove(i)
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
          None => () // Void instructions can't be dead by this criterion
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
    match block.terminator {
      Some(term) =>
        for v in get_terminator_uses(term) {
          let count = counts.get(v.id).unwrap_or(0)
          counts.set(v.id, count + 1)
        }
      None => ()
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
    // Store has side effects (modifies memory)
    Store(_, _) => true
    // Calls may have side effects
    Call(_) | CallIndirect(_) => true
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
          match inst.result {
            Some(r) =>
              if r.ty is I32 {
                constants.set(r.id, ConstValue::I32(v.to_int()))
              } else {
                constants.set(r.id, ConstValue::I64(v))
              }
            None => ()
          }
        Fconst(v) =>
          match inst.result {
            Some(r) =>
              if r.ty is F32 {
                constants.set(r.id, ConstValue::F32(v.to_float()))
              } else {
                constants.set(r.id, ConstValue::F64(v))
              }
            None => ()
          }
        _ => ()
      }
      // Then try to fold the instruction
      match try_fold_constant(inst, constants) {
        Some(const_val) =>
          match inst.result {
            Some(v) => {
              constants.set(v.id, const_val)
              // Replace instruction with constant
              inst.opcode = const_val.to_opcode()
              // Clear operands since this is now a constant
              while inst.operands.length() > 0 {
                let _ = inst.operands.pop()

              }
              result.mark_changed()
            }
            None => ()
          }
        None => ()
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
    F32(v) => Opcode::Fconst(v.to_double())
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
    // Avoid division by zero
    Sdiv =>
      fold_binary_int_checked(inst, constants, fn(a, b) {
        if b != 0L {
          Some(a / b)
        } else {
          None
        }
      })
    Udiv =>
      fold_binary_int_checked(inst, constants, fn(a, b) {
        if b != 0L {
          Some(
            a
            .reinterpret_as_uint64()
            .div(b.reinterpret_as_uint64())
            .reinterpret_as_int64(),
          )
        } else {
          None
        }
      })
    // Bitwise operations
    Band => fold_binary_int(inst, constants, fn(a, b) { a & b })
    Bor => fold_binary_int(inst, constants, fn(a, b) { a | b })
    Bxor => fold_binary_int(inst, constants, fn(a, b) { a ^ b })
    Ishl =>
      fold_binary_int(inst, constants, fn(a, b) { a << (b.to_int() % 64) })
    Sshr =>
      fold_binary_int(inst, constants, fn(a, b) {
        (a.reinterpret_as_uint64() >> (b.to_int() % 64)).reinterpret_as_int64()
      })
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
/// Fold binary integer operation with checked result
fn fold_binary_int_checked(
  inst : Inst,
  constants : @hashmap.HashMap[Int, ConstValue],
  op : (Int64, Int64) -> Int64?,
) -> ConstValue? {
  if inst.operands.length() != 2 {
    return None
  }
  let a = get_const(inst.operands[0], constants)
  let b = get_const(inst.operands[1], constants)
  match (a, b) {
    (Some(I32(va)), Some(I32(vb))) =>
      match op(va.to_int64(), vb.to_int64()) {
        Some(r) => Some(ConstValue::I32(r.to_int()))
        None => None
      }
    (Some(I64(va)), Some(I64(vb))) =>
      match op(va, vb) {
        Some(r) => Some(ConstValue::I64(r))
        None => None
      }
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
      Some(ConstValue::F32(op(va.to_double(), vb.to_double()).to_float()))
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
pub fn propagate_copies(func : Function) -> OptResult {
  let result = OptResult::new()
  // Map from copy destination to copy source
  let copies : @hashmap.HashMap[Int, Value] = @hashmap.new()
  // First pass: collect all copy instructions
  for block in func.blocks {
    for inst in block.instructions {
      match inst.opcode {
        Copy =>
          match inst.result {
            Some(dest) =>
              if inst.operands.length() > 0 {
                copies.set(dest.id, inst.operands[0])
              }
            None => ()
          }
        _ => ()
      }
    }
  }
  // Second pass: replace uses of copied values
  for block in func.blocks {
    for inst in block.instructions {
      for i, op in inst.operands {
        match resolve_copy(op, copies) {
          Some(resolved) =>
            if resolved.id != op.id {
              inst.operands[i] = resolved
              result.mark_changed()
            }
          None => ()
        }
      }
    }
    // Also update terminator operands
    match block.terminator {
      Some(term) => {
        let new_term = propagate_copies_in_terminator(term, copies, result)
        block.terminator = Some(new_term)
      }
      None => ()
    }
  }
  result
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
pub fn eliminate_common_subexpressions(func : Function) -> OptResult {
  let result = OptResult::new()
  // Map from expression signature to value
  let expressions : @hashmap.HashMap[String, Value] = @hashmap.new()
  for block in func.blocks {
    let mut i = 0
    while i < block.instructions.length() {
      let inst = block.instructions[i]
      // Skip instructions with side effects or no result
      if has_side_effects(inst) {
        i = i + 1
        continue
      }
      match inst.result {
        Some(result_val) => {
          let sig = compute_expression_signature(inst)
          match expressions.get(sig) {
            Some(existing) => {
              // Replace this instruction with a copy
              inst.opcode = Opcode::Copy
              // Clear operands and add the existing value
              while inst.operands.length() > 0 {
                let _ = inst.operands.pop()

              }
              inst.operands.push(existing)
              result.mark_changed()
            }
            None =>
              // Record this expression
              expressions.set(sig, result_val)
          }
        }
        None => ()
      }
      i = i + 1
    }
  }
  result
}

///|
/// Compute a signature for an expression (opcode + operands)
fn compute_expression_signature(inst : Inst) -> String {
  let mut sig = inst.opcode.to_string()
  for op in inst.operands {
    sig = sig + "_v" + op.id.to_string()
  }
  sig
}

// ============ Run All Optimizations ============

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
    // Run each optimization pass
    let cf_result = fold_constants(func)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = propagate_copies(func)
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = eliminate_common_subexpressions(func)
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = eliminate_dead_code(func)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
  }
  result
}
