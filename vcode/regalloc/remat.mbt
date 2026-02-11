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
// Current remat candidates:
// - integer/float constants (LoadConst*)
// - runtime function pointers and direct function addresses (Load*FuncPtr/LoadFuncAddr)
// - cheap ALU defs that are profitable to re-create near uses (AddImm/SubImm/Extend)

///|
priv struct RematDef {
  opcode : @instr.VCodeOpcode
  def_block_id : Int
  def_inst_idx : Int
  cls : @abi.RegClass
  uses : Array[@abi.Reg]
  use_constraints : Array[@abi.OperandConstraint]
}

///|
fn is_remat_candidate(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    @instr.LoadConst(_)
    | @instr.LoadConstF32(_)
    | @instr.LoadConstF64(_)
    | @instr.AddImm(_, _)
    | @instr.SubImm(_, _)
    | @instr.Extend(_)
    | @instr.LoadGCFuncPtr(_)
    | @instr.LoadJITFuncPtr(_)
    | @instr.LoadExceptionFuncPtr(_)
    | @instr.LoadFuncAddr(_) => true
    _ => false
  }
}

///|
fn record_block_need(
  needs : Map[Int, Set[Int]],
  block_id : Int,
  vreg_id : Int,
) -> Unit {
  match needs.get(block_id) {
    Some(s) => s.add(vreg_id) |> ignore
    None => {
      let s : Set[Int] = Set::new()
      s.add(vreg_id) |> ignore
      needs.set(block_id, s)
    }
  }
}

///|
fn rewrite_use_reg(reg : @abi.Reg, local_map : Map[Int, @abi.VReg]) -> @abi.Reg {
  match reg {
    @abi.Virtual(v) =>
      match local_map.get(v.id) {
        Some(nv) => @abi.Virtual(nv)
        None => reg
      }
    _ => reg
  }
}

