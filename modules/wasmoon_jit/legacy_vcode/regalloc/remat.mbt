// Cranelift-style rematerialization for VCode.
//
// Cranelift performs rematerialization in IR opts (egraph/elaborate) by cloning
// cheap-to-recompute instructions (especially constants) into blocks where they
// are used, shortening live ranges and reducing register pressure.
//
// Wasmoon’s VCode is already close to machine code; we implement a conservative
// subset that clones cheap, side-effect-free defs into each use block when the
// value is used across blocks.
//
// Current remat candidates (kept conservative, Cranelift-style):
// - integer/float constants (LoadConst*)
// - runtime function pointers and direct function addresses (Load*FuncPtr/LoadFuncAddr)

///|
priv struct RematDef {
  opcode : @instr.VCodeOpcode
  cls : @abi.RegClass
  uses : Array[@abi.Reg]
  use_constraints : Array[@abi.OperandConstraint]
}

///|
fn is_long_distance_remat_candidate(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    LoadConst(_)
    | LoadConstF32(_)
    | LoadConstF64(_)
    | LoadGCFuncPtr(_)
    | LoadJITFuncPtr(_)
    | LoadExceptionFuncPtr(_)
    | LoadFuncAddr(_) => true
    _ => false
  }
}

///|
fn is_cross_block_remat_candidate(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    LoadConst(_)
    | LoadConstF32(_)
    | LoadConstF64(_)
    | LoadGCFuncPtr(_)
    | LoadJITFuncPtr(_)
    | LoadExceptionFuncPtr(_)
    | LoadFuncAddr(_) => true
    _ => false
  }
}

///|
fn clone_remat_inst(def : RematDef, dst : @abi.VReg) -> @instr.VCodeInst {
  let inst = @instr.VCodeInst::new(def.opcode)
  inst.add_def({ reg: Virtual(dst) })
  for i in 0..<def.uses.length() {
    let use_reg = def.uses[i]
    let constraint = def.use_constraints[i]
    match constraint {
      FixedReg(preg) => inst.add_use_fixed(use_reg, preg)
      Any => inst.add_use(use_reg)
    }
  }
  inst
}

///|
fn regalloc_class(cls : @abi.RegClass) -> @core_regalloc.RegClass {
  match cls {
    Int => Int
    Float32 | Float64 => Float
    Vector => Vector
  }
}

///|
fn remat_virtual_reg(vreg : @abi.VReg) -> @core_regalloc.VirtualReg {
  { id: vreg.id, class: regalloc_class(vreg.class) }
}

///|
fn remat_plan_key(block_id : Int, inst_index : Int, vreg_id : Int) -> Int {
  (block_id * 1_000_003 + inst_index) * 1_000_003 + vreg_id
}

///|
fn add_remat_use(
  out : Array[@core_regalloc.RematUseInfo],
  block_id : Int,
  inst_index : Int,
  reg : @abi.Reg,
) -> Unit {
  if reg is Virtual(vreg) {
    out.push({ vreg: remat_virtual_reg(vreg), block_id, inst_index })
  }
}

///|
fn count_remat_plan(
  plans : Array[@core_regalloc.RematCloneInfo],
) -> Map[Int, Int] {
  let counts : Map[Int, Int] = {}
  for plan in plans {
    let key = remat_plan_key(plan.block_id, plan.inst_index, plan.vreg.id)
    counts.set(key, counts.get(key).unwrap_or(0) + 1)
  }
  counts
}

///|
fn remat_local_plan_key(block_id : Int, vreg_id : Int) -> Int {
  block_id * 1_000_003 + vreg_id
}

///|
fn count_local_remat_plan(
  plans : Array[@core_regalloc.RematLocalCloneInfo],
) -> Map[Int, Int] {
  let counts : Map[Int, Int] = {}
  for plan in plans {
    let key = remat_local_plan_key(plan.block_id, plan.vreg.id)
    counts.set(key, counts.get(key).unwrap_or(0) + 1)
  }
  counts
}

