// IR Optimization Passes
// Implements target-independent optimizations on the high-level IR

///|
/// Result of an optimization pass
pub struct OptResult {
  mut changed : Bool // Whether the IR was modified
} derive(Eq)

///|
fn OptResult::OptResult() -> OptResult {
  { changed: false, }
}

///|
/// Mark that the IR was changed
fn OptResult::mark_changed(self : OptResult) -> Unit {
  self.changed = true
}

// ============ Dead Code Elimination ============

///|
/// Dead Code Elimination (DCE)
/// Removes instructions whose results are never used
fn eliminate_dead_code(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  let use_counts = compute_use_counts(func)
  let dead_insts = Array::make(func.next_inst_id, false)
  let worklist : Array[Inst] = []
  for block in func.blocks {
    for inst in block.instructions {
      if inst.results.length() > 0 &&
        inst.results.all(v => use_counts[v.id] == 0) &&
        !inst.opcode.semantics().must_preserve_if_unused() {
        dead_insts[inst.id] = true
        worklist.push(inst)
        result.mark_changed()
      }
    }
  }
  while worklist.pop() is Some(inst) {
    for operand in inst.operands {
      let count = use_counts[operand.id]
      if count > 0 {
        let remaining = count - 1
        use_counts[operand.id] = remaining
        if remaining == 0 && func.defining_inst(operand) is Some(definition) {
          if !dead_insts[definition.id] &&
            definition.results.all(value => use_counts[value.id] == 0) &&
            !definition.opcode.semantics().must_preserve_if_unused() {
            dead_insts[definition.id] = true
            worklist.push(definition)
            result.mark_changed()
          }
        }
      }
    }
  }
  if result.changed {
    for block in func.blocks {
      block.retain_instructions(inst => !dead_insts[inst.id])
    }
  }
  result
}

///|
/// Compute use counts for all values in a function
fn compute_use_counts(func : Function) -> Array[Int] {
  let counts = Array::make(func.next_value_id, 0)
  fn count(value : Value) -> Unit {
    counts[value.id] = counts[value.id] + 1
  }
  for block in func.blocks {
    for inst in block.instructions {
      for op in inst.operands {
        count(op)
      }
    }
    if block.terminator is Some(term) {
      match term {
        Jump(_, args) | Return(args) =>
          for value in args {
            count(value)
          }
        Branch(cond, _, true_args, _, false_args) => {
          count(cond)
          for value in true_args {
            count(value)
          }
          for value in false_args {
            count(value)
          }
        }
        Brz(cond, _, _) | Brnz(cond, _, _) => count(cond)
        BrTable(index, _, _) => count(index)
        Trap(_) | TrapExit(_) => ()
      }
    }
  }
  counts
}

// ============ Constant Folding ============