///|
fn clone_remat_inst(def : RematDef, dst : @abi.VReg) -> @instr.VCodeInst {
  let inst = @instr.VCodeInst::new(def.opcode)
  inst.add_def({ reg: @abi.Virtual(dst) })
  for i in 0..<def.uses.length() {
    let use_reg = def.uses[i]
    let constraint = def.use_constraints[i]
    match constraint {
      @abi.FixedReg(preg) => inst.add_use_fixed(use_reg, preg)
      @abi.Any => inst.add_use(use_reg)
    }
  }
  inst
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
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      if is_remat_candidate(inst.opcode) &&
        inst.defs.length() == 1 &&
        inst.def_constraints.length() == 1 &&
        inst.def_constraints[0] is @abi.Any &&
        inst.defs[0].reg is @abi.Virtual(vreg) {
        if remat_defs.get(vreg.id) is None {
          remat_defs.set(vreg.id, {
            opcode: inst.opcode,
            def_block_id: block.id,
            def_inst_idx: inst_idx,
            cls: vreg.class,
            uses: inst.uses.copy(),
            use_constraints: inst.use_constraints.copy(),
          })
        }
      }
    }
  }
  if remat_defs.is_empty() {
    return func
  }
  let min_distance = 16
  let per_vreg_clone_cap = 16
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
      min_distance : Int,
      per_vreg_clone_cap : Int,
    ) -> @abi.Reg {
      match reg {
        @abi.Virtual(v) =>
          match remat_defs.get(v.id) {
            Some(def) => {
              if def.def_block_id != block_id {
                return reg
              }
              if use_inst_idx - def.def_inst_idx < min_distance {
                return reg
              }
              let cloned = clone_count.get(v.id).unwrap_or(0)
              if cloned >= per_vreg_clone_cap {
                return reg
              }
              let nv = func.new_vreg(def.cls)
              let inst = clone_remat_inst(def, nv)
              new_block.insts.push(inst)
              clone_count.set(v.id, cloned + 1)
              @abi.Virtual(nv)
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
          min_distance,
          per_vreg_clone_cap,
        )
      }
      new_block.insts.push(inst)
    }
    match block.terminator {
      Some(term) => {
        let term_idx = block.insts.length()
        let new_term = match term {
          @instr.Jump(target, args) => {
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
                  min_distance,
                  per_vreg_clone_cap,
                ),
              )
            }
            @instr.Jump(target, new_args)
          }
          @instr.Branch(cond, t, e) =>
            @instr.Branch(
              maybe_remat_use(
                func,
                cond,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                min_distance,
                per_vreg_clone_cap,
              ),
              t,
              e,
            )
          @instr.BranchCmp(lhs, rhs, cond, is64, t, e) =>
            @instr.BranchCmp(
              maybe_remat_use(
                func,
                lhs,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                min_distance,
                per_vreg_clone_cap,
              ),
              maybe_remat_use(
                func,
                rhs,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                min_distance,
                per_vreg_clone_cap,
              ),
              cond,
              is64,
              t,
              e,
            )
          @instr.BranchCmpImm(lhs, imm, cond, is64, t, e) =>
            @instr.BranchCmpImm(
              maybe_remat_use(
                func,
                lhs,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                min_distance,
                per_vreg_clone_cap,
              ),
              imm,
              cond,
              is64,
              t,
              e,
            )
          @instr.BranchZero(reg, is_nonzero, is64, t, e) =>
            @instr.BranchZero(
              maybe_remat_use(
                func,
                reg,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                min_distance,
                per_vreg_clone_cap,
              ),
              is_nonzero,
              is64,
              t,
              e,
            )
          @instr.BrTable(index, targets, default) =>
            @instr.BrTable(
              maybe_remat_use(
                func,
                index,
                block.id,
                term_idx,
                remat_defs,
                clone_count,
                new_block,
                min_distance,
                per_vreg_clone_cap,
              ),
              targets,
              default,
            )
          @instr.Return(vals) => {
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
                  min_distance,
                  per_vreg_clone_cap,
                ),
              )
            }
            @instr.Return(new_vals)
          }
          @instr.Trap(msg) => @instr.Trap(msg)
        }
        new_block.set_terminator(new_term)
      }
      None => ()
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

  // block_id -> set of remat-vreg IDs that are used in this block but defined elsewhere.
  let block_needs : Map[Int, Set[Int]] = {}

  // 1) Collect rematerializable defs.
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      if is_remat_candidate(inst.opcode) &&
        inst.defs.length() == 1 &&
        inst.def_constraints.length() == 1 &&
        inst.def_constraints[0] is @abi.Any &&
        inst.defs[0].reg is @abi.Virtual(vreg) {
        if remat_defs.get(vreg.id) is None {
          remat_defs.set(vreg.id, {
            opcode: inst.opcode,
            def_block_id: block.id,
            def_inst_idx: inst_idx,
            cls: vreg.class,
            uses: inst.uses.copy(),
            use_constraints: inst.use_constraints.copy(),
          })
        }
      }
    }
  }

  // 2) Compute per-block remat needs by scanning uses.
  fn scan_use_reg(
    remat_defs : Map[Int, RematDef],
    block_needs : Map[Int, Set[Int]],
    block_id : Int,
    reg : @abi.Reg,
  ) -> Unit {
    if reg is @abi.Virtual(v) {
      match remat_defs.get(v.id) {
        Some(def) =>
          if def.def_block_id != block_id {
            record_block_need(block_needs, block_id, v.id)
          }
        None => ()
      }
    }
  }

  for block in func.blocks {
    for inst in block.insts {
      for u in inst.uses {
        scan_use_reg(remat_defs, block_needs, block.id, u)
      }
    }
    match block.terminator {
      Some(term) =>
        match term {
          @instr.Jump(_target, args) =>
            for a in args {
              scan_use_reg(remat_defs, block_needs, block.id, a)
            }
          @instr.Branch(cond, _t, _e) =>
            scan_use_reg(remat_defs, block_needs, block.id, cond)
          @instr.BranchCmp(lhs, rhs, _cond, _is64, _t, _e) => {
            scan_use_reg(remat_defs, block_needs, block.id, lhs)
            scan_use_reg(remat_defs, block_needs, block.id, rhs)
          }
          @instr.BranchZero(reg, _is_nonzero, _is64, _t, _e) =>
            scan_use_reg(remat_defs, block_needs, block.id, reg)
          @instr.BranchCmpImm(lhs, _imm, _cond, _is64, _t, _e) =>
            scan_use_reg(remat_defs, block_needs, block.id, lhs)
          @instr.Return(vals) =>
            for r in vals {
              scan_use_reg(remat_defs, block_needs, block.id, r)
            }
          @instr.BrTable(index, _targets, _default) =>
            scan_use_reg(remat_defs, block_needs, block.id, index)
          @instr.Trap(_) => ()
        }
      None => ()
    }
  }
  if block_needs.is_empty() {
    return func
  }

  // 3) Rebuild blocks with inserted const-loads and rewritten uses.
  for i in 0..<func.blocks.length() {
    let block = func.blocks[i]
    let needs = match block_needs.get(block.id) {
      Some(s) => s
      None => continue
    }

    // Per-block mapping: original vreg id -> new local vreg.
    let local_map : Map[Int, @abi.VReg] = {}
    let need_ids : Array[Int] = []
    for vreg_id in needs {
      need_ids.push(vreg_id)
    }
    need_ids.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
    for vreg_id in need_ids {
      let def = remat_defs.get(vreg_id).unwrap()
      let nv = func.new_vreg(def.cls)
      local_map.set(vreg_id, nv)
    }
    let new_block = @block.VCodeBlock::new(block.id)
    for p in block.params {
      new_block.params.push(p)
    }

    // Insert remat defs at block start.
    for vreg_id in need_ids {
      let def = remat_defs.get(vreg_id).unwrap()
      let nv = local_map.get(vreg_id).unwrap()
      let inst = clone_remat_inst(def, nv)
      new_block.insts.push(inst)
    }

    // Rewrite instruction uses and append.
    for inst in block.insts {
      for j, u in inst.uses {
        inst.uses[j] = rewrite_use_reg(u, local_map)
      }
      new_block.insts.push(inst)
    }

    // Rewrite terminator.
    match block.terminator {
      Some(term) => {
        let new_term = match term {
          @instr.Jump(target, args) => {
            let new_args : Array[@abi.Reg] = []
            for a in args {
              new_args.push(rewrite_use_reg(a, local_map))
            }
            @instr.Jump(target, new_args)
          }
          @instr.Branch(cond, t, e) =>
            @instr.Branch(rewrite_use_reg(cond, local_map), t, e)
          @instr.BranchCmp(lhs, rhs, cond, is64, t, e) =>
            @instr.BranchCmp(
              rewrite_use_reg(lhs, local_map),
              rewrite_use_reg(rhs, local_map),
              cond,
              is64,
              t,
              e,
            )
          @instr.BranchZero(reg, is_nonzero, is64, t, e) =>
            @instr.BranchZero(
              rewrite_use_reg(reg, local_map),
              is_nonzero,
              is64,
              t,
              e,
            )
          @instr.BranchCmpImm(lhs, imm, cond, is64, t, e) =>
            @instr.BranchCmpImm(
              rewrite_use_reg(lhs, local_map),
              imm,
              cond,
              is64,
              t,
              e,
            )
          @instr.Return(vals) => {
            let new_vals : Array[@abi.Reg] = []
            for r in vals {
              new_vals.push(rewrite_use_reg(r, local_map))
            }
            @instr.Return(new_vals)
          }
          @instr.BrTable(index, targets, default) =>
            @instr.BrTable(rewrite_use_reg(index, local_map), targets, default)
          @instr.Trap(msg) => @instr.Trap(msg)
        }
        new_block.set_terminator(new_term)
      }
      None => ()
    }
    func.blocks[i] = new_block
  }
  func
}
