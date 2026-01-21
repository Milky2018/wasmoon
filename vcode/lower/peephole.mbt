// VCode Peephole Optimization Pass
// Performs local optimizations on VCode before register allocation
//
// Implemented optimizations:
// 1. AddImm(0) elimination: add x, y, #0 → mov x, y (or eliminate if x == y)
// 2. SubImm(0) elimination: sub x, y, #0 → mov x, y (or eliminate if x == y)
// 3. Redundant move elimination: mov x, x → nop
// 4. Add(x, 0) / Sub(x, 0) with constant tracking
// 5. Constant propagation for immediate operands
// 6. Store merging: two adjacent store8 → store16, store16 → store32, etc.
// 7. Load merging: two adjacent load8 → load16, load16 → load32, etc.
// 8. Load-store forwarding: store followed by load from same address

///|
/// State for tracking vreg values during peephole optimization
priv struct PeepholeState {
  // Map from vreg id to the constant value it holds (if any)
  constants : Map[Int, Int64]
  // Map from vreg id to its source vreg (for move tracking)
  copies : Map[Int, Int]
}

///|
fn PeepholeState::new() -> PeepholeState {
  { constants: {}, copies: {} }
}

///|
/// Get the vreg id from a Reg if it's virtual
fn get_vreg_id(reg : @abi.Reg) -> Int? {
  match reg {
    Virtual(vreg) => Some(vreg.id)
    Physical(_) => None
  }
}

///|
/// Get the vreg id from a Writable if it's virtual
fn get_def_vreg_id(writable : @abi.Writable) -> Int? {
  get_vreg_id(writable.reg)
}

///|
/// Check if two registers are the same virtual register
fn same_vreg(r1 : @abi.Reg, r2 : @abi.Reg) -> Bool {
  match (r1, r2) {
    (Virtual(v1), Virtual(v2)) => v1.id == v2.id
    _ => false
  }
}

///|
/// Collect all used vregs from an instruction (both uses and terminator uses)
fn collect_uses(inst : @instr.VCodeInst, used : @hashset.HashSet[Int]) -> Unit {
  for use_ in inst.uses {
    if get_vreg_id(use_) is Some(id) {
      used.add(id)
    }
  }
}

///|
/// Count uses of virtual regs across the whole function.
fn collect_use_counts(func : @regalloc.VCodeFunction) -> Map[Int, Int] {
  let counts : Map[Int, Int] = {}
  let add_use = fn(reg : @abi.Reg) -> Unit {
    if get_vreg_id(reg) is Some(id) {
      let count = counts.get(id).unwrap_or(0)
      counts.set(id, count + 1)
    }
  }
  for block in func.blocks {
    for inst in block.insts {
      for use_ in inst.uses {
        add_use(use_)
      }
    }
    if block.terminator is Some(term) {
      let term_uses = match term {
        @instr.VCodeTerminator::Jump(_, args)
        | @instr.VCodeTerminator::Return(args) => args
        @instr.VCodeTerminator::Branch(cond, _, _)
        | @instr.VCodeTerminator::BranchZero(cond, _, _, _, _)
        | @instr.VCodeTerminator::BrTable(cond, _, _) => [cond]
        @instr.VCodeTerminator::BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
        @instr.VCodeTerminator::BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
        @instr.VCodeTerminator::Trap(_) => []
      }
      for use_ in term_uses {
        add_use(use_)
      }
    }
  }
  counts
}

///|
/// Collect uses from terminator
fn collect_terminator_uses(
  term : @instr.VCodeTerminator,
  used : @hashset.HashSet[Int],
) -> Unit {
  match term {
    Branch(cond, _, _) => if get_vreg_id(cond) is Some(id) { used.add(id) }
    BranchCmp(lhs, rhs, _, _, _, _) => {
      if get_vreg_id(lhs) is Some(id) {
        used.add(id)
      }
      if get_vreg_id(rhs) is Some(id) {
        used.add(id)
      }
    }
    BranchZero(reg, _, _, _, _) =>
      if get_vreg_id(reg) is Some(id) {
        used.add(id)
      }
    BranchCmpImm(lhs, _, _, _, _, _) =>
      if get_vreg_id(lhs) is Some(id) {
        used.add(id)
      }
    Return(values) =>
      for v in values {
        if get_vreg_id(v) is Some(id) {
          used.add(id)
        }
      }
    BrTable(index, _, _) => if get_vreg_id(index) is Some(id) { used.add(id) }
    Jump(_, args) =>
      for a in args {
        if get_vreg_id(a) is Some(id) {
          used.add(id)
        }
      }
    Trap(_) => ()
  }
}

///|
/// Collect uses from block parameters (values that flow to successor blocks)
fn collect_block_param_uses(
  block : @block.VCodeBlock,
  func : @regalloc.VCodeFunction,
  used : @hashset.HashSet[Int],
) -> Unit {
  // Get successor block IDs from terminator
  let successors : Array[Int] = match block.terminator {
    Some(Jump(target, _args)) => [target]
    Some(Branch(_, then_b, else_b)) => [then_b, else_b]
    Some(BranchCmp(_, _, _, _, then_b, else_b)) => [then_b, else_b]
    Some(BranchZero(_, _, _, then_b, else_b)) => [then_b, else_b]
    Some(BranchCmpImm(_, _, _, _, then_b, else_b)) => [then_b, else_b]
    Some(BrTable(_, targets, default)) => {
      let result : Array[Int] = []
      for t in targets {
        result.push(t)
      }
      result.push(default)
      result
    }
    _ => []
  }

  // For each successor, mark its block parameters as used
  for succ_id in successors {
    if succ_id >= 0 && succ_id < func.blocks.length() {
      let succ_block = func.blocks[succ_id]
      for param in succ_block.params {
        used.add(param.id)
      }
    }
  }
}

///|
/// Run peephole optimization on a single block
/// Returns the number of instructions eliminated
fn optimize_block(
  block : @block.VCodeBlock,
  func : @regalloc.VCodeFunction,
  state : PeepholeState,
) -> Int {
  // Phase 1: Collect all used vregs (for dead code elimination)
  let used : @hashset.HashSet[Int] = @hashset.new()

  // Collect uses from all instructions
  for inst in block.insts {
    collect_uses(inst, used)
  }

  // Collect uses from terminator
  if block.terminator is Some(term) {
    collect_terminator_uses(term, used)
  }

  // Collect uses from successor block parameters
  collect_block_param_uses(block, func, used)

  // Phase 2: Apply peephole optimizations and dead code elimination
  let mut eliminated = 0
  let new_insts : Array[@instr.VCodeInst] = []
  for inst in block.insts {
    // NOTE: Intra-block DCE requires global liveness analysis.
    // The `used` set only contains uses from THIS block, but a value defined
    // here might be used in a different block. Proper DCE needs to know which
    // vregs are live-out from each block, which requires cross-block analysis.
    // For now, DCE is only done by the register allocator's dead code marking.

    let optimized = optimize_instruction(inst, state)
    match optimized {
      Some(new_inst) => {
        new_insts.push(new_inst)
        // Update state based on the new instruction
        update_state(new_inst, state)
      }
      None =>
        // Instruction was eliminated
        eliminated = eliminated + 1
    }
  }
  // Replace block instructions with optimized ones
  block.insts.clear()
  for inst in new_insts {
    block.insts.push(inst)
  }
  eliminated
}

///|
/// Helper to create a Move instruction with given def and use
fn make_move(def : @abi.Writable, use_ : @abi.Reg) -> @instr.VCodeInst {
  let new_inst = @instr.VCodeInst::new(Move)
  new_inst.add_def(def)
  new_inst.add_use(use_)
  new_inst
}

///|
/// Helper to create an AddImm instruction
fn make_add_imm(
  imm : Int,
  is_64 : Bool,
  def : @abi.Writable,
  use_ : @abi.Reg,
) -> @instr.VCodeInst {
  let new_inst = @instr.VCodeInst::new(AddImm(imm, is_64))
  new_inst.add_def(def)
  new_inst.add_use(use_)
  new_inst
}

///|
/// Helper to create a SubImm instruction
fn make_sub_imm(
  imm : Int,
  is_64 : Bool,
  def : @abi.Writable,
  use_ : @abi.Reg,
) -> @instr.VCodeInst {
  let new_inst = @instr.VCodeInst::new(SubImm(imm, is_64))
  new_inst.add_def(def)
  new_inst.add_use(use_)
  new_inst
}