///|
fn collect_remat_uses(
  func : VCodeFunction,
) -> Array[@core_regalloc.RematUseInfo] {
  let remat_uses : Array[@core_regalloc.RematUseInfo] = []
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      for operand in inst.uses {
        add_remat_use(remat_uses, block.id, inst_idx, operand)
      }
    }
    if block.terminator is Some(term) {
      let term_idx = block.insts.length()
      match term {
        Jump(_, args) =>
          for arg in args {
            add_remat_use(remat_uses, block.id, term_idx, arg)
          }
        Branch(cond, _, _) =>
          add_remat_use(remat_uses, block.id, term_idx, cond)
        BranchCmp(lhs, rhs, _, _, _, _) => {
          add_remat_use(remat_uses, block.id, term_idx, lhs)
          add_remat_use(remat_uses, block.id, term_idx, rhs)
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          add_remat_use(remat_uses, block.id, term_idx, lhs)
        BranchZero(reg, _, _, _, _) =>
          add_remat_use(remat_uses, block.id, term_idx, reg)
        BrTable(index, _, _) =>
          add_remat_use(remat_uses, block.id, term_idx, index)
        Return(vals) =>
          for value in vals {
            add_remat_use(remat_uses, block.id, term_idx, value)
          }
        Trap(_) => ()
      }
    }
  }
  remat_uses
}

///|
/// Clone long-distance rematerializable defs within the same block.
///
/// This mirrors Cranelift's remat intent for cheap constants: shorten very long
/// live ranges by re-defining constants near far-away uses.
pub fn rematerialize_long_distance_constants(
  func : VCodeFunction,
) -> VCodeFunction {
  let remat_defs : Map[Int, RematDef] = {}
  let remat_def_infos : Array[@core_regalloc.RematDefInfo] = []
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      if is_long_distance_remat_candidate(inst.opcode) &&
        inst.defs.length() == 1 &&
        inst.def_constraints.length() == 1 &&
        inst.def_constraints[0] is Any &&
        inst.defs[0].reg is Virtual(vreg) &&
        remat_defs.get(vreg.id) is None {
        remat_defs.set(vreg.id, {
          opcode: inst.opcode,
          cls: vreg.class,
          uses: inst.uses.copy(),
          use_constraints: inst.use_constraints.copy(),
        })
        remat_def_infos.push({
          vreg: remat_virtual_reg(vreg),
          block_id: block.id,
          inst_index: inst_idx,
        })
      }
    }
  }
  if remat_defs.is_empty() {
    return func
  }
  let min_distance = 4
  let per_vreg_clone_cap = 16
  let remat_plan_counts = count_remat_plan(
    @core_regalloc.plan_long_distance_rematerializations(
      remat_def_infos,
      collect_remat_uses(func),
      min_distance~,
      per_vreg_clone_cap~,
    ),
  )
  for i in 0..<func.blocks.length() {
    let block = func.blocks[i]
    let new_block = @block.VCodeBlock::new(block.id)
    for p in block.params {
      new_block.params.push(p)
    }
    let clone_count : Map[Int, Int] = {}
    fn maybe_remat_use(
      func : VCodeFunction,
      reg : @abi.Reg,
      block_id : Int,
      use_inst_idx : Int,
      remat_defs : Map[Int, RematDef],
      clone_count : Map[Int, Int],
      new_block : @block.VCodeBlock,
      remat_plan_counts : Map[Int, Int],
    ) -> @abi.Reg {
      match reg {
        Virtual(v) =>
          match remat_defs.get(v.id) {
            Some(def) => {
              let key = remat_plan_key(block_id, use_inst_idx, v.id)
              let planned = remat_plan_counts.get(key).unwrap_or(0)
              if planned <= 0 {
                return reg
              }
              remat_plan_counts.set(key, planned - 1)
              let cloned = clone_count.get(v.id).unwrap_or(0)
              let nv = func.new_vreg(def.cls)
              let inst = clone_remat_inst(def, nv)
              new_block.insts.push(inst)
              clone_count.set(v.id, cloned + 1)
              Virtual(nv)
            }
            None => reg
          }
        _ => reg
      }
    }

    for inst_idx, inst in block.insts {
      for u_idx, u in inst.uses {
        inst.uses[u_idx] = maybe_remat_use(
          func,
          u,
          block.id,
          inst_idx,
          remat_defs,
          clone_count,
          new_block,
          remat_plan_counts,
        )
      }
      new_block.insts.push(inst)
    }
    if block.terminator is Some(term) {
      let term_idx = block.insts.length()
      let new_term = match term {
        Jump(target, args) => {
          let new_args : Array[@abi.Reg] = []
          for a in args {
            new_args.push(
              maybe_remat_use(
                func,
                a,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                remat_plan_counts,
              ),
            )
          }
          @instr.Jump(target, new_args)
        }
        Branch(cond, t, e) =>
          Branch(
            maybe_remat_use(
              func,
              cond,
              block.id,
              term_idx,
              remat_defs,
              clone_count,
              new_block,
              remat_plan_counts,
            ),
            t,
            e,
          )
        BranchCmp(lhs, rhs, cond, is64, t, e) =>
          BranchCmp(
            maybe_remat_use(
              func,
              lhs,
              block.id,
              term_idx,
              remat_defs,
              clone_count,
              new_block,
              remat_plan_counts,
            ),
            maybe_remat_use(
              func,
              rhs,
              block.id,
              term_idx,
              remat_defs,
              clone_count,
              new_block,
              remat_plan_counts,
            ),
            cond,
            is64,
            t,
            e,
          )
        BranchCmpImm(lhs, imm, cond, is64, t, e) =>
          BranchCmpImm(
            maybe_remat_use(
              func,
              lhs,
              block.id,
              term_idx,
              remat_defs,
              clone_count,
              new_block,
              remat_plan_counts,
            ),
            imm,
            cond,
            is64,
            t,
            e,
          )
        BranchZero(reg, is_nonzero, is64, t, e) =>
          BranchZero(
            maybe_remat_use(
              func,
              reg,
              block.id,
              term_idx,
              remat_defs,
              clone_count,
              new_block,
              remat_plan_counts,
            ),
            is_nonzero,
            is64,
            t,
            e,
          )
        BrTable(index, targets, default) =>
          BrTable(
            maybe_remat_use(
              func,
              index,
              block.id,
              term_idx,
              remat_defs,
              clone_count,
              new_block,
              remat_plan_counts,
            ),
            targets,
            default,
          )
        Return(vals) => {
          let new_vals : Array[@abi.Reg] = []
          for v in vals {
            new_vals.push(
              maybe_remat_use(
                func,
                v,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                remat_plan_counts,
              ),
            )
          }
          Return(new_vals)
        }
        Trap(msg) => Trap(msg)
      }
      new_block.set_terminator(new_term)
    }
    func.blocks[i] = new_block
  }
  func
}

