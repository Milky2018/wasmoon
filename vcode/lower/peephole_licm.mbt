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
        let vmctx_idx = @isa.ISA::current().vmctx_reg_index()
        fn is_vmctx_reg(r : @abi.Reg) -> Bool {
          r is Physical(p) && p.index == vmctx_idx
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
  let vmctx_idx = @isa.ISA::current().vmctx_reg_index()
  // Collect all vregs that are func_table pointers.
  let func_table_ptrs : @hashset.HashSet[Int] = @hashset.new()
  for blk in func.blocks {
    for inst in blk.insts {
      match inst.opcode {
        Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET)
        | LoadPtr(I64, @abi.VMCTX_FUNC_TABLE_OFFSET) =>
          if inst.defs.length() == 1 && inst.uses.length() == 1 {
            if inst.uses[0] is Physical(p) && p.index == vmctx_idx {
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
    r is Physical(p) && p.index == vmctx_idx
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
        CallPtr(_, _, _)
        | CallDirect(_, _, _, _)
        | ReturnCallIndirect(_, _)
        | TypeCheckSubtypeIndirect(_) => {
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
