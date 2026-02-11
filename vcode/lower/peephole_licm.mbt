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
/// - only track immutable vmctx-derived base pointers (`func_table`, `globals`)
/// - only CSE `Load(I64, off)` / `LoadPtr(I64, off)` from that func_table pointer
fn cse_immutable_loads(func : @regalloc.VCodeFunction) -> Unit {
  let vmctx_idx = @isa.ISA::current().vmctx_reg_index()
  // Wasm ABI: param 0 is vmctx. Treat it as vmctx alias so repeated
  // vmctx-derived base loads can be CSE'd even before prelude rewrites.
  let vmctx_aliases : @hashset.HashSet[Int] = @hashset.new()
  let params = func.get_params()
  if params.length() > 0 {
    vmctx_aliases.add(params[0].id)
  }
  // Collect all vregs that are func_table pointers.
  let func_table_ptrs : @hashset.HashSet[Int] = @hashset.new()
  fn is_vmctx_alias(
    reg : @abi.Reg,
    copies : Map[Int, Int],
    aliases : @hashset.HashSet[Int],
  ) -> Bool {
    match reg {
      Physical(p) => p.index == vmctx_idx
      Virtual(v) => {
        let mut cur = v.id
        while copies.get(cur) is Some(next) {
          if next == cur {
            break
          }
          cur = next
        }
        aliases.contains(cur)
      }
    }
  }

  for blk in func.blocks {
    let copies : Map[Int, Int] = {}
    for inst in blk.insts {
      if inst.opcode is Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        if get_def_vreg_id(inst.defs[0]) is Some(dst) {
          if get_vreg_id(inst.uses[0]) is Some(src) {
            let mut src_root = src
            while copies.get(src_root) is Some(next) {
              if next == src_root {
                break
              }
              src_root = next
            }
            copies.set(dst, src_root)
            if vmctx_aliases.contains(src_root) {
              vmctx_aliases.add(dst)
            }
          }
        }
      }
      match inst.opcode {
        Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET)
        | LoadPtr(I64, @abi.VMCTX_FUNC_TABLE_OFFSET) =>
          if inst.defs.length() == 1 && inst.uses.length() == 1 {
            if is_vmctx_alias(inst.uses[0], copies, vmctx_aliases) {
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
    match r {
      Physical(p) => p.index == vmctx_idx
      Virtual(v) => vmctx_aliases.contains(v.id)
    }
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

      // Also CSE duplicate vmctx-derived immutable base loads:
      // - func_table: `load.i64 +8 x19`
      // - globals ptr: `load.i64 +32 x19`
      if !replaced {
        match inst.opcode {
          Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET)
          | Load(I64, @abi.VMCTX_GLOBALS_OFFSET)
          | LoadPtr(I64, @abi.VMCTX_FUNC_TABLE_OFFSET)
          | LoadPtr(I64, @abi.VMCTX_GLOBALS_OFFSET) =>
            if inst.defs.length() == 1 &&
              inst.uses.length() == 1 &&
              is_vmctx(inst.uses[0]) {
              let key = match inst.opcode {
                Load(_, off) | LoadPtr(_, off) =>
                  "vmctx_base|" + off.to_string()
                _ => "vmctx_base"
              }
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
  let dom = compute_dominators(func)
  let def_pos : Map[Int, (Int, Int)] = {}
  for block in func.blocks {
    for param in block.params {
      if !def_pos.contains(param.id) {
        def_pos.set(param.id, (block.id, -1))
      }
    }
    for inst_idx, inst in block.insts {
      for def in inst.defs {
        if def.reg is Virtual(vreg) && !def_pos.contains(vreg.id) {
          def_pos.set(vreg.id, (block.id, inst_idx))
        }
      }
    }
  }
  let copies : Map[Int, @abi.VReg] = {}
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      if inst.opcode is Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        if inst.defs[0].reg is Virtual(dst_vreg) &&
          inst.uses[0] is Virtual(src_vreg) {
          if same_reg_class(dst_vreg.class, src_vreg.class) &&
            def_pos.get(src_vreg.id) is Some((src_block, src_inst)) &&
            dom[block.id].contains(src_block) &&
            (src_block != block.id || src_inst < inst_idx) {
            copies.set(dst_vreg.id, src_vreg)
          }
        }
      }
    }
  }
  if copies.is_empty() {
    return
  }
  fn resolve_copy(
    reg : @abi.VReg,
    copies : Map[Int, @abi.VReg],
    def_pos : Map[Int, (Int, Int)],
    dom : Array[@hashset.HashSet[Int]],
    use_block_id : Int,
    use_inst_idx : Int,
  ) -> @abi.VReg {
    let mut cur = reg
    let visited : @hashset.HashSet[Int] = @hashset.new()
    while copies.get(cur.id) is Some(next) {
      if next.id == cur.id || visited.contains(cur.id) {
        break
      }
      visited.add(cur.id)
      if def_pos.get(next.id) is Some((src_block, src_inst)) &&
        dom[use_block_id].contains(src_block) &&
        (src_block != use_block_id || src_inst < use_inst_idx) {
        cur = next
      } else {
        break
      }
    }
    cur
  }

  let rewrite_reg = fn(
    reg : @abi.Reg,
    use_block_id : Int,
    use_inst_idx : Int,
  ) -> @abi.Reg {
    match reg {
      Virtual(v) =>
        if copies.get(v.id) is Some(target) {
          Virtual(
            resolve_copy(
              target, copies, def_pos, dom, use_block_id, use_inst_idx,
            ),
          )
        } else {
          reg
        }
      _ => reg
    }
  }
  for block in func.blocks {
    for inst_idx, inst in block.insts {
      for u in 0..<inst.uses.length() {
        inst.uses[u] = rewrite_reg(inst.uses[u], block.id, inst_idx)
      }
    }
    if block.terminator is Some(term) {
      let use_idx = block.insts.length()
      let new_term = match term {
        @instr.VCodeTerminator::Jump(target, args) => {
          let new_args : Array[@abi.Reg] = []
          for arg in args {
            new_args.push(rewrite_reg(arg, block.id, use_idx))
          }
          @instr.VCodeTerminator::Jump(target, new_args)
        }
        @instr.VCodeTerminator::Branch(cond, then_id, else_id) =>
          @instr.VCodeTerminator::Branch(
            rewrite_reg(cond, block.id, use_idx),
            then_id,
            else_id,
          )
        @instr.VCodeTerminator::BranchCmp(
          lhs,
          rhs,
          cond,
          is_64,
          then_id,
          else_id
        ) =>
          @instr.VCodeTerminator::BranchCmp(
            rewrite_reg(lhs, block.id, use_idx),
            rewrite_reg(rhs, block.id, use_idx),
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
            rewrite_reg(cond, block.id, use_idx),
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
            rewrite_reg(lhs, block.id, use_idx),
            imm,
            cond,
            is_64,
            then_id,
            else_id,
          )
        @instr.VCodeTerminator::Return(args) => {
          let new_args : Array[@abi.Reg] = []
          for arg in args {
            new_args.push(rewrite_reg(arg, block.id, use_idx))
          }
          @instr.VCodeTerminator::Return(new_args)
        }
        @instr.VCodeTerminator::BrTable(index, targets, default_id) =>
          @instr.VCodeTerminator::BrTable(
            rewrite_reg(index, block.id, use_idx),
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
/// Treat call-like instructions as barriers for mem-base value availability.
fn is_mem_base_cse_barrier(opcode : @instr.VCodeOpcode) -> Bool {
  // Cranelift keeps heap-base values live across direct Wasm calls in hot
  // paths. Keep barriers for C/indirect calls (and subtype checks) where the
  // callee/slow path may mutate runtime-managed memory state.
  match opcode {
    @instr.CallDirect(_, _, _, @instr.Wasm) => false
    @instr.CallDirect(_, _, _, @instr.C) => true
    @instr.CallPtr(_, _, @instr.C) => true
    @instr.CallPtr(_, _, @instr.Wasm) => true
    @instr.ReturnCallIndirect(_, _) => true
    @instr.TypeCheckSubtypeIndirect(_) => true
    _ => false
  }
}

///|
/// Clone mem-base environment map.
fn clone_mem_base_env(src : Map[Int, Int]) -> Map[Int, Int] {
  let dst : Map[Int, Int] = {}
  for mem_idx, vreg_id in src {
    dst.set(mem_idx, vreg_id)
  }
  dst
}

///|
/// Compare two mem-base environments for exact equality.
fn same_mem_base_env(lhs : Map[Int, Int], rhs : Map[Int, Int]) -> Bool {
  for mem_idx, vreg_id in lhs {
    if rhs.get(mem_idx) is Some(other) {
      if other != vreg_id {
        return false
      }
    } else {
      return false
    }
  }
  for mem_idx, _ in rhs {
    if lhs.get(mem_idx) is None {
      return false
    }
  }
  true
}

///|
/// Intersect predecessor out-envs, keeping only `(mem_idx -> vreg)` pairs
/// available with the exact same vreg in all predecessors.
fn merge_mem_base_preds(
  preds : Array[Int],
  out_env : Array[Map[Int, Int]],
) -> Map[Int, Int] {
  if preds.length() == 0 {
    return {}
  }
  let merged = clone_mem_base_env(out_env[preds[0]])
  for i in 1..<preds.length() {
    let pred_env = out_env[preds[i]]
    let to_remove : Array[Int] = []
    for mem_idx, vreg_id in merged {
      match pred_env.get(mem_idx) {
        Some(other) if other == vreg_id => ()
        _ => to_remove.push(mem_idx)
      }
    }
    for mem_idx in to_remove {
      merged.remove(mem_idx) |> ignore
    }
    if merged.length() == 0 {
      break
    }
  }
  merged
}

///|
/// Dominance-safe CSE for `LoadMemBase(mem=...)`.
///
/// Unlike the previous block-local pass, this computes a forward dataflow
/// environment and allows reuse across block boundaries when all predecessors
/// agree on the exact same available vreg.
fn cse_mem_base_loads(func : @regalloc.VCodeFunction) -> Unit {
  let n = func.blocks.length()
  if n == 0 {
    return
  }
  let block_id_to_index : Map[Int, Int] = {}
  for i, blk in func.blocks {
    block_id_to_index.set(blk.id, i)
  }
  let preds : Array[Array[Int]] = []
  for _ in 0..<n {
    preds.push([])
  }
  for pred_idx, blk in func.blocks {
    let succ_ids = get_successors(blk.terminator)
    for succ_id in succ_ids {
      if block_id_to_index.get(succ_id) is Some(succ_idx) {
        preds[succ_idx].push(pred_idx)
      }
    }
  }
  let in_env : Array[Map[Int, Int]] = []
  let out_env : Array[Map[Int, Int]] = []
  for _ in 0..<n {
    in_env.push({})
    out_env.push({})
  }

  // Fixed-point solve for available mem-base values.
  let mut changed = true
  while changed {
    changed = false
    for block_idx, blk in func.blocks {
      let incoming = if block_idx == 0 {
        {}
      } else {
        merge_mem_base_preds(preds[block_idx], out_env)
      }
      if !same_mem_base_env(in_env[block_idx], incoming) {
        in_env[block_idx] = incoming
        changed = true
      }
      let state = clone_mem_base_env(in_env[block_idx])
      for inst in blk.insts {
        if is_mem_base_cse_barrier(inst.opcode) {
          state.clear()
          continue
        }
        if inst.opcode is LoadMemBase(mem_idx) && inst.defs.length() == 1 {
          if get_def_vreg_id(inst.defs[0]) is Some(dst) {
            // Forward the available value through this block with the latest
            // local name to avoid creating very long vreg live ranges.
            state.set(mem_idx, dst)
          }
        }
      }
      if !same_mem_base_env(out_env[block_idx], state) {
        out_env[block_idx] = state
        changed = true
      }
    }
  }

  // Rewrite loads using stable in-env snapshots.
  for block_idx, blk in func.blocks {
    let state = clone_mem_base_env(in_env[block_idx])
    let new_insts : Array[@instr.VCodeInst] = []
    for inst in blk.insts {
      if is_mem_base_cse_barrier(inst.opcode) {
        state.clear()
        new_insts.push(inst)
        continue
      }
      match inst.opcode {
        LoadMemBase(mem_idx) =>
          if inst.defs.length() == 1 {
            if state.get(mem_idx) is Some(prev_id) {
              let mv = @instr.VCodeInst::new(Move)
              mv.add_def(inst.defs[0])
              mv.add_use(Virtual({ id: prev_id, class: Int }))
              new_insts.push(mv)
              if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                state.set(mem_idx, dst)
              }
            } else {
              new_insts.push(inst)
              if get_def_vreg_id(inst.defs[0]) is Some(dst) {
                state.set(mem_idx, dst)
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
priv struct JumpForwardInfo {
  target : Int
  arg_indices : Array[Int]
}

///|
priv struct ResolvedJump {
  target : Int
  args : Array[@abi.Reg]
  changed : Bool
}

///|
fn build_jump_forwarding_map(
  func : @regalloc.VCodeFunction,
) -> Map[Int, JumpForwardInfo] {
  let forwarding : Map[Int, JumpForwardInfo] = {}
  for block in func.blocks {
    guard block.insts.length() == 0 else { continue }
    guard block.terminator is Some(@instr.VCodeTerminator::Jump(target, args)) else {
      continue
    }
    guard target != block.id else { continue }
    guard args.length() == block.params.length() else { continue }
    let arg_indices : Array[Int] = []
    let mut ok = true
    for arg in args {
      match arg {
        Virtual(vreg) => {
          let mut found = -1
          for i, param in block.params {
            if param.id == vreg.id {
              found = i
              break
            }
          }
          if found < 0 {
            ok = false
            break
          }
          arg_indices.push(found)
        }
        Physical(_) => {
          ok = false
          break
        }
      }
    }
    if ok {
      forwarding.set(block.id, { target, arg_indices })
    }
  }
  forwarding
}

///|
fn thread_trivial_jump_blocks(func : @regalloc.VCodeFunction) -> Int {
  let forwarding = build_jump_forwarding_map(func)
  if forwarding.is_empty() {
    return 0
  }
  fn resolve_jump(
    target : Int,
    args : Array[@abi.Reg],
    forwarding : Map[Int, JumpForwardInfo],
  ) -> ResolvedJump {
    let mut cur_target = target
    let mut cur_args = args
    let mut changed = false
    let visited : @hashset.HashSet[Int] = @hashset.new()
    while true {
      if visited.contains(cur_target) {
        break
      }
      visited.add(cur_target)
      match forwarding.get(cur_target) {
        Some(info) => {
          if info.arg_indices.length() != cur_args.length() {
            break
          }
          let next_args : Array[@abi.Reg] = []
          let mut valid = true
          for idx in info.arg_indices {
            if idx < 0 || idx >= cur_args.length() {
              valid = false
              break
            }
            next_args.push(cur_args[idx])
          }
          if !valid {
            break
          }
          cur_target = info.target
          cur_args = next_args
          changed = true
        }
        None => break
      }
    }
    { target: cur_target, args: cur_args, changed }
  }

  fn resolve_target_no_args(
    target : Int,
    forwarding : Map[Int, JumpForwardInfo],
  ) -> Int {
    let mut cur_target = target
    let visited : @hashset.HashSet[Int] = @hashset.new()
    while true {
      if visited.contains(cur_target) {
        break
      }
      visited.add(cur_target)
      match forwarding.get(cur_target) {
        Some(info) =>
          if info.arg_indices.length() == 0 {
            cur_target = info.target
          } else {
            break
          }
        None => break
      }
    }
    cur_target
  }

  let mut rewrites = 0
  for block in func.blocks {
    match block.terminator {
      Some(@instr.VCodeTerminator::Jump(target, args)) => {
        let resolved = resolve_jump(target, args, forwarding)
        if resolved.changed {
          block.set_terminator(
            @instr.VCodeTerminator::Jump(resolved.target, resolved.args),
          )
          rewrites = rewrites + 1
        }
      }
      Some(@instr.VCodeTerminator::Branch(cond, then_b, else_b)) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            @instr.VCodeTerminator::Branch(cond, new_then, new_else),
          )
          rewrites = rewrites + 1
        }
      }
      Some(
        @instr.VCodeTerminator::BranchCmp(lhs, rhs, cond, is_64, then_b, else_b)
      ) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            @instr.VCodeTerminator::BranchCmp(
              lhs, rhs, cond, is_64, new_then, new_else,
            ),
          )
          rewrites = rewrites + 1
        }
      }
      Some(
        @instr.VCodeTerminator::BranchZero(
          reg,
          is_nonzero,
          is_64,
          then_b,
          else_b
        )
      ) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            @instr.VCodeTerminator::BranchZero(
              reg, is_nonzero, is_64, new_then, new_else,
            ),
          )
          rewrites = rewrites + 1
        }
      }
      Some(
        @instr.VCodeTerminator::BranchCmpImm(
          lhs,
          imm,
          cond,
          is_64,
          then_b,
          else_b
        )
      ) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            @instr.VCodeTerminator::BranchCmpImm(
              lhs, imm, cond, is_64, new_then, new_else,
            ),
          )
          rewrites = rewrites + 1
        }
      }
      Some(@instr.VCodeTerminator::BrTable(index, targets, default_id)) => {
        let new_targets : Array[Int] = []
        let mut changed = false
        for target in targets {
          let new_target = resolve_target_no_args(target, forwarding)
          if new_target != target {
            changed = true
          }
          new_targets.push(new_target)
        }
        let new_default = resolve_target_no_args(default_id, forwarding)
        if new_default != default_id {
          changed = true
        }
        if changed {
          block.set_terminator(
            @instr.VCodeTerminator::BrTable(index, new_targets, new_default),
          )
          rewrites = rewrites + 1
        }
      }
      _ => ()
    }
  }
  rewrites
}

///|
/// Run peephole optimization on an entire VCode function
/// This should be called after lower_function and before register allocation
pub fn optimize_vcode(func : @regalloc.VCodeFunction) -> Unit {
  let mut inst_count = 0
  for block in func.blocks {
    inst_count = inst_count + block.insts.length()
  }
  let enable_licm = true
  let enable_immutable_load_cse = true
  let enable_mem_base_cse = true
  // Bound expensive ad-hoc memory peepholes on very large functions.
  // Keep the correctness-preserving core passes enabled for all functions.
  let enable_mem_peepholes = inst_count <= 1200

  // Pass 0: loop-invariant code motion
  if enable_licm {
    licm_hoist_invariants(func)
  }
  // Pass 0.5: block-local CSE for immutable loads
  if enable_immutable_load_cse {
    cse_immutable_loads(func)
  }
  // Pass 0.6: block-local CSE for LoadMemBase
  if enable_mem_base_cse {
    cse_mem_base_loads(func)
  }

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
  // Pass 1.6: Global copy propagation for virtual moves.
  // Keep this disabled for now: even bounded versions still regress
  // branch-heavy WAST suites. Local propagation remains enabled.
  let enable_global_copy_prop = false
  if enable_global_copy_prop {
    propagate_moves_global(func)
  }
  // Pass 1.65: Fuse cmp+branch into compare branches
  fuse_cmp_branch(func)
  // Pass 1.66: Thread trivial jump blocks, including block-arg forwarding.
  // This reduces jump chains and improves block fallthrough opportunities.
  thread_trivial_jump_blocks(func) |> ignore
  // Pass 1.7: Drop trivially-dead value defs
  dce_trivially_dead(func)

  // Pass 2: In-place update optimization
  for block in func.blocks {
    optimize_inplace_updates(block) |> ignore
  }

  if enable_mem_peepholes {
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
}