///|
/// Optimize a single instruction
/// Returns None if the instruction should be eliminated
/// Returns Some(inst) with possibly modified instruction otherwise
fn optimize_instruction(
  inst : @instr.VCodeInst,
  state : PeepholeState,
) -> @instr.VCodeInst? {
  match inst.opcode {
    // AddImm(0) → Move or eliminate
    AddImm(0, _) => {
      if inst.defs.length() > 0 && inst.uses.length() > 0 {
        let def = inst.defs[0]
        let use_ = inst.uses[0]
        if same_vreg(def.reg, use_) {
          // add x, x, #0 → eliminate
          return None
        }
        // add x, y, #0 → mov x, y
        return Some(make_move(def, use_))
      }
      Some(inst)
    }
    // SubImm(0) → Move or eliminate
    SubImm(0, _) => {
      if inst.defs.length() > 0 && inst.uses.length() > 0 {
        let def = inst.defs[0]
        let use_ = inst.uses[0]
        if same_vreg(def.reg, use_) {
          // sub x, x, #0 → eliminate
          return None
        }
        // sub x, y, #0 → mov x, y
        return Some(make_move(def, use_))
      }
      Some(inst)
    }
    // Move x, x → eliminate
    // Move x, const → LoadConst x, value
    Move => {
      if inst.defs.length() > 0 && inst.uses.length() > 0 {
        let def = inst.defs[0]
        let use_ = inst.uses[0]
        if same_vreg(def.reg, use_) {
          return None
        }
        // If source is a known constant, replace with LoadConst
        if get_vreg_id(use_) is Some(use_id) {
          if state.constants.get(use_id) is Some(const_val) {
            let new_inst = @instr.VCodeInst::new(LoadConst(const_val))
            new_inst.add_def(def)
            return Some(new_inst)
          }
        }
      }
      Some(inst)
    }
    // Add with constant 0 operand → Move or eliminate
    Add(is_64) => {
      if inst.uses.length() >= 2 {
        // Check if second operand is known to be 0
        if get_vreg_id(inst.uses[1]) is Some(use_id) {
          if state.constants.get(use_id) is Some(0L) {
            // add x, y, const_0 → mov x, y
            if inst.defs.length() > 0 {
              let def = inst.defs[0]
              let use_ = inst.uses[0]
              if same_vreg(def.reg, use_) {
                return None
              }
              return Some(make_move(def, use_))
            }
          }
        }
        // Check if first operand is known to be 0
        if get_vreg_id(inst.uses[0]) is Some(use_id) {
          if state.constants.get(use_id) is Some(0L) {
            // add x, const_0, y → mov x, y
            if inst.defs.length() > 0 {
              let def = inst.defs[0]
              let use_ = inst.uses[1]
              if same_vreg(def.reg, use_) {
                return None
              }
              return Some(make_move(def, use_))
            }
          }
        }
        // Check if we can use AddImm instead of Add with reg
        if get_vreg_id(inst.uses[1]) is Some(use_id) {
          if state.constants.get(use_id) is Some(const_val) {
            let imm = const_val.to_int()
            // AArch64 ADD immediate: 12-bit unsigned (0-4095)
            if imm >= 0 && imm <= 4095 {
              if inst.defs.length() > 0 {
                return Some(
                  make_add_imm(imm, is_64, inst.defs[0], inst.uses[0]),
                )
              }
            }
          }
        }
      }
      Some(inst)
    }
    // Sub with constant 0 operand → Move or eliminate
    Sub(is_64) => {
      if inst.uses.length() >= 2 {
        // Check if second operand is known to be 0
        if get_vreg_id(inst.uses[1]) is Some(use_id) {
          if state.constants.get(use_id) is Some(0L) {
            // sub x, y, const_0 → mov x, y
            if inst.defs.length() > 0 {
              let def = inst.defs[0]
              let use_ = inst.uses[0]
              if same_vreg(def.reg, use_) {
                return None
              }
              return Some(make_move(def, use_))
            }
          }
        }
        // Check if we can use SubImm instead of Sub with reg
        if get_vreg_id(inst.uses[1]) is Some(use_id) {
          if state.constants.get(use_id) is Some(const_val) {
            let imm = const_val.to_int()
            // AArch64 SUB immediate: 12-bit unsigned (0-4095)
            if imm >= 0 && imm <= 4095 {
              if inst.defs.length() > 0 {
                return Some(
                  make_sub_imm(imm, is_64, inst.defs[0], inst.uses[0]),
                )
              }
            }
          }
        }
      }
      Some(inst)
    }
    // Track constant loads
    LoadConst(_) => Some(inst)
    // Default: keep instruction unchanged
    _ => Some(inst)
  }
}

///|
/// Update state based on an instruction's effects
fn update_state(inst : @instr.VCodeInst, state : PeepholeState) -> Unit {
  match inst.opcode {
    // Track constant loads
    LoadConst(value) =>
      if inst.defs.length() > 0 {
        if get_def_vreg_id(inst.defs[0]) is Some(def_id) {
          state.constants.set(def_id, value)
        }
      }
    // Track moves as copies
    Move =>
      if inst.defs.length() > 0 && inst.uses.length() > 0 {
        if get_def_vreg_id(inst.defs[0]) is Some(def_id) {
          if get_vreg_id(inst.uses[0]) is Some(use_id) {
            state.copies.set(def_id, use_id)
            // If source has a known constant, propagate it
            if state.constants.get(use_id) is Some(c) {
              state.constants.set(def_id, c)
            }
          }
        }
      }
    // Any other def invalidates tracking for that vreg
    _ =>
      for def in inst.defs {
        if get_def_vreg_id(def) is Some(def_id) {
          state.constants.remove(def_id)
          state.copies.remove(def_id)
        }
      }
  }
}

