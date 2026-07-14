// ============ Loop Invariant Code Motion (LICM) ============

///|
/// Loop Invariant Code Motion
/// Moves loop-invariant computations out of loops to the preheader
fn hoist_loop_invariants(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  let cfg = CFG::build(func)
  let loops = cfg.find_loops()

  // Build a map from value id to the block where it's defined
  let value_to_block : @hashmap.HashMap[Int, Int] = HashMap([])
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
/// 1. It has no observable effects and cannot trap
/// 2. All its operands are either defined outside the loop or are loop-invariant
fn is_loop_invariant(
  inst : Inst,
  loop_ : Loop,
  value_to_block : @hashmap.HashMap[Int, Int],
  invariant_values : @hashmap.HashMap[Int, Bool],
) -> Bool {
  // Instructions with observable effects or traps cannot be hoisted.
  if inst.opcode.semantics().must_preserve_if_unused() {
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
  let invariant_values : @hashmap.HashMap[Int, Bool] = HashMap([])

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

// ============ Strength Reduction ============

///|
/// Strength Reduction
/// Replaces expensive operations with cheaper equivalents
/// Examples: multiplication by power of 2 -> shift, division by power of 2 -> shift
fn reduce_strength(func : Function) -> OptResult {
  let result = OptResult::OptResult()

  // Build constant map
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Scalar(IntConst(v)) && inst.first_result() is Some(r) {
        if r.ty is I32 {
          constants.set(r.id, I32(v.to_int()))
        } else {
          constants.set(r.id, I64(v))
        }
      }
    }
  }

  // Apply strength reduction
  for block in func.blocks {
    let rewritten : Array[Inst] = []
    for inst in block.instructions {
      match inst.opcode {
        // Multiplication by power of 2 -> left shift
        Scalar(IntBinary(Mul)) =>
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
              let shift_operand = append_iconst(
                rewritten,
                func,
                const_operand.ty,
                shift_amount.to_int64(),
              )
              // Replace imul with ishl
              inst.opcode = Scalar(IntBinary(ShiftLeft))
              inst.operands.clear()
              inst.operands.push(other_operand)
              inst.operands.push(shift_operand)
              result.mark_changed()
            }
          }
        // Division by power of 2 -> right shift (for unsigned)
        Scalar(IntBinary(UnsignedDiv)) =>
          if inst.operands.length() == 2 {
            let (const_idx, shift_amount) = find_power_of_two_operand(
              inst.operands,
              constants,
            )
            if const_idx == 1 && shift_amount >= 0 {
              let dividend = inst.operands[0]
              let divisor = inst.operands[1]
              let shift_operand = append_iconst(
                rewritten,
                func,
                divisor.ty,
                shift_amount.to_int64(),
              )
              // Only reduce if divisor is constant power of 2
              // Replace udiv with ushr (logical right shift)
              inst.opcode = Scalar(IntBinary(UnsignedShiftRight))
              inst.operands.clear()
              inst.operands.push(dividend)
              inst.operands.push(shift_operand)
              result.mark_changed()
            }
          }
        // Modulo by power of 2 -> bitwise AND
        Scalar(IntBinary(UnsignedRem)) =>
          if inst.operands.length() == 2 {
            let (const_idx, shift_amount) = find_power_of_two_operand(
              inst.operands,
              constants,
            )
            if const_idx == 1 &&
              shift_amount >= 0 &&
              power_of_two_mask(inst.operands[1], constants) is Some(mask) {
              let dividend = inst.operands[0]
              let divisor = inst.operands[1]
              let mask_operand = append_iconst(
                rewritten,
                func,
                divisor.ty,
                mask,
              )
              // x % (2^n) == x & (2^n - 1)
              inst.opcode = Scalar(IntBinary(And))
              inst.operands.clear()
              inst.operands.push(dividend)
              inst.operands.push(mask_operand)
              result.mark_changed()
            }
          }
        _ => ()
      }
      rewritten.push(inst)
    }
    block.instructions.clear()
    for inst in rewritten {
      block.instructions.push(inst)
    }
  }
  result
}

///|
fn append_iconst(
  instructions : Array[Inst],
  func : Function,
  ty : Type,
  value : Int64,
) -> Value {
  let result = func.new_value(ty)
  instructions.push(func.new_inst(Scalar(IntConst(value)), [], [result]))
  result
}

///|
fn power_of_two_mask(
  value : Value,
  constants : @hashmap.HashMap[Int, ConstValue],
) -> Int64? {
  match constants.get(value.id) {
    Some(I32(v)) => Some((v - 1).to_int64())
    Some(I64(v)) => Some(v - 1L)
    _ => None
  }
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
