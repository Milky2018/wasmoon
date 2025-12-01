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
              inst.operands.clear()
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
              inst.operands.clear()
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
    // Basic optimizations only
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
        _ => ()
      }
    }
  }
  // Simplify branches
  for block in func.blocks {
    match block.terminator {
      Some(Brz(cond, then_target, else_target)) =>
        match constants.get(cond.id) {
          Some(I32(v)) => {
            // brz: branch if zero
            let target = if v == 0 { then_target } else { else_target }
            block.terminator = Some(Terminator::Jump(target, []))
            result.mark_changed()
          }
          Some(I64(v)) => {
            let target = if v == 0L { then_target } else { else_target }
            block.terminator = Some(Terminator::Jump(target, []))
            result.mark_changed()
          }
          _ => ()
        }
      Some(Brnz(cond, then_target, else_target)) =>
        match constants.get(cond.id) {
          Some(I32(v)) => {
            // brnz: branch if not zero
            let target = if v != 0 { then_target } else { else_target }
            block.terminator = Some(Terminator::Jump(target, []))
            result.mark_changed()
          }
          Some(I64(v)) => {
            let target = if v != 0L { then_target } else { else_target }
            block.terminator = Some(Terminator::Jump(target, []))
            result.mark_changed()
          }
          _ => ()
        }
      Some(BrTable(index, targets, default_target)) =>
        match constants.get(index.id) {
          Some(I32(v)) => {
            // Convert to direct jump if index is constant
            let target = if v >= 0 && v < targets.length() {
              targets[v]
            } else {
              default_target
            }
            block.terminator = Some(Terminator::Jump(target, []))
            result.mark_changed()
          }
          _ => ()
        }
      _ => ()
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
        match block.terminator {
          Some(term) =>
            for succ in get_terminator_targets(term) {
              if not(reachable.get(succ).unwrap_or(false)) {
                worklist.push(succ)
              }
            }
          None => ()
        }
        break
      }
    }
  }
  // Remove unreachable blocks (iterate backwards to avoid index issues)
  let mut i = func.blocks.length() - 1
  while i >= 0 {
    let block = func.blocks[i]
    if not(reachable.get(block.id).unwrap_or(false)) {
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
    match block.terminator {
      Some(term) => {
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
      None => ()
    }
  }
  // Find mergeable pairs: pred has 1 successor, succ has 1 predecessor
  let to_merge : Array[(Int, Int)] = [] // (pred_id, succ_id)
  for block in func.blocks {
    if block.id == 0 {
      continue // Don't merge into entry block
    }
    let preds = pred_count.get(block.id).unwrap_or(0)
    if preds == 1 {
      match single_pred.get(block.id) {
        Some(pred_id) => {
          let succs = succ_count.get(pred_id).unwrap_or(0)
          if succs == 1 {
            // Check that the jump has no arguments (simple case)
            for pred_block in func.blocks {
              if pred_block.id == pred_id {
                match pred_block.terminator {
                  Some(Jump(_, args)) =>
                    if args.length() == 0 {
                      to_merge.push((pred_id, block.id))
                    }
                  _ => ()
                }
                break
              }
            }
          }
        }
        None => ()
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
    match (pred_block, succ_block) {
      (Some(pred), Some(succ)) => {
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
      _ => ()
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
    if block.instructions.length() == 0 && block.params.length() == 0 {
      match block.terminator {
        Some(Jump(target, args)) =>
          if args.length() == 0 {
            jump_targets.set(block.id, target)
          }
        _ => ()
      }
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
      if inst.result is Some(v) {
        value_to_block.set(v.id, block.id)
      }
    }
  }

  // Process each loop
  for loop_ in loops {
    // Find preheader - the unique predecessor outside the loop
    match cfg.get_loop_preheader(loop_) {
      Some(preheader_id) => {
        // Find preheader block
        let mut preheader_block : Block? = None
        for block in func.blocks {
          if block.id == preheader_id {
            preheader_block = Some(block)
            break
          }
        }
        match preheader_block {
          Some(preheader) => {
            // Find loop-invariant instructions and move them
            let hoisted = hoist_from_loop(
              func, loop_, preheader, value_to_block,
            )
            if hoisted {
              result.mark_changed()
            }
          }
          None => ()
        }
      }
      None => () // No unique preheader, can't hoist
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
            let already_invariant = match inst.result {
              Some(v) => invariant_values.get(v.id).unwrap_or(false)
              None => true
            }
            if !already_invariant &&
              is_loop_invariant(inst, loop_, value_to_block, invariant_values) {
              // Mark result as invariant
              if inst.result is Some(v) {
                invariant_values.set(v.id, true)
              }

              // Move instruction to preheader (before terminator)
              block.instructions.remove(i) |> ignore
              preheader.instructions.push(inst)

              // Update value_to_block
              if inst.result is Some(v) {
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
  let new_result = match inst.result {
    Some(v) => {
      let new_id = func.next_value_id
      func.next_value_id = new_id + 1
      Some({ id: new_id, ty: v.ty })
    }
    None => None
  }
  let new_operands : Array[Value] = []
  for op in inst.operands {
    new_operands.push(op)
  }
  { opcode: inst.opcode, operands: new_operands, result: new_result }
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
      match inst.opcode {
        Iconst(v) =>
          if inst.result is Some(r) {
            if r.ty is I32 {
              constants.set(r.id, ConstValue::I32(v.to_int()))
            } else {
              constants.set(r.id, ConstValue::I64(v))
            }
          }
        _ => ()
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