///|
/// In-place update optimization
/// Pattern: vA = op ... vB ...; vB = mov vA  →  vB = op ... vB ...
/// This eliminates redundant moves when the result is only used to update
/// the same operand.
fn optimize_inplace_updates(block : @block.VCodeBlock) -> Int {
  let mut eliminated = 0

  // Build def-use chains for vregs within this block
  // def_inst[vreg_id] = instruction index that defines it
  let def_inst : Map[Int, Int] = {}
  // use_count[vreg_id] = number of uses within this block
  let use_count : Map[Int, Int] = {}
  for i, inst in block.insts {
    // Track definitions
    for def in inst.defs {
      if get_def_vreg_id(def) is Some(def_id) {
        def_inst.set(def_id, i)
      }
    }
    // Track uses
    for use_ in inst.uses {
      if get_vreg_id(use_) is Some(use_id) {
        let count = use_count.get(use_id).unwrap_or(0)
        use_count.set(use_id, count + 1)
      }
    }
  }
  if block.terminator is Some(term) {
    let term_uses = match term {
      @instr.VCodeTerminator::Jump(_, args)
      | @instr.VCodeTerminator::Return(args) => args
      @instr.VCodeTerminator::Branch(cond, _, _)
      | @instr.VCodeTerminator::BranchZero(cond, _, _, _, _)
      | @instr.VCodeTerminator::BrTable(cond, _, _) => [cond]
      @instr.VCodeTerminator::BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
      @instr.VCodeTerminator::BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
      @instr.VCodeTerminator::Trap(_) => []
    }
    for use_ in term_uses {
      if get_vreg_id(use_) is Some(use_id) {
        let count = use_count.get(use_id).unwrap_or(0)
        use_count.set(use_id, count + 1)
      }
    }
  }
  if block.terminator is Some(term) {
    let term_uses = match term {
      @instr.VCodeTerminator::Jump(_, args)
      | @instr.VCodeTerminator::Return(args) => args
      @instr.VCodeTerminator::Branch(cond, _, _)
      | @instr.VCodeTerminator::BranchZero(cond, _, _, _, _)
      | @instr.VCodeTerminator::BrTable(cond, _, _) => [cond]
      @instr.VCodeTerminator::BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
      @instr.VCodeTerminator::BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
      @instr.VCodeTerminator::Trap(_) => []
    }
    for use_ in term_uses {
      if get_vreg_id(use_) is Some(use_id) {
        let count = use_count.get(use_id).unwrap_or(0)
        use_count.set(use_id, count + 1)
      }
    }
  }

  // Look for patterns: vA = op ... vB ...; vB = mov vA
  // where vA is only used by the mov AND vB is not used between def and mov
  let to_eliminate : @hashset.HashSet[Int] = @hashset.new()
  let replace_def : Map[Int, Int] = {} // inst_idx -> new_def_vreg_id
  for i, inst in block.insts {
    if inst.opcode is Move && inst.defs.length() == 1 && inst.uses.length() == 1 {
      let def_vreg = get_def_vreg_id(inst.defs[0])
      let use_vreg = get_vreg_id(inst.uses[0])
      if def_vreg is Some(dst_id) && use_vreg is Some(src_id) {
        // This is: dst = mov src
        // Check if src is defined in this block and has only 1 use (this mov)
        if def_inst.get(src_id) is Some(def_idx) {
          if use_count.get(src_id) == Some(1) {
            // src is only used by this mov
            let def_instr = block.insts[def_idx]
            // Check if dst is an operand of the def instruction
            let mut dst_is_operand = false
            for use_ in def_instr.uses {
              if get_vreg_id(use_) == Some(dst_id) {
                dst_is_operand = true
                break
              }
            }
            if dst_is_operand && is_inplace_safe(def_instr.opcode) {
              // Pattern matched! vA = op ... vB ...; vB = mov vA
              // Now check that vB (dst_id) is not used between def and mov
              let mut dst_used_between = false
              for j = def_idx + 1; j < i; j = j + 1 {
                for use_ in block.insts[j].uses {
                  if get_vreg_id(use_) == Some(dst_id) {
                    dst_used_between = true
                    break
                  }
                }
                if dst_used_between {
                  break
                }
              }
              if !dst_used_between {
                // Safe to apply optimization
                to_eliminate.add(i)
                replace_def.set(def_idx, dst_id)
                eliminated = eliminated + 1
              }
            }
          }
        }
      }
    }
  }

  // Apply transformations if any found
  if eliminated > 0 {
    let new_insts : Array[@instr.VCodeInst] = []
    for i, inst in block.insts {
      if to_eliminate.contains(i) {
        // Skip this mov instruction
        continue
      }
      if replace_def.get(i) is Some(new_def_id) {
        // Replace the def vreg
        if inst.defs.length() > 0 {
          let old_def = inst.defs[0]
          if old_def.reg is Virtual(old_vreg) {
            let new_vreg : @abi.VReg = { id: new_def_id, class: old_vreg.class }
            let new_writable : @abi.Writable = {
              reg: @abi.Reg::Virtual(new_vreg),
            }
            inst.defs[0] = new_writable
          }
        }
      }
      new_insts.push(inst)
    }
    block.insts.clear()
    for inst in new_insts {
      block.insts.push(inst)
    }
  }
  eliminated
}

///|
/// Check if an instruction is safe for in-place update
/// (reads operands before writing result)
fn is_inplace_safe(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    // Arithmetic operations - all read before write
    Add(_) | Sub(_) | Mul(_) => true
    AddImm(_, _) | SubImm(_, _) => true
    // Logical operations
    And | Or | Xor | Shl(_) => true
    // Moves are not safe (we're eliminating them, not transforming them)
    Move => false
    // Load/store have side effects
    Load(_, _) | Store(_, _) => false
    // Other complex operations - be conservative
    _ => false
  }
}

// ============ Store/Load Merging ============

///|
/// Info about a narrow memory operation for merging analysis
priv struct MemOpInfo {
  bits : Int // 8, 16, or 32
  offset : Int // Memory offset
  base_vreg_id : Int // Base address vreg id
  value_vreg_id : Int // Value vreg id (for stores) or def vreg id (for loads)
  is_store : Bool // true for store, false for load
}

