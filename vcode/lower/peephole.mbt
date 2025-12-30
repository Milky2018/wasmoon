// VCode Peephole Optimization Pass
// Performs local optimizations on VCode before register allocation
//
// Implemented optimizations:
// 1. AddImm(0) elimination: add x, y, #0 → mov x, y (or eliminate if x == y)
// 2. SubImm(0) elimination: sub x, y, #0 → mov x, y (or eliminate if x == y)
// 3. Redundant move elimination: mov x, x → nop
// 4. Add(x, 0) / Sub(x, 0) with constant tracking
// 5. Constant propagation for immediate operands

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
    Jump(_) | Trap(_) => ()
  }
}

///|
/// Collect uses from block parameters (values that flow to successor blocks)
fn collect_block_param_uses(
  block : @block.VCodeBlock,
  func : VCodeFunction,
  used : @hashset.HashSet[Int],
) -> Unit {
  // Get successor block IDs from terminator
  let successors : Array[Int] = match block.terminator {
    Some(Jump(target)) => [target]
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
/// Check if an instruction is pure (no side effects) and can be eliminated if unused
fn is_pure_instruction(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    // Pure arithmetic/logic - safe to eliminate
    Add(_)
    | AddImm(_, _)
    | Sub(_)
    | SubImm(_, _)
    | Mul(_)
    | And
    | Or
    | Xor
    | Shl(_)
    | AShr(_)
    | LShr(_)
    | Rotr(_)
    | Not
    | Cmp(_, _)
    | FCmp(_)
    | Extend(_)
    | Truncate
    | Move
    | LoadConst(_)
    | LoadConstF32(_)
    | LoadConstF64(_)
    | FAdd(_)
    | FSub(_)
    | FMul(_)
    | FDiv(_)
    | FSqrt(_)
    | FAbs(_)
    | FNeg(_)
    | AddShifted(_, _)
    | SubShifted(_, _)
    | AndShifted(_, _)
    | OrShifted(_, _)
    | XorShifted(_, _)
    | Madd
    | Msub
    | Mneg
    | Select
    | SelectCmp(_, _)
    | Clz(_)
    | Popcnt(_)
    | Rbit(_)
    | IntToFloat(_)
    | FPromote
    | FDemote
    | Bitcast => true
    // Instructions with side effects - keep
    _ => false
  }
}

///|
/// Run peephole optimization on a single block
/// Returns the number of instructions eliminated
fn optimize_block(
  block : @block.VCodeBlock,
  func : VCodeFunction,
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
    // DCE disabled for now - needs more work on cross-block analysis
    // let is_dead = if inst.defs.length() == 1 && is_pure_instruction(inst.opcode) {
    //   if get_def_vreg_id(inst.defs[0]) is Some(def_id) {
    //     not(used.contains(def_id))
    //   } else {
    //     false
    //   }
    // } else {
    //   false
    // }
    // if is_dead {
    //   eliminated = eliminated + 1
    //   continue
    // }

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
    Move => {
      if inst.defs.length() > 0 && inst.uses.length() > 0 {
        let def = inst.defs[0]
        let use_ = inst.uses[0]
        if same_vreg(def.reg, use_) {
          return None
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
/// Run peephole optimization on an entire VCode function
/// This should be called after lower_function and before register allocation
pub fn optimize_vcode(func : VCodeFunction) -> Unit {
  let mut total_eliminated = 0
  for block in func.blocks {
    // Create fresh state for each block (conservative approach)
    // TODO: Could use dataflow analysis for cross-block optimization
    let state = PeepholeState::new()
    total_eliminated = total_eliminated + optimize_block(block, func, state)
  }
  // Optionally log statistics
  // if total_eliminated > 0 {
  //   println("Peephole: eliminated \{total_eliminated} instructions")
  // }
}
