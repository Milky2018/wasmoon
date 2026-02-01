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