///|
/// Extract memory operation info from an instruction
fn get_mem_op_info(inst : @instr.VCodeInst) -> MemOpInfo? {
  match inst.opcode {
    StorePtrNarrow(bits, offset) =>
      if inst.uses.length() >= 2 {
        let base_id = get_vreg_id(inst.uses[0])
        let value_id = get_vreg_id(inst.uses[1])
        match (base_id, value_id) {
          (Some(b), Some(v)) =>
            Some({
              bits,
              offset,
              base_vreg_id: b,
              value_vreg_id: v,
              is_store: true,
            })
          _ => None
        }
      } else {
        None
      }
    LoadPtrNarrow(bits, _, offset) =>
      if inst.uses.length() >= 1 && inst.defs.length() >= 1 {
        let base_id = get_vreg_id(inst.uses[0])
        let def_id = get_def_vreg_id(inst.defs[0])
        match (base_id, def_id) {
          (Some(b), Some(d)) =>
            Some({
              bits,
              offset,
              base_vreg_id: b,
              value_vreg_id: d,
              is_store: false,
            })
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// Check if two memory ops can be merged (adjacent, same base, compatible sizes)
fn can_merge_mem_ops(op1 : MemOpInfo, op2 : MemOpInfo) -> Bool {
  // Must have same base address
  if op1.base_vreg_id != op2.base_vreg_id {
    return false
  }
  // Must be same type (both stores or both loads)
  if op1.is_store != op2.is_store {
    return false
  }
  // Must have same bit width
  if op1.bits != op2.bits {
    return false
  }
  // Must be adjacent (op2 immediately follows op1 in memory)
  let expected_offset = op1.offset + op1.bits / 8
  op2.offset == expected_offset
}

///|
/// Merge stores optimization
/// Pattern: store8 [base+off], val1; store8 [base+off+1], val2
/// Becomes: combined = (val2 << 8) | val1; store16 [base+off], combined
fn optimize_store_merging(
  block : @block.VCodeBlock,
  func : @regalloc.VCodeFunction,
) -> Int {
  if block.insts.length() < 2 {
    return 0
  }

  // Track which instructions to remove and what to insert
  let to_remove : @hashset.HashSet[Int] = @hashset.new()
  let insertions : Array[(Int, Array[@instr.VCodeInst])] = []
  let mut merged = 0

  // Scan for consecutive store8 pairs
  let mut i = 0
  while i < block.insts.length() - 1 {
    let op1 = get_mem_op_info(block.insts[i])
    let op2 = get_mem_op_info(block.insts[i + 1])
    match (op1, op2) {
      (Some(s1), Some(s2)) =>
        if s1.is_store &&
          s2.is_store &&
          s1.bits == 8 &&
          can_merge_mem_ops(s1, s2) {
          // Found adjacent store8 pair - merge into store16
          let new_insts = create_merged_store(func, s1, s2, 16)
          to_remove.add(i)
          to_remove.add(i + 1)
          insertions.push((i, new_insts))
          merged = merged + 1
          i = i + 2 // Skip the second store
          continue
        }
      _ => ()
    }
    i = i + 1
  }

  // Apply transformations
  if merged > 0 {
    apply_block_transformations(block, to_remove, insertions)
  }
  merged
}

///|
/// Create merged store instructions
/// Combines two values: combined = val_lo | (val_hi << bits)
fn create_merged_store(
  func : @regalloc.VCodeFunction,
  lo : MemOpInfo,
  hi : MemOpInfo,
  new_bits : Int,
) -> Array[@instr.VCodeInst] {
  let result : Array[@instr.VCodeInst] = []

  // Use OrShifted to combine: combined = val_lo | (val_hi << 8)
  // OrShifted(Lsl, 8) computes: Rd = Rn | (Rm << 8)
  let combined_vreg = func.new_vreg(Int)
  let shift_amount = lo.bits // Shift by lo.bits (8 for store8->store16)
  let or_shifted_inst = @instr.VCodeInst::new(OrShifted(Lsl, shift_amount))
  or_shifted_inst.add_def({ reg: Virtual(combined_vreg) })
  or_shifted_inst.add_use(Virtual({ id: lo.value_vreg_id, class: Int })) // Rn = val_lo
  or_shifted_inst.add_use(Virtual({ id: hi.value_vreg_id, class: Int })) // Rm = val_hi
  result.push(or_shifted_inst)

  // Create merged store: store16 [base+off], combined
  let store_inst = @instr.VCodeInst::new(StorePtrNarrow(new_bits, lo.offset))
  store_inst.add_use(Virtual({ id: lo.base_vreg_id, class: Int }))
  store_inst.add_use(Virtual(combined_vreg))
  result.push(store_inst)
  result
}

///|
/// Merge loads optimization
/// Pattern: val1 = load8 [base+off]; val2 = load8 [base+off+1]
/// If both values are only used for store8 to same relative offsets:
/// Becomes: combined = load16 [base+off]; store16 [dst+off], combined
fn optimize_load_merging(
  block : @block.VCodeBlock,
  func : @regalloc.VCodeFunction,
) -> Int {
  if block.insts.length() < 2 {
    return 0
  }
  let to_remove : @hashset.HashSet[Int] = @hashset.new()
  let insertions : Array[(Int, Array[@instr.VCodeInst])] = []
  let mut merged = 0

  // Build def-use map for this block
  let def_map : Map[Int, Int] = {} // vreg_id -> instruction index
  for i, inst in block.insts {
    for def in inst.defs {
      if get_def_vreg_id(def) is Some(id) {
        def_map.set(id, i)
      }
    }
  }

  // Scan for load8 pairs that are used by store8 pairs
  let mut i = 0
  while i < block.insts.length() - 1 {
    let op1 = get_mem_op_info(block.insts[i])
    let op2 = get_mem_op_info(block.insts[i + 1])
    match (op1, op2) {
      (Some(l1), Some(l2)) =>
        if !l1.is_store &&
          !l2.is_store &&
          l1.bits == 8 &&
          can_merge_mem_ops(l1, l2) {
          // Found adjacent load8 pair
          // Check if they are used by adjacent store8 pair
          match find_store_pair_for_loads(block, l1, l2, i + 2) {
            Some((s1_idx, s2_idx, dst_base, dst_offset)) => {
              // Can merge both load and store
              let new_insts = create_merged_load_store(
                func, l1, dst_base, dst_offset,
              )
              to_remove.add(i)
              to_remove.add(i + 1)
              to_remove.add(s1_idx)
              to_remove.add(s2_idx)
              insertions.push((i, new_insts))
              merged = merged + 1
              i = i + 2
              continue
            }
            None => ()
          }
        }
      _ => ()
    }
    i = i + 1
  }
  if merged > 0 {
    apply_block_transformations(block, to_remove, insertions)
  }
  merged
}

///|
/// Find store8 pair that uses the values from load8 pair
fn find_store_pair_for_loads(
  block : @block.VCodeBlock,
  load1 : MemOpInfo,
  load2 : MemOpInfo,
  start_idx : Int,
) -> (Int, Int, Int, Int)? {
  // Look for: store8 [dst+off], load1_result; store8 [dst+off+1], load2_result
  let mut found_s1 : (Int, Int, Int)? = None // (idx, base_vreg, offset)
  for j = start_idx; j < block.insts.length(); j = j + 1 {
    let op = get_mem_op_info(block.insts[j])
    if op is Some(s) && s.is_store && s.bits == 8 {
      if s.value_vreg_id == load1.value_vreg_id {
        // Found store of load1 result
        found_s1 = Some((j, s.base_vreg_id, s.offset))
      } else if s.value_vreg_id == load2.value_vreg_id {
        // Found store of load2 result - check if it matches
        if found_s1 is Some((s1_idx, s1_base, s1_off)) {
          if s.base_vreg_id == s1_base && s.offset == s1_off + 1 {
            return Some((s1_idx, j, s1_base, s1_off))
          }
        }
      }
    }
  }
  None
}

///|
/// Create merged load + store instructions
fn create_merged_load_store(
  func : @regalloc.VCodeFunction,
  load_info : MemOpInfo,
  dst_base : Int,
  dst_offset : Int,
) -> Array[@instr.VCodeInst] {
  let result : Array[@instr.VCodeInst] = []

  // Create merged load: combined = load16u [src_base+off]
  let combined_vreg = func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(
    LoadPtrNarrow(16, false, load_info.offset),
  )
  load_inst.add_def({ reg: Virtual(combined_vreg) })
  load_inst.add_use(Virtual({ id: load_info.base_vreg_id, class: Int }))
  result.push(load_inst)

  // Create merged store: store16 [dst_base+off], combined
  let store_inst = @instr.VCodeInst::new(StorePtrNarrow(16, dst_offset))
  store_inst.add_use(Virtual({ id: dst_base, class: Int }))
  store_inst.add_use(Virtual(combined_vreg))
  result.push(store_inst)
  result
}

///|
/// Load-store forwarding optimization
/// Pattern: store [base+off], val; ... ; load [base+off] (no intervening store)
/// Becomes: store [base+off], val; mov result, val
fn optimize_load_store_forwarding(block : @block.VCodeBlock) -> Int {
  // Build a map of recent stores: (base_vreg, offset, bits) -> value_vreg
  // Reset when we see a potentially aliasing store
  let store_map : Map[String, Int] = {} // "base:offset:bits" -> value_vreg_id
  let mut forwarded = 0
  let to_replace : Array[(Int, @instr.VCodeInst)] = []
  for i, inst in block.insts {
    match inst.opcode {
      StorePtrNarrow(bits, offset) => {
        store_map.clear()
        if inst.uses.length() >= 2 {
          if get_vreg_id(inst.uses[0]) is Some(base) &&
            get_vreg_id(inst.uses[1]) is Some(val) {
            let key = "\{base}:\{offset}:\{bits}"
            store_map.set(key, val)
          }
        }
      }
      LoadPtrNarrow(bits, signed, offset) =>
        if inst.uses.length() >= 1 && inst.defs.length() >= 1 {
          if get_vreg_id(inst.uses[0]) is Some(base) {
            let key = "\{base}:\{offset}:\{bits}"
            if store_map.get(key) is Some(val_vreg) {
              if get_def_vreg_id(inst.defs[0]) is Some(_) {
                // Forwarding must preserve the load semantics:
                // - narrow stores truncate to `bits`
                // - loads sign/zero-extend from `bits`
                // Implement by extending the stored value.
                let kind = match (bits, signed) {
                  (8, true) => @instr.Signed8To64
                  (8, false) => @instr.Unsigned8To64
                  (16, true) => @instr.Signed16To64
                  (16, false) => @instr.Unsigned16To64
                  (32, true) => @instr.Signed32To64
                  (32, false) => @instr.Unsigned32To64
                  _ => continue
                }
                let ext = @instr.VCodeInst::new(Extend(kind))
                ext.add_def(inst.defs[0])
                ext.add_use(Virtual({ id: val_vreg, class: Int }))
                to_replace.push((i, ext))
                forwarded = forwarded + 1
              }
            }
          }
        }
      // Any other store invalidates the map (conservative)
      Store(_, _) | StorePtr(_, _) => store_map.clear()
      // Calls may have side effects
      CallPtr(_, _, _) | ReturnCallIndirect(_, _) => store_map.clear()
      _ => ()
    }
  }

  // Apply replacements
  for pair in to_replace {
    let (idx, new_inst) = pair
    block.insts[idx] = new_inst
  }
  forwarded
}

///|
/// Apply block transformations (remove and insert instructions)
fn apply_block_transformations(
  block : @block.VCodeBlock,
  to_remove : @hashset.HashSet[Int],
  insertions : Array[(Int, Array[@instr.VCodeInst])],
) -> Unit {
  // Sort insertions by position (descending) to maintain indices
  insertions.sort_by(fn(a, b) { b.0 - a.0 })
  let new_insts : Array[@instr.VCodeInst] = []
  let insert_map : Map[Int, Array[@instr.VCodeInst]] = {}
  for pair in insertions {
    insert_map.set(pair.0, pair.1)
  }
  for i, inst in block.insts {
    // Insert new instructions before this position if any
    if insert_map.get(i) is Some(new) {
      for new_inst in new {
        new_insts.push(new_inst)
      }
    }
    // Skip removed instructions
    if !to_remove.contains(i) {
      new_insts.push(inst)
    }
  }
  block.insts.clear()
  for inst in new_insts {
    block.insts.push(inst)
  }
}

///|
/// Build CFG successors for a block
fn get_successors(term : @instr.VCodeTerminator?) -> Array[Int] {
  match term {
    Some(@instr.VCodeTerminator::Jump(target, _)) => [target]
    Some(@instr.VCodeTerminator::Branch(_, then_b, else_b)) => [then_b, else_b]
    Some(@instr.VCodeTerminator::BranchCmp(_, _, _, _, then_b, else_b)) =>
      [then_b, else_b]
    Some(@instr.VCodeTerminator::BranchZero(_, _, _, then_b, else_b)) =>
      [then_b, else_b]
    Some(@instr.VCodeTerminator::BranchCmpImm(_, _, _, _, then_b, else_b)) =>
      [then_b, else_b]
    Some(@instr.VCodeTerminator::BrTable(_, targets, default)) => {
      let out : Array[Int] = []
      for t in targets {
        out.push(t)
      }
      out.push(default)
      out
    }
    _ => []
  }
}

///|
/// Collect vreg uses from a terminator
fn collect_terminator_uses_simple(
  term : @instr.VCodeTerminator,
  used : @hashset.HashSet[Int],
) -> Unit {
  collect_terminator_uses(term, used)
}

///|
/// Deep-copy a `HashSet[Int]` by re-inserting elements.
///
/// Note: do NOT use `@hashset.HashSet::copy()` here: the core HashSet copy is
/// shallow and shares mutable `Entry` nodes (probe sequence length is mutated on
/// insert/remove). Mutating the "copy" would corrupt the source set and can
/// lead to non-termination.
fn clone_hashset_int(set : @hashset.HashSet[Int]) -> @hashset.HashSet[Int] {
  let out : @hashset.HashSet[Int] = @hashset.new()
  for x in set {
    out.add(x)
  }
  out
}

///|
/// Compute dominators for all blocks (simple iterative algorithm).
fn compute_dominators(
  func : @regalloc.VCodeFunction,
) -> Array[@hashset.HashSet[Int]] {
  let n = func.blocks.length()

  // IMPORTANT: avoid `Array::make(n, [])` because it aliases the same array.
  let preds : Array[Array[Int]] = []
  for _ in 0..<n {
    preds.push([])
  }
  for b in func.blocks {
    let succs = get_successors(b.terminator)
    for s in succs {
      if s >= 0 && s < n {
        preds[s].push(b.id)
      }
    }
  }
  let all : @hashset.HashSet[Int] = @hashset.new()
  for i in 0..<n {
    all.add(i)
  }

  // IMPORTANT: avoid `Array::make(n, set)` because it aliases the same set.
  let dom : Array[@hashset.HashSet[Int]] = []
  for i in 0..<n {
    if i == 0 {
      let s : @hashset.HashSet[Int] = @hashset.new()
      s.add(0)
      dom.push(s)
    } else {
      dom.push(clone_hashset_int(all))
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for b in 1..<n {
      let mut new_dom : @hashset.HashSet[Int] = @hashset.new()
      // If block has no preds (unreachable), keep only itself.
      if preds[b].length() == 0 {
        new_dom.add(b)
      } else {
        // Start with dom of first predecessor, then intersect.
        new_dom = clone_hashset_int(dom[preds[b][0]])
        for pi in 1..<preds[b].length() {
          let p = preds[b][pi]
          let to_remove : Array[Int] = []
          for x in new_dom {
            if !dom[p].contains(x) {
              to_remove.push(x)
            }
          }
          for x in to_remove {
            new_dom.remove(x)
          }
        }
        new_dom.add(b)
      }
      // Compare by size + membership.
      if new_dom.length() != dom[b].length() {
        dom[b] = new_dom
        changed = true
      } else {
        let mut same = true
        for x in new_dom {
          if !dom[b].contains(x) {
            same = false
            break
          }
        }
        if !same {
          dom[b] = new_dom
          changed = true
        }
      }
    }
  }
  dom
}

///|
/// Loop-invariant code motion for simple invariants.
///
/// Detect natural loops via backedges (h dominates b for edge b->h). If the
/// loop header has a unique predecessor outside the loop, treat it as a
/// preheader and hoist:
/// - `LoadConst` (with heuristics to avoid reg pressure)
/// - a small set of loop-invariant `Load`/`LoadPtr` from immutable vmctx-derived data
fn licm_hoist_invariants(func : @regalloc.VCodeFunction) -> Unit {
  let n = func.blocks.length()
  if n == 0 {
    return
  }

  // Build preds.
  let preds : Array[Array[Int]] = []
  for _ in 0..<n {
    preds.push([])
  }
  for b in func.blocks {
    let succs = get_successors(b.terminator)
    for s in succs {
      if s >= 0 && s < n {
        preds[s].push(b.id)
      }
    }
  }
  let dom = compute_dominators(func)

  // Identify backedges and hoist per-loop.
  for b in func.blocks {
    let succs = get_successors(b.terminator)
    for h in succs {
      if h >= 0 && h < n && dom[b.id].contains(h) {
        // Natural loop nodes.
        let loop_nodes : @hashset.HashSet[Int] = @hashset.new()
        loop_nodes.add(h)
        loop_nodes.add(b.id)
        let work : Array[Int] = [b.id]
        while work.length() > 0 {
          let cur = work.pop().unwrap()
          for p in preds[cur] {
            if !loop_nodes.contains(p) {
              loop_nodes.add(p)
              if p != h {
                work.push(p)
              }
            }
          }
        }

        // Find unique outside predecessor of header = preheader.
        let outside_preds : Array[Int] = []
        for p in preds[h] {
          if !loop_nodes.contains(p) {
            outside_preds.push(p)
          }
        }
        if outside_preds.length() != 1 {
          continue
        }
        let preheader_id = outside_preds[0]

        // Compute all vreg ids used outside loop.
        let used_outside : @hashset.HashSet[Int] = @hashset.new()
        for i in 0..<n {
          if loop_nodes.contains(i) {
            continue
          }
          let blk = func.blocks[i]
          for inst in blk.insts {
            collect_uses(inst, used_outside)
          }
          if blk.terminator is Some(term) {
            collect_terminator_uses_simple(term, used_outside)
          }
        }
        fn is_expensive_const(value : Int64) -> Bool {
          // Heuristic: values outside 16-bit range usually need multiple
          // instructions (movz+movk) to materialize.
          value < 0L || value > 0xFFFFL
        }

        // Count vreg uses inside the loop, to avoid hoisting cheap constants that
        // would increase live ranges/reg pressure.
        let use_count_in_loop : Map[Int, Int] = {}
        for i in 0..<n {
          if !loop_nodes.contains(i) {
            continue
          }
          let blk = func.blocks[i]
          for inst in blk.insts {
            for u in inst.uses {
              if get_vreg_id(u) is Some(uid) {
                let c = use_count_in_loop.get(uid).unwrap_or(0)
                use_count_in_loop.set(uid, c + 1)
              }
            }
          }
          if blk.terminator is Some(term) {
            let used : @hashset.HashSet[Int] = @hashset.new()
            collect_terminator_uses_simple(term, used)
            for uid in used {
              let c = use_count_in_loop.get(uid).unwrap_or(0)
              use_count_in_loop.set(uid, c + 1)
            }
          }
        }

        // Build set of vregs defined inside the loop.
        let defs_in_loop : @hashset.HashSet[Int] = @hashset.new()
        for i in 0..<n {
          if !loop_nodes.contains(i) {
            continue
          }
          let blk = func.blocks[i]
          for inst in blk.insts {
            for def in inst.defs {
              if get_def_vreg_id(def) is Some(did) {
                defs_in_loop.add(did)
              }
            }
          }
        }
        fn is_vmctx_reg(r : @abi.Reg) -> Bool {
          r is Physical(p) && p.index == @abi.REG_VMCTX
        }

        // Def map for virtual registers (only the simple case we care about).
        let def_inst : Map[Int, @instr.VCodeInst] = {}
        for blk in func.blocks {
          for inst in blk.insts {
            if inst.defs.length() == 1 &&
              get_def_vreg_id(inst.defs[0]) is Some(did) {
              def_inst.set(did, inst)
            }
          }
        }

        // Is this vreg an immutable pointer derived from vmctx.func_table?
        fn is_immutable_ptr(vreg_id : Int) -> Bool {
          match def_inst.get(vreg_id) {
            Some(inst) =>
              if inst.opcode is Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET) &&
                inst.uses.length() == 1 {
                is_vmctx_reg(inst.uses[0])
              } else {
                false
              }
            None => false
          }
        }

        // Checks whether a load is safe to hoist.
        fn is_hoistable_load(op : @instr.VCodeOpcode, base : @abi.Reg) -> Bool {
          match op {
            Load(I64, off) | LoadPtr(I64, off) =>
              if is_vmctx_reg(base) {
                // Only allow vmctx.func_table load at the moment.
                off == @abi.VMCTX_FUNC_TABLE_OFFSET
              } else if base is Virtual(v) {
                // Allow loads from the func_table pointer.
                is_immutable_ptr(v.id)
              } else {
                false
              }
            _ => false
          }
        }

        // Hoist invariants from loop blocks to preheader.
        let hoisted : Array[@instr.VCodeInst] = []
        let hoisted_defs : @hashset.HashSet[Int] = @hashset.new()
        for i in 0..<n {
          if !loop_nodes.contains(i) {
            continue
          }
          let blk = func.blocks[i]
          let new_insts : Array[@instr.VCodeInst] = []
          for inst in blk.insts {
            // Helper: can we treat this inst as loop-invariant now?
            fn base_is_invariant(base : @abi.Reg) -> Bool {
              if is_vmctx_reg(base) {
                return true
              }
              match base {
                Virtual(v) =>
                  !defs_in_loop.contains(v.id) || hoisted_defs.contains(v.id)
                _ => false
              }
            }

            // 1) Constants
            match inst.opcode {
              LoadConst(value) =>
                if inst.defs.length() == 1 &&
                  get_def_vreg_id(inst.defs[0]) is Some(def_id) {
                  let use_cnt = use_count_in_loop.get(def_id).unwrap_or(0)
                  if !used_outside.contains(def_id) &&
                    (is_expensive_const(value) || use_cnt >= 3) {
                    hoisted.push(inst)
                    hoisted_defs.add(def_id)
                    continue
                  }
                }
              _ => ()
            }

            // 2) Hoistable loads from immutable regions
            if inst.defs.length() == 1 && inst.uses.length() == 1 {
              if get_def_vreg_id(inst.defs[0]) is Some(def_id) {
                if !used_outside.contains(def_id) &&
                  base_is_invariant(inst.uses[0]) &&
                  is_hoistable_load(inst.opcode, inst.uses[0]) {
                  hoisted.push(inst)
                  hoisted_defs.add(def_id)
                  continue
                }
              }
            }
            new_insts.push(inst)
          }
          blk.insts.clear()
          for inst in new_insts {
            blk.insts.push(inst)
          }
        }
        if hoisted.length() > 0 {
          let pre = func.blocks[preheader_id]
          for inst in hoisted {
            pre.insts.push(inst)
          }
        }
      }
    }
  }
}

///|
/// Block-local CSE for immutable vmctx/func_table loads.
///
/// Today this is intentionally conservative:
/// - vmctx base must be `x19`
/// - only track the `vmctx.func_table` pointer (`VMCTX_FUNC_TABLE_OFFSET`)
/// - only CSE `Load(I64, off)` / `LoadPtr(I64, off)` from that func_table pointer
fn cse_immutable_loads(func : @regalloc.VCodeFunction) -> Unit {
  // Collect all vregs that are func_table pointers.
  let func_table_ptrs : @hashset.HashSet[Int] = @hashset.new()
  for blk in func.blocks {
    for inst in blk.insts {
      match inst.opcode {
        Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET)
        | LoadPtr(I64, @abi.VMCTX_FUNC_TABLE_OFFSET) =>
          if inst.defs.length() == 1 && inst.uses.length() == 1 {
            if inst.uses[0] is Physical(p) && p.index == @abi.REG_VMCTX {
              if get_def_vreg_id(inst.defs[0]) is Some(did) {
                func_table_ptrs.add(did)
              }
            }
          }
        _ => ()
      }
    }
  }
  fn is_vmctx(r : @abi.Reg) -> Bool {
    r is Physical(p) && p.index == @abi.REG_VMCTX
  }

  fn canonical_id(id : Int, copies : Map[Int, Int]) -> Int {
    let mut cur = id
    while copies.get(cur) is Some(next) {
      if next == cur {
        break
      }
      cur = next
    }
    cur
  }

  for blk in func.blocks {
    let copies : Map[Int, Int] = {}
    // key: "kind|base|off" -> vreg id
    // kind = 0 for Load, 1 for LoadPtr
    let seen : Map[String, Int] = {}
    let new_insts : Array[@instr.VCodeInst] = []
    for inst in blk.insts {
      // Track simple virtual copies for canonicalization.
      if inst.opcode is Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        if get_def_vreg_id(inst.defs[0]) is Some(dst) {
          if get_vreg_id(inst.uses[0]) is Some(src) {
            copies.set(dst, canonical_id(src, copies))
          }
        }
      }
      let mut replaced = false
      match inst.opcode {
        Load(I64, off) =>
          if inst.defs.length() == 1 && inst.uses.length() == 1 {
            let base = inst.uses[0]
            if base is Virtual(v) {
              let base_id = canonical_id(v.id, copies)
              if func_table_ptrs.contains(base_id) {
                let key = "0|" + base_id.to_string() + "|" + off.to_string()
                if seen.get(key) is Some(prev_id) {
                  let mv = @instr.VCodeInst::new(Move)
                  mv.add_def(inst.defs[0])
                  mv.add_use(Virtual({ id: prev_id, class: Int }))
                  new_insts.push(mv)
                  if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                    copies.set(dst, canonical_id(prev_id, copies))
                  }
                  replaced = true
                } else {
                  seen.set(key, get_def_vreg_id(inst.defs[0]).unwrap())
                }
              }
            }
          }
        LoadPtr(I64, off) =>
          if inst.defs.length() == 1 && inst.uses.length() == 1 {
            let base = inst.uses[0]
            if base is Virtual(v) {
              let base_id = canonical_id(v.id, copies)
              if func_table_ptrs.contains(base_id) {
                let key = "1|" + base_id.to_string() + "|" + off.to_string()
                if seen.get(key) is Some(prev_id) {
                  let mv = @instr.VCodeInst::new(Move)
                  mv.add_def(inst.defs[0])
                  mv.add_use(Virtual({ id: prev_id, class: Int }))
                  new_insts.push(mv)
                  if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                    copies.set(dst, canonical_id(prev_id, copies))
                  }
                  replaced = true
                } else {
                  seen.set(key, get_def_vreg_id(inst.defs[0]).unwrap())
                }
              }
            }
          }
        _ => ()
      }

      // Also CSE duplicate func_table base loads from vmctx: `load.i64 +8 x19`.
      if !replaced {
        match inst.opcode {
          Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET)
          | LoadPtr(I64, @abi.VMCTX_FUNC_TABLE_OFFSET) =>
            if inst.defs.length() == 1 &&
              inst.uses.length() == 1 &&
              is_vmctx(inst.uses[0]) {
              let key = "ftbase"
              if seen.get(key) is Some(prev_id) {
                let mv = @instr.VCodeInst::new(Move)
                mv.add_def(inst.defs[0])
                mv.add_use(Virtual({ id: prev_id, class: Int }))
                new_insts.push(mv)
                if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                  copies.set(dst, canonical_id(prev_id, copies))
                }
                replaced = true
              } else {
                seen.set(key, get_def_vreg_id(inst.defs[0]).unwrap())
              }
            }
          _ => ()
        }
      }
      if !replaced {
        new_insts.push(inst)
      }
    }
    blk.insts.clear()
    for inst in new_insts {
      blk.insts.push(inst)
    }
  }
}