///|
/// Constant Folding
/// Evaluates constant expressions at compile time
fn fold_constants(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  // Map from value id to constant value (if known)
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      // First, record any constant instruction
      match inst.opcode {
        Scalar(IntConst(v)) =>
          match inst.first_result() {
            Some(r) =>
              if r.ty is I32 {
                constants.set(r.id, I32(v.to_int()))
              } else {
                constants.set(r.id, I64(v))
              }
            None => ()
          }
        Scalar(FloatConst32(bits)) =>
          match inst.first_result() {
            Some(r) =>
              constants.set(r.id, F32(Float::reinterpret_from_uint(bits)))
            None => ()
          }
        Scalar(FloatConst64(bits)) =>
          match inst.first_result() {
            Some(r) => constants.set(r.id, F64(bits.reinterpret_as_double()))
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
    I32(v) => Scalar(IntConst(v.to_int64()))
    I64(v) => Scalar(IntConst(v))
    F32(v) => Scalar(FloatConst32(v.reinterpret_as_uint()))
    F64(v) => Scalar(FloatConst64(v.reinterpret_as_uint64()))
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
    Scalar(IntConst(_)) | Scalar(FloatConst32(_)) | Scalar(FloatConst64(_)) =>
      None
    // Binary integer operations
    Scalar(IntBinary(Add)) =>
      fold_binary_int(inst, constants, fn(a, b) { a + b })
    Scalar(IntBinary(Sub)) =>
      fold_binary_int(inst, constants, fn(a, b) { a - b })
    Scalar(IntBinary(Mul)) =>
      fold_binary_int(inst, constants, fn(a, b) { a * b })
    Scalar(IntBinary(SignedDiv)) => fold_sdiv(inst, constants)
    Scalar(IntBinary(UnsignedDiv)) => fold_udiv(inst, constants)
    // Bitwise operations
    Scalar(IntBinary(And)) =>
      fold_binary_int(inst, constants, fn(a, b) { a & b })
    Scalar(IntBinary(Or)) =>
      fold_binary_int(inst, constants, fn(a, b) { a | b })
    Scalar(IntBinary(Xor)) =>
      fold_binary_int(inst, constants, fn(a, b) { a ^ b })
    Scalar(IntBinary(ShiftLeft)) => fold_ishl(inst, constants)
    Scalar(IntBinary(SignedShiftRight)) => fold_sshr(inst, constants)
    Scalar(IntBinary(UnsignedShiftRight)) => fold_ushr(inst, constants)
    Scalar(IntBinary(SignedRem)) => fold_srem(inst, constants)
    Scalar(IntBinary(UnsignedRem)) => fold_urem(inst, constants)
    // Float operations
    Scalar(FloatBinary(Add)) =>
      fold_binary_float(inst, constants, fn(a, b) { a + b })
    Scalar(FloatBinary(Sub)) =>
      fold_binary_float(inst, constants, fn(a, b) { a - b })
    Scalar(FloatBinary(Mul)) =>
      fold_binary_float(inst, constants, fn(a, b) { a * b })
    Scalar(FloatBinary(Div)) =>
      fold_binary_float(inst, constants, fn(a, b) { a / b })
    // Comparisons
    Scalar(IntCompare(cc)) => fold_icmp(inst, constants, cc)
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
      Some(I32(op(va.to_int64(), vb.to_int64()).to_int()))
    (Some(I64(va)), Some(I64(vb))) => Some(I64(op(va, vb)))
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
      Some(F32(op(va.to_double(), vb.to_double()) |> Float::from_double))
    (Some(F64(va)), Some(F64(vb))) => Some(F64(op(va, vb)))
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
      Some(I32(if result { 1 } else { 0 }))
    }
    (Some(I64(va)), Some(I64(vb))) => {
      let result = eval_icmp_i64(cc, va, vb)
      Some(I32(if result { 1 } else { 0 }))
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
    (Some(I32(a)), Some(I32(b))) => Some(I32(a << (b % 32)))
    (Some(I64(a)), Some(I64(b))) => Some(I64(a << (b.to_int() % 64)))
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
    (Some(I32(a)), Some(I32(b))) => Some(I32(a >> (b % 32)))
    (Some(I64(a)), Some(I64(b))) => Some(I64(a >> (b.to_int() % 64)))
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
      Some(I32(result))
    }
    (Some(I64(a)), Some(I64(b))) => {
      let shift = b.to_int() % 64
      let result = (a.reinterpret_as_uint64() >> shift).reinterpret_as_int64()
      Some(I64(result))
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
        Some(I32(a / b))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else if a == -9223372036854775808L && b == -1L {
        None
      } else {
        Some(I64(a / b))
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
        Some(I32(result))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        let result = (a.reinterpret_as_uint64() / b.reinterpret_as_uint64())
          |> UInt64::reinterpret_as_int64
        Some(I64(result))
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
    (Some(I32(a)), Some(I32(b))) => if b == 0 { None } else { Some(I32(a % b)) }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        Some(I64(a % b))
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
        Some(I32(result))
      }
    (Some(I64(a)), Some(I64(b))) =>
      if b == 0L {
        None
      } else {
        let result = (a.reinterpret_as_uint64() % b.reinterpret_as_uint64())
          |> UInt64::reinterpret_as_int64
        Some(I64(result))
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
/// Alias/copy canonicalization pass.
/// Resolves visible copy chains along the dominator tree and rewrites operands
/// to canonical values (Cranelift analogue: `resolve_all_aliases()`).
fn canonicalize_aliases(func : Function) -> OptResult {
  canonicalize_aliases_with_analysis(func, FunctionAnalysis::build(func))
}

///|
fn canonicalize_aliases_with_analysis(
  func : Function,
  analysis : FunctionAnalysis,
) -> OptResult {
  let result = OptResult::OptResult()
  if func.blocks.length() == 0 {
    return result
  }
  // Active alias environment for the current dominator-tree path.
  let aliases : Array[Value?] = Array::make(func.next_value_id, None)
  fn enter(block_id : Int) -> (Array[Int], Bool) {
    let idx = analysis.block_idx[block_id]
    let block = func.blocks[idx]
    // Track aliases introduced in this block so we can pop on exit.
    let local_aliases : Array[Int] = []
    for inst in block.instructions {
      // Canonicalize operands through currently visible alias chain.
      for i, op in inst.operands {
        let resolved = resolve_copy(op, aliases)
        if resolved.id != op.id {
          inst.operands[i] = resolved
          result.mark_changed()
        }
      }
      // If this instruction defines a copy, make its destination an alias.
      if inst.opcode is Scalar(Copy) &&
        inst.first_result() is Some(dest) &&
        inst.operands.length() > 0 {
        aliases[dest.id] = Some(inst.operands[0])
        local_aliases.push(dest.id)
      }
    }
    // Canonicalize terminator operands as well.
    if block.terminator is Some(term) {
      let new_term = propagate_copies_in_terminator(term, aliases, result)
      block.terminator = Some(new_term)
    }
    (local_aliases, true)
  }

  // Walk dominated children, then pop this block's aliases.
  if analysis.cfg.is_valid(0) {
    visit_dominator_tree(analysis.domtree, 0, enter, fn(local_aliases) {
      for id in local_aliases {
        aliases[id] = None
      }
    })
  }
  result
}

///|
/// Resolve a value through copy chain
fn resolve_copy(v : Value, copies : Array[Value?]) -> Value {
  let mut current = v
  while copies[current.id] is Some(source) {
    current = source
  }
  current
}

///|
/// Propagate copies in terminator
fn propagate_copies_in_terminator(
  term : Terminator,
  copies : Array[Value?],
  result : OptResult,
) -> Terminator {
  fn canonical(value : Value) -> Value {
    let resolved = resolve_copy(value, copies)
    if resolved.id != value.id {
      result.mark_changed()
    }
    resolved
  }
  match term {
    Jump(target, args) => {
      for index, value in args {
        args[index] = canonical(value)
      }
      Jump(target, args)
    }
    Brz(cond, then_t, else_t) => Brz(canonical(cond), then_t, else_t)
    Brnz(cond, then_t, else_t) => Brnz(canonical(cond), then_t, else_t)
    Branch(cond, true_t, true_args, false_t, false_args) => {
      for index, value in true_args {
        true_args[index] = canonical(value)
      }
      for index, value in false_args {
        false_args[index] = canonical(value)
      }
      Branch(canonical(cond), true_t, true_args, false_t, false_args)
    }
    BrTable(index, targets, default_t) =>
      BrTable(canonical(index), targets, default_t)
    Return(values) => {
      for index, value in values {
        values[index] = canonical(value)
      }
      Return(values)
    }
    Trap(_) | TrapExit(_) => term
  }
}