///|
/// Rematerialize cross-block cheap defs:
/// - Detect vregs defined by rematerializable opcodes.
/// - If such a vreg is used in a different block than its def, clone the
///   defining opcode into each such use block and rewrite uses to a block-local
///   vreg.
///
/// This is intentionally conservative and mirrors Cranelift’s “clone remat
/// values into the block where used” strategy.
pub fn rematerialize_cross_block_constants(
  func : VCodeFunction,
) -> VCodeFunction {
  // vreg_id -> rematerializable def
  let remat_defs : Map[Int, RematDef] = {}
  let remat_def_infos : Array[@core_regalloc.RematDefInfo] = []

  // 1) Collect rematerializable defs.
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      if is_cross_block_remat_candidate(inst.opcode) &&
        inst.defs.length() == 1 &&
        inst.def_constraints.length() == 1 &&
        inst.def_constraints[0] is Any &&
        inst.defs[0].reg is Virtual(vreg) &&
        remat_defs.get(vreg.id) is None {
        remat_defs.set(vreg.id, {
          opcode: inst.opcode,
          cls: vreg.class,
          uses: inst.uses.copy(),
          use_constraints: inst.use_constraints.copy(),
        })
        remat_def_infos.push({
          vreg: remat_virtual_reg(vreg),
          block_id: block.id,
          inst_index: inst_idx,
        })
      }
    }
  }
  if remat_defs.is_empty() {
    return func
  }
  let remat_plan_counts = count_local_remat_plan(
    @core_regalloc.plan_cross_block_rematerializations(
      remat_def_infos,
      collect_remat_uses(func),
    ),
  )

  // 2) Rebuild blocks and materialize remat defs at first use position.
  for i in 0..<func.blocks.length() {
    let block = func.blocks[i]
    let new_block = @block.VCodeBlock::new(block.id)
    for p in block.params {
      new_block.params.push(p)
    }
    // Per-block remat cache, mirrors Cranelift remat_copies[(block, value)].
    let local_map : Map[Int, @abi.VReg] = {}
    fn rewrite_use_with_local_remat(
      func : VCodeFunction,
      reg : @abi.Reg,
      remat_defs : Map[Int, RematDef],
      local_map : Map[Int, @abi.VReg],
      block_id : Int,
      new_block : @block.VCodeBlock,
      remat_plan_counts : Map[Int, Int],
    ) -> @abi.Reg {
      match reg {
        Virtual(v) =>
          match local_map.get(v.id) {
            Some(nv) => Virtual(nv)
            None =>
              match remat_defs.get(v.id) {
                Some(def) => {
                  let key = remat_local_plan_key(block_id, v.id)
                  let planned = remat_plan_counts.get(key).unwrap_or(0)
                  if planned > 0 {
                    remat_plan_counts.set(key, planned - 1)
                    let nv = func.new_vreg(def.cls)
                    local_map.set(v.id, nv)
                    new_block.insts.push(clone_remat_inst(def, nv))
                    Virtual(nv)
                  } else {
                    reg
                  }
                }
                None => reg
              }
          }
        _ => reg
      }
    }

    for inst in block.insts {
      for j, u in inst.uses {
        inst.uses[j] = rewrite_use_with_local_remat(
          func,
          u,
          remat_defs,
          local_map,
          block.id,
          new_block,
          remat_plan_counts,
        )
      }
      new_block.insts.push(inst)
    }
    if block.terminator is Some(term) {
      let new_term = match term {
        Jump(target, args) => {
          let new_args : Array[@abi.Reg] = []
          for a in args {
            new_args.push(
              rewrite_use_with_local_remat(
                func,
                a,
                remat_defs,
                local_map,
                block.id,
                new_block,
                remat_plan_counts,
              ),
            )
          }
          @instr.Jump(target, new_args)
        }
        Branch(cond, t, e) =>
          Branch(
            rewrite_use_with_local_remat(
              func,
              cond,
              remat_defs,
              local_map,
              block.id,
              new_block,
              remat_plan_counts,
            ),
            t,
            e,
          )
        BranchCmp(lhs, rhs, cond, is64, t, e) =>
          BranchCmp(
            rewrite_use_with_local_remat(
              func,
              lhs,
              remat_defs,
              local_map,
              block.id,
              new_block,
              remat_plan_counts,
            ),
            rewrite_use_with_local_remat(
              func,
              rhs,
              remat_defs,
              local_map,
              block.id,
              new_block,
              remat_plan_counts,
            ),
            cond,
            is64,
            t,
            e,
          )
        BranchZero(reg, is_nonzero, is64, t, e) =>
          BranchZero(
            rewrite_use_with_local_remat(
              func,
              reg,
              remat_defs,
              local_map,
              block.id,
              new_block,
              remat_plan_counts,
            ),
            is_nonzero,
            is64,
            t,
            e,
          )
        BranchCmpImm(lhs, imm, cond, is64, t, e) =>
          BranchCmpImm(
            rewrite_use_with_local_remat(
              func,
              lhs,
              remat_defs,
              local_map,
              block.id,
              new_block,
              remat_plan_counts,
            ),
            imm,
            cond,
            is64,
            t,
            e,
          )
        Return(vals) => {
          let new_vals : Array[@abi.Reg] = []
          for r in vals {
            new_vals.push(
              rewrite_use_with_local_remat(
                func,
                r,
                remat_defs,
                local_map,
                block.id,
                new_block,
                remat_plan_counts,
              ),
            )
          }
          Return(new_vals)
        }
        BrTable(index, targets, default) =>
          BrTable(
            rewrite_use_with_local_remat(
              func,
              index,
              remat_defs,
              local_map,
              block.id,
              new_block,
              remat_plan_counts,
            ),
            targets,
            default,
          )
        Trap(msg) => Trap(msg)
      }
      new_block.set_terminator(new_term)
    }
    func.blocks[i] = new_block
  }
  func
}