///|
/// Check if two register classes are identical.
fn same_reg_class(a : @abi.RegClass, b : @abi.RegClass) -> Bool {
  match (a, b) {
    (Int, Int) | (Float32, Float32) | (Float64, Float64) | (Vector, Vector) =>
      true
    _ => false
  }
}

///|
/// Convert a compare kind to a branch condition.
fn cmp_kind_to_cond(kind : @instr.CmpKind) -> @instr.Cond {
  match kind {
    Eq => @instr.Cond::Eq
    Ne => @instr.Cond::Ne
    Slt => @instr.Cond::Lt
    Sle => @instr.Cond::Le
    Sgt => @instr.Cond::Gt
    Sge => @instr.Cond::Ge
    Ult => @instr.Cond::Lo
    Ule => @instr.Cond::Ls
    Ugt => @instr.Cond::Hi
    Uge => @instr.Cond::Hs
  }
}

///|
/// Check whether an opcode is trivially dead when its defs are unused.
fn is_trivially_dead_opcode(op : @instr.VCodeOpcode) -> Bool {
  match op {
    Move
    | LoadConst(_)
    | LoadConstF32(_)
    | LoadConstF64(_)
    | LoadConstV128(_)
    | LoadFuncAddr(_)
    | Nop => true
    _ => false
  }
}

///|
/// Remove trivially-dead value defs (constants/moves) across the function.
fn dce_trivially_dead(func : @regalloc.VCodeFunction) -> Unit {
  let mut changed = true
  while changed {
    changed = false
    let used : @hashset.HashSet[Int] = @hashset.new()
    for block in func.blocks {
      for inst in block.insts {
        collect_uses(inst, used)
      }
      if block.terminator is Some(term) {
        collect_terminator_uses(term, used)
      }
    }
    for block in func.blocks {
      let new_insts : Array[@instr.VCodeInst] = []
      for inst in block.insts {
        let mut remove = false
        if is_trivially_dead_opcode(inst.opcode) {
          if inst.defs.length() == 0 {
            remove = true
          } else {
            let mut has_physical_def = false
            let mut any_used = false
            for def in inst.defs {
              match def.reg {
                Physical(_) => has_physical_def = true
                Virtual(v) => if used.contains(v.id) { any_used = true }
              }
            }
            if !has_physical_def && !any_used {
              remove = true
            }
          }
        }
        if remove {
          changed = true
          continue
        }
        new_insts.push(inst)
      }
      block.insts.clear()
      for inst in new_insts {
        block.insts.push(inst)
      }
    }
  }
}

///|
/// Propagate single-use virtual moves within a block.
/// This reduces redundant copies created by earlier passes.
fn propagate_single_use_moves(
  block : @block.VCodeBlock,
  global_use_counts : Map[Int, Int],
) -> Unit {
  let use_counts : Map[Int, Int] = {}
  for inst in block.insts {
    for use_ in inst.uses {
      if get_vreg_id(use_) is Some(vid) {
        let count = use_counts.get(vid).unwrap_or(0)
        use_counts.set(vid, count + 1)
      }
    }
  }
  if block.terminator is Some(term) {
    let term_uses = match term {
      @instr.VCodeTerminator::Jump(_, args)
      | @instr.VCodeTerminator::Return(args) => args
      @instr.VCodeTerminator::Branch(cond, _, _)
      | @instr.VCodeTerminator::BranchZero(cond, _, _, _, _)
      | @instr.VCodeTerminator::BrTable(cond, _, _) => [cond]
      @instr.VCodeTerminator::BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
      @instr.VCodeTerminator::BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
      @instr.VCodeTerminator::Trap(_) => []
    }
    for use_ in term_uses {
      if get_vreg_id(use_) is Some(vid) {
        let count = use_counts.get(vid).unwrap_or(0)
        use_counts.set(vid, count + 1)
      }
    }
  }
  fn resolve_copy(reg : @abi.VReg, copies : Map[Int, @abi.VReg]) -> @abi.VReg {
    let mut cur = reg
    while copies.get(cur.id) is Some(next) {
      if next.id == cur.id {
        break
      }
      cur = next
    }
    cur
  }

  let copies : Map[Int, @abi.VReg] = {}
  let to_remove : @hashset.HashSet[Int] = @hashset.new()
  for i, inst in block.insts {
    if inst.opcode is Move && inst.defs.length() == 1 && inst.uses.length() == 1 {
      if inst.defs[0].reg is Virtual(dst_vreg) &&
        inst.uses[0] is Virtual(src_vreg) {
        if same_reg_class(dst_vreg.class, src_vreg.class) &&
          use_counts.get(dst_vreg.id).unwrap_or(0) == 1 &&
          global_use_counts.get(dst_vreg.id).unwrap_or(0) ==
          use_counts.get(dst_vreg.id).unwrap_or(0) {
          let resolved = resolve_copy(src_vreg, copies)
          copies.set(dst_vreg.id, resolved)
          to_remove.add(i)
        }
      }
    }
  }
  let rewrite_reg = fn(reg : @abi.Reg) -> @abi.Reg {
    match reg {
      Virtual(v) =>
        if copies.get(v.id) is Some(target) {
          Virtual(resolve_copy(target, copies))
        } else {
          reg
        }
      _ => reg
    }
  }
  let new_insts : Array[@instr.VCodeInst] = []
  for i, inst in block.insts {
    if to_remove.contains(i) {
      continue
    }
    for u in 0..<inst.uses.length() {
      inst.uses[u] = rewrite_reg(inst.uses[u])
    }
    new_insts.push(inst)
  }
  block.insts.clear()
  for inst in new_insts {
    block.insts.push(inst)
  }
  if block.terminator is Some(term) {
    let new_term = match term {
      @instr.VCodeTerminator::Jump(target, args) => {
        let new_args : Array[@abi.Reg] = []
        for arg in args {
          new_args.push(rewrite_reg(arg))
        }
        @instr.VCodeTerminator::Jump(target, new_args)
      }
      @instr.VCodeTerminator::Branch(cond, then_id, else_id) =>
        @instr.VCodeTerminator::Branch(rewrite_reg(cond), then_id, else_id)
      @instr.VCodeTerminator::BranchCmp(lhs, rhs, cond, is_64, then_id, else_id) =>
        @instr.VCodeTerminator::BranchCmp(
          rewrite_reg(lhs),
          rewrite_reg(rhs),
          cond,
          is_64,
          then_id,
          else_id,
        )
      @instr.VCodeTerminator::BranchZero(
        cond,
        is_nonzero,
        is_64,
        then_id,
        else_id
      ) =>
        @instr.VCodeTerminator::BranchZero(
          rewrite_reg(cond),
          is_nonzero,
          is_64,
          then_id,
          else_id,
        )
      @instr.VCodeTerminator::BranchCmpImm(
        lhs,
        imm,
        cond,
        is_64,
        then_id,
        else_id
      ) =>
        @instr.VCodeTerminator::BranchCmpImm(
          rewrite_reg(lhs),
          imm,
          cond,
          is_64,
          then_id,
          else_id,
        )
      @instr.VCodeTerminator::Return(args) => {
        let new_args : Array[@abi.Reg] = []
        for arg in args {
          new_args.push(rewrite_reg(arg))
        }
        @instr.VCodeTerminator::Return(new_args)
      }
      @instr.VCodeTerminator::BrTable(index, targets, default_id) =>
        @instr.VCodeTerminator::BrTable(rewrite_reg(index), targets, default_id)
      @instr.VCodeTerminator::Trap(msg) => @instr.VCodeTerminator::Trap(msg)
    }
    block.set_terminator(new_term)
  }
}

///|
/// Propagate virtual moves across the whole function and remove redundant copies.
fn propagate_moves_global(func : @regalloc.VCodeFunction) -> Unit {
  let copies : Map[Int, @abi.VReg] = {}
  for block in func.blocks {
    for inst in block.insts {
      if inst.opcode is Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        if inst.defs[0].reg is Virtual(dst_vreg) &&
          inst.uses[0] is Virtual(src_vreg) {
          if same_reg_class(dst_vreg.class, src_vreg.class) {
            copies.set(dst_vreg.id, src_vreg)
          }
        }
      }
    }
  }
  if copies.is_empty() {
    return
  }
  fn resolve_copy(reg : @abi.VReg, copies : Map[Int, @abi.VReg]) -> @abi.VReg {
    let mut cur = reg
    while copies.get(cur.id) is Some(next) {
      if next.id == cur.id {
        break
      }
      cur = next
    }
    cur
  }

  let rewrite_reg = fn(reg : @abi.Reg) -> @abi.Reg {
    match reg {
      Virtual(v) =>
        if copies.get(v.id) is Some(target) {
          Virtual(resolve_copy(target, copies))
        } else {
          reg
        }
      _ => reg
    }
  }
  for block in func.blocks {
    let new_insts : Array[@instr.VCodeInst] = []
    for inst in block.insts {
      for u in 0..<inst.uses.length() {
        inst.uses[u] = rewrite_reg(inst.uses[u])
      }
      if inst.opcode is Move &&
        inst.defs.length() == 1 &&
        inst.defs[0].reg is Virtual(dst_vreg) &&
        copies.contains(dst_vreg.id) {
        continue
      }
      new_insts.push(inst)
    }
    block.insts.clear()
    for inst in new_insts {
      block.insts.push(inst)
    }
    if block.terminator is Some(term) {
      let new_term = match term {
        @instr.VCodeTerminator::Jump(target, args) => {
          let new_args : Array[@abi.Reg] = []
          for arg in args {
            new_args.push(rewrite_reg(arg))
          }
          @instr.VCodeTerminator::Jump(target, new_args)
        }
        @instr.VCodeTerminator::Branch(cond, then_id, else_id) =>
          @instr.VCodeTerminator::Branch(rewrite_reg(cond), then_id, else_id)
        @instr.VCodeTerminator::BranchCmp(
          lhs,
          rhs,
          cond,
          is_64,
          then_id,
          else_id
        ) =>
          @instr.VCodeTerminator::BranchCmp(
            rewrite_reg(lhs),
            rewrite_reg(rhs),
            cond,
            is_64,
            then_id,
            else_id,
          )
        @instr.VCodeTerminator::BranchZero(
          cond,
          is_nonzero,
          is_64,
          then_id,
          else_id
        ) =>
          @instr.VCodeTerminator::BranchZero(
            rewrite_reg(cond),
            is_nonzero,
            is_64,
            then_id,
            else_id,
          )
        @instr.VCodeTerminator::BranchCmpImm(
          lhs,
          imm,
          cond,
          is_64,
          then_id,
          else_id
        ) =>
          @instr.VCodeTerminator::BranchCmpImm(
            rewrite_reg(lhs),
            imm,
            cond,
            is_64,
            then_id,
            else_id,
          )
        @instr.VCodeTerminator::Return(args) => {
          let new_args : Array[@abi.Reg] = []
          for arg in args {
            new_args.push(rewrite_reg(arg))
          }
          @instr.VCodeTerminator::Return(new_args)
        }
        @instr.VCodeTerminator::BrTable(index, targets, default_id) =>
          @instr.VCodeTerminator::BrTable(
            rewrite_reg(index),
            targets,
            default_id,
          )
        @instr.VCodeTerminator::Trap(msg) => @instr.VCodeTerminator::Trap(msg)
      }
      block.set_terminator(new_term)
    }
  }
}

///|
/// Block-local CSE for LoadMemBase (mem=0..), reset on calls.
fn cse_mem_base_loads(func : @regalloc.VCodeFunction) -> Unit {
  for blk in func.blocks {
    let last_base : Map[Int, Int] = {}
    let new_insts : Array[@instr.VCodeInst] = []
    for inst in blk.insts {
      match inst.opcode {
        CallPtr(_, _, _) | ReturnCallIndirect(_, _) => {
          last_base.clear()
          new_insts.push(inst)
        }
        LoadMemBase(mem_idx) =>
          if inst.defs.length() == 1 {
            if last_base.get(mem_idx) is Some(prev_id) {
              let mv = @instr.VCodeInst::new(Move)
              mv.add_def(inst.defs[0])
              mv.add_use(Virtual({ id: prev_id, class: Int }))
              new_insts.push(mv)
              if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                last_base.set(mem_idx, dst)
              }
            } else {
              new_insts.push(inst)
              if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                last_base.set(mem_idx, dst)
              }
            }
          } else {
            new_insts.push(inst)
          }
        _ => new_insts.push(inst)
      }
    }
    blk.insts.clear()
    for inst in new_insts {
      blk.insts.push(inst)
    }
  }
}

///|
/// Fuse `cmp` + `branch` into `br_cmp`/`br_cmp_imm` when the cmp result
/// is only used by the branch terminator.
fn fuse_cmp_branch(func : @regalloc.VCodeFunction) -> Unit {
  let const_defs : Map[Int, Int64] = {}
  for blk in func.blocks {
    for inst in blk.insts {
      if inst.opcode is LoadConst(val) && inst.defs.length() == 1 {
        if get_def_vreg_id(inst.defs[0]) is Some(did) {
          const_defs.set(did, val)
        }
      }
    }
  }
  for blk in func.blocks {
    match blk.terminator {
      Some(@instr.VCodeTerminator::Branch(cond, then_id, else_id)) =>
        if cond is Virtual(cond_vreg) && blk.insts.length() > 0 {
          let mut cond_uses = 0
          for inst in blk.insts {
            for use_ in inst.uses {
              if get_vreg_id(use_) is Some(uid) && uid == cond_vreg.id {
                cond_uses = cond_uses + 1
              }
            }
          }
          if cond_uses == 0 {
            let mut cmp_idx : Int? = None
            let mut cmp_inst : @instr.VCodeInst? = None
            for i, inst in blk.insts {
              if inst.defs.length() == 1 &&
                get_def_vreg_id(inst.defs[0]) == Some(cond_vreg.id) {
                cmp_idx = Some(i)
                cmp_inst = Some(inst)
                break
              }
            }
            if cmp_idx is Some(idx) &&
              cmp_inst is Some(cmp) &&
              cmp.opcode is Cmp(kind, is_64) &&
              cmp.defs.length() == 1 &&
              cmp.uses.length() == 2 {
              let lhs = cmp.uses[0]
              let rhs = cmp.uses[1]
              let cond = cmp_kind_to_cond(kind)
              let new_term = if rhs is Virtual(rhs_vreg) &&
                const_defs.get(rhs_vreg.id) is Some(val) &&
                is_valid_add_imm(val) {
                @instr.VCodeTerminator::BranchCmpImm(
                  lhs,
                  val.to_int(),
                  cond,
                  is_64,
                  then_id,
                  else_id,
                )
              } else {
                @instr.VCodeTerminator::BranchCmp(
                  lhs, rhs, cond, is_64, then_id, else_id,
                )
              }
              let new_insts : Array[@instr.VCodeInst] = []
              for i, inst in blk.insts {
                if i != idx {
                  new_insts.push(inst)
                }
              }
              blk.insts.clear()
              for inst in new_insts {
                blk.insts.push(inst)
              }
              blk.set_terminator(new_term)
            }
          }
        }
      _ => ()
    }
  }
}

///|
/// Run peephole optimization on an entire VCode function
/// This should be called after lower_function and before register allocation
pub fn optimize_vcode(func : @regalloc.VCodeFunction) -> Unit {
  // Pass 0: loop-invariant code motion
  licm_hoist_invariants(func)
  // Pass 0.5: block-local CSE for immutable loads
  cse_immutable_loads(func)
  // Pass 0.6: block-local CSE for LoadMemBase
  cse_mem_base_loads(func)

  // Pass 1: Basic peephole optimizations (constant folding, move elimination)
  for block in func.blocks {
    let state = PeepholeState::new()
    optimize_block(block, func, state) |> ignore
  }
  // Pass 1.5: Copy propagation for single-use moves
  let global_use_counts = collect_use_counts(func)
  for block in func.blocks {
    propagate_single_use_moves(block, global_use_counts)
  }
  // Pass 1.6: Global copy propagation for virtual moves
  propagate_moves_global(func)
  // Pass 1.65: Fuse cmp+branch into compare branches
  fuse_cmp_branch(func)
  // Pass 1.7: Drop trivially-dead value defs
  dce_trivially_dead(func)

  // Pass 2: In-place update optimization
  for block in func.blocks {
    optimize_inplace_updates(block) |> ignore
  }

  // Pass 3: Memory operation merging (store8+store8 -> store16, etc.)
  for block in func.blocks {
    optimize_store_merging(block, func) |> ignore
  }

  // Pass 4: Load-store pair merging (for memcpy-like patterns)
  for block in func.blocks {
    optimize_load_merging(block, func) |> ignore
  }

  // Pass 5: Load-store forwarding (store then load -> store then mov)
  for block in func.blocks {
    optimize_load_store_forwarding(block) |> ignore
  }
}
