///|
/// Loop-invariant code motion for simple invariants.
///
/// Detect natural loops via backedges (h dominates b for edge b->h). If the
/// loop header has a unique predecessor outside the loop, treat it as a
/// preheader and hoist:
/// - `LoadConst` (with heuristics to avoid reg pressure)
/// - a small set of loop-invariant `Load`/`LoadPtr` from immutable vmctx-derived data
fn licm_hoist_invariants(
  func : @machv.Function,
  runtime_layout : @abi.RuntimeContextLayout,
  isa : @isa.ISA,
) -> Unit {
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
        let loop_nodes : @hashset.HashSet[Int] = HashSet([])
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
        let used_outside : @hashset.HashSet[Int] = HashSet([])
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
            let used : @hashset.HashSet[Int] = HashSet([])
            collect_terminator_uses_simple(term, used)
            for uid in used {
              let c = use_count_in_loop.get(uid).unwrap_or(0)
              use_count_in_loop.set(uid, c + 1)
            }
          }
        }

        // Build set of vregs defined inside the loop.
        let defs_in_loop : @hashset.HashSet[Int] = HashSet([])
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
        let vmctx_idx = isa.vmctx_reg_index()
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
              match inst.opcode {
                Load(I64, off) =>
                  off == runtime_layout.function_table_offset &&
                  inst.uses.length() == 1 &&
                  is_vmctx_reg(inst.uses[0])
                _ => false
              }
            None => false
          }
        }

        // Checks whether a load is safe to hoist.
        fn is_hoistable_load(op : @instr.VCodeOpcode, base : @abi.Reg) -> Bool {
          match op {
            Load(I64, off) | LoadPtr(I64, off) =>
              if is_vmctx_reg(base) {
                // Only allow runtime function-table load at the moment.
                off == runtime_layout.function_table_offset
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
        let hoisted_defs : @hashset.HashSet[Int] = HashSet([])
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
            if inst.opcode is LoadConst(value) &&
              inst.defs.length() == 1 &&
              get_def_vreg_id(inst.defs[0]) is Some(def_id) {
              let use_cnt = use_count_in_loop.get(def_id).unwrap_or(0)
              if !used_outside.contains(def_id) &&
                (is_expensive_const(value) || use_cnt >= 3) {
                hoisted.push(inst)
                hoisted_defs.add(def_id)
                continue
              }
            }

            // 2) Hoistable loads from immutable regions
            if inst.defs.length() == 1 &&
              inst.uses.length() == 1 &&
              get_def_vreg_id(inst.defs[0]) is Some(def_id) &&
              !used_outside.contains(def_id) &&
              base_is_invariant(inst.uses[0]) &&
              is_hoistable_load(inst.opcode, inst.uses[0]) {
              hoisted.push(inst)
              hoisted_defs.add(def_id)
              continue
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
fn cse_immutable_loads(
  func : @machv.Function,
  runtime_layout : @abi.RuntimeContextLayout,
  isa : @isa.ISA,
) -> Unit {
  let vmctx_idx = isa.vmctx_reg_index()
  // Wasm ABI: param 0 is vmctx. Treat it as vmctx alias so repeated
  // vmctx-derived base loads can be CSE'd even before prelude rewrites.
  let vmctx_aliases : @hashset.HashSet[Int] = HashSet([])
  let params = func.get_params()
  if params.length() > 0 {
    vmctx_aliases.add(params[0].id)
  }
  // Collect all vregs that are func_table pointers.
  let func_table_ptrs : @hashset.HashSet[Int] = HashSet([])
  fn is_function_table_context_load(op : @instr.VCodeOpcode) -> Bool {
    match op {
      Load(I64, off) | LoadPtr(I64, off) =>
        off == runtime_layout.function_table_offset
      _ => false
    }
  }
  fn is_context_base_load(op : @instr.VCodeOpcode) -> Bool {
    match op {
      Load(I64, off) | LoadPtr(I64, off) =>
        off == runtime_layout.function_table_offset ||
        off == runtime_layout.global_storage_offset
      _ => false
    }
  }
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
        inst.uses.length() == 1 &&
        get_def_vreg_id(inst.defs[0]) is Some(dst) &&
        get_vreg_id(inst.uses[0]) is Some(src) {
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
      if is_function_table_context_load(inst.opcode) &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 &&
        is_vmctx_alias(inst.uses[0], copies, vmctx_aliases) &&
        get_def_vreg_id(inst.defs[0]) is Some(did) {
        func_table_ptrs.add(did)
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
        inst.uses.length() == 1 &&
        get_def_vreg_id(inst.defs[0]) is Some(dst) &&
        get_vreg_id(inst.uses[0]) is Some(src) {
        copies.set(dst, canonical_id(src, copies))
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
      // - function table: `load.i64 +function_table_offset context`
      // - global storage: `load.i64 +global_storage_offset context`
      if !replaced &&
        is_context_base_load(inst.opcode) &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 &&
        is_vmctx(inst.uses[0]) {
        let key = match inst.opcode {
          Load(_, off) | LoadPtr(_, off) => "vmctx_base|" + off.to_string()
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
/// Check if an immediate fits AArch64 add/sub encoding (12-bit or 12-bit<<12).
///
/// Kept local to avoid package cycles with `vcode/lower`.
fn is_valid_add_imm(val : Int64) -> Bool {
  if val >= 0L && val <= 4095L {
    return true
  }
  if val >= 0L && (val & 0xFFFL) == 0L && val >> 12 <= 4095L {
    return true
  }
  false
}

///|
/// Convert a compare kind to a branch condition.
fn cmp_kind_to_cond(kind : @instr.CmpKind) -> @instr.Cond {
  match kind {
    Eq => Eq
    Ne => Ne
    Slt => Lt
    Sle => Le
    Sgt => Gt
    Sge => Ge
    Ult => Lo
    Ule => Ls
    Ugt => Hi
    Uge => Hs
  }
}

///|
fn invert_cond(cond : @instr.Cond) -> @instr.Cond {
  match cond {
    Eq => Ne
    Ne => Eq
    Hs => Lo
    Lo => Hs
    Mi => Pl
    Pl => Mi
    Vs => Vc
    Vc => Vs
    Ps => Pc
    Pc => Ps
    Hi => Ls
    Ls => Hi
    Ge => Lt
    Lt => Ge
    Gt => Le
    Le => Gt
    Al => Al
  }
}

///|
fn eval_cmp_imm_cond(lhs : Int, rhs : Int, cond : @instr.Cond) -> Bool {
  match cond {
    Eq => lhs == rhs
    Ne => lhs != rhs
    Hs | Ge => lhs >= rhs
    Lo | Lt => lhs < rhs
    Hi | Gt => lhs > rhs
    Ls | Le => lhs <= rhs
    Al => true
    _ => false
  }
}

///|
fn classify_cmp_result_branching(imm : Int, cond : @instr.Cond) -> Bool? {
  let when_cmp_true = eval_cmp_imm_cond(1, imm, cond)
  let when_cmp_false = eval_cmp_imm_cond(0, imm, cond)
  if when_cmp_true && !when_cmp_false {
    return Some(true)
  }
  if !when_cmp_true && when_cmp_false {
    return Some(false)
  }
  None
}

///|
fn build_cmp_branch_terminator(
  lhs : @abi.Reg,
  rhs : @abi.Reg,
  cmp_kind : @instr.CmpKind,
  cmp_is_64 : Bool,
  branch_when_cmp_true : Bool,
  then_id : Int,
  else_id : Int,
  const_defs : Map[Int, Int64],
) -> @instr.VCodeTerminator {
  let mut cond = cmp_kind_to_cond(cmp_kind)
  if !branch_when_cmp_true {
    cond = invert_cond(cond)
  }
  if rhs is Virtual(rhs_vreg) &&
    const_defs.get(rhs_vreg.id) is Some(val) &&
    is_valid_add_imm(val) {
    BranchCmpImm(lhs, val.to_int(), cond, cmp_is_64, then_id, else_id)
  } else {
    BranchCmp(lhs, rhs, cond, cmp_is_64, then_id, else_id)
  }
}

///|
/// Check whether an opcode is trivially dead when its defs are unused.
fn is_trivially_dead_opcode(op : @instr.VCodeOpcode) -> Bool {
  match op {
    // Pure integer/extend ops: safe to drop when defs are unused.
    Add(_)
    | AddImm(_, _)
    | Sub(_)
    | SubImm(_, _)
    | Extend(_)
    // Existing trivially-dead constant/move forms.
    | Move
    | LoadConst(_)
    | LoadConstF32(_)
    | LoadConstF64(_)
    | LoadConstV128(_)
    | LoadCodeAddr(_)
    | Nop => true
    _ => false
  }
}

///|
/// Remove trivially-dead value defs (constants/moves) across the function.
fn dce_trivially_dead(func : @machv.Function) -> Unit {
  let mut changed = true
  while changed {
    changed = false
    let used : @hashset.HashSet[Int] = HashSet([])
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
  global_use_counts : Array[Int],
) -> Unit {
  let use_counts : Array[Int] = Array::make(global_use_counts.length(), 0)
  fn get_count(counts : Array[Int], id : Int) -> Int {
    if id >= 0 && id < counts.length() {
      counts[id]
    } else {
      0
    }
  }
  fn inc_count(counts : Array[Int], id : Int) -> Unit {
    if id < 0 || id >= counts.length() {
      return
    }
    counts[id] = counts[id] + 1
  }
  for inst in block.insts {
    for use_ in inst.uses {
      if get_vreg_id(use_) is Some(vid) {
        inc_count(use_counts, vid)
      }
    }
  }
  if block.terminator is Some(term) {
    let term_uses = match term {
      Jump(_, args) | Return(args) => args
      Branch(cond, _, _) | BranchZero(cond, _, _, _, _) | BrTable(cond, _, _) =>
        [cond]
      BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
      BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
      Trap(_) => []
    }
    for use_ in term_uses {
      if get_vreg_id(use_) is Some(vid) {
        inc_count(use_counts, vid)
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
  let to_remove : @hashset.HashSet[Int] = HashSet([])
  for i, inst in block.insts {
    if inst.opcode is Move &&
      inst.defs.length() == 1 &&
      inst.uses.length() == 1 &&
      inst.defs[0].reg is Virtual(dst_vreg) &&
      inst.uses[0] is Virtual(src_vreg) &&
      same_reg_class(dst_vreg.class, src_vreg.class) &&
      get_count(use_counts, dst_vreg.id) == 1 &&
      get_count(global_use_counts, dst_vreg.id) ==
      get_count(use_counts, dst_vreg.id) {
      let resolved = resolve_copy(src_vreg, copies)
      copies.set(dst_vreg.id, resolved)
      to_remove.add(i)
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
      Jump(target, args) => {
        let new_args : Array[@abi.Reg] = []
        for arg in args {
          new_args.push(rewrite_reg(arg))
        }
        @instr.VCodeTerminator::Jump(target, new_args)
      }
      Branch(cond, then_id, else_id) =>
        Branch(rewrite_reg(cond), then_id, else_id)
      BranchCmp(lhs, rhs, cond, is_64, then_id, else_id) =>
        BranchCmp(
          rewrite_reg(lhs),
          rewrite_reg(rhs),
          cond,
          is_64,
          then_id,
          else_id,
        )
      BranchZero(cond, is_nonzero, is_64, then_id, else_id) =>
        BranchZero(rewrite_reg(cond), is_nonzero, is_64, then_id, else_id)
      BranchCmpImm(lhs, imm, cond, is_64, then_id, else_id) =>
        BranchCmpImm(rewrite_reg(lhs), imm, cond, is_64, then_id, else_id)
      Return(args) => {
        let new_args : Array[@abi.Reg] = []
        for arg in args {
          new_args.push(rewrite_reg(arg))
        }
        Return(new_args)
      }
      BrTable(index, targets, default_id) =>
        BrTable(rewrite_reg(index), targets, default_id)
      Trap(msg) => Trap(msg)
    }
    block.set_terminator(new_term)
  }
}

///|
/// Propagate virtual moves across the whole function and remove redundant copies.
fn propagate_moves_global(func : @machv.Function) -> Unit {
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
        inst.uses.length() == 1 &&
        inst.defs[0].reg is Virtual(dst_vreg) &&
        inst.uses[0] is Virtual(src_vreg) &&
        same_reg_class(dst_vreg.class, src_vreg.class) &&
        def_pos.get(src_vreg.id) is Some((src_block, src_inst)) &&
        dom[block.id].contains(src_block) &&
        (src_block != block.id || src_inst < inst_idx) {
        copies.set(dst_vreg.id, src_vreg)
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
    let visited : @hashset.HashSet[Int] = HashSet([])
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
        Jump(target, args) => {
          let new_args : Array[@abi.Reg] = []
          for arg in args {
            new_args.push(rewrite_reg(arg, block.id, use_idx))
          }
          @instr.VCodeTerminator::Jump(target, new_args)
        }
        Branch(cond, then_id, else_id) =>
          Branch(rewrite_reg(cond, block.id, use_idx), then_id, else_id)
        BranchCmp(lhs, rhs, cond, is_64, then_id, else_id) =>
          BranchCmp(
            rewrite_reg(lhs, block.id, use_idx),
            rewrite_reg(rhs, block.id, use_idx),
            cond,
            is_64,
            then_id,
            else_id,
          )
        BranchZero(cond, is_nonzero, is_64, then_id, else_id) =>
          BranchZero(
            rewrite_reg(cond, block.id, use_idx),
            is_nonzero,
            is_64,
            then_id,
            else_id,
          )
        BranchCmpImm(lhs, imm, cond, is_64, then_id, else_id) =>
          BranchCmpImm(
            rewrite_reg(lhs, block.id, use_idx),
            imm,
            cond,
            is_64,
            then_id,
            else_id,
          )
        Return(args) => {
          let new_args : Array[@abi.Reg] = []
          for arg in args {
            new_args.push(rewrite_reg(arg, block.id, use_idx))
          }
          Return(new_args)
        }
        BrTable(index, targets, default_id) =>
          BrTable(rewrite_reg(index, block.id, use_idx), targets, default_id)
        Trap(msg) => Trap(msg)
      }
      block.set_terminator(new_term)
    }
  }
}

///|
/// Fuse `cmp` + `branch` into `br_cmp`/`br_cmp_imm` when the cmp result
/// is only used by the branch terminator.
fn fuse_cmp_branch(func : @machv.Function) -> Unit {
  let const_defs : Map[Int, Int64] = {}
  for blk in func.blocks {
    for inst in blk.insts {
      if inst.opcode is LoadConst(val) &&
        inst.defs.length() == 1 &&
        get_def_vreg_id(inst.defs[0]) is Some(did) {
        const_defs.set(did, val)
      }
    }
  }
  for blk in func.blocks {
    let mut cond_vreg_opt : @abi.VReg? = None
    let mut then_id = -1
    let mut else_id = -1
    let mut branch_when_cmp_true = true
    match blk.terminator {
      Some(Branch(cond, then_b, else_b)) =>
        if cond is Virtual(cond_vreg) {
          cond_vreg_opt = Some(cond_vreg)
          then_id = then_b
          else_id = else_b
          branch_when_cmp_true = true
        }
      Some(BranchZero(cond, is_nonzero, _is_64, then_b, else_b)) =>
        if cond is Virtual(cond_vreg) {
          cond_vreg_opt = Some(cond_vreg)
          then_id = then_b
          else_id = else_b
          branch_when_cmp_true = is_nonzero
        }
      Some(BranchCmpImm(lhs, imm, cond, _is_64, then_b, else_b)) =>
        if lhs is Virtual(cond_vreg) &&
          classify_cmp_result_branching(imm, cond) is Some(should_branch) {
          cond_vreg_opt = Some(cond_vreg)
          then_id = then_b
          else_id = else_b
          branch_when_cmp_true = should_branch
        }
      _ => ()
    }
    if cond_vreg_opt is Some(cond_vreg) && blk.insts.length() > 0 {
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
          let new_term = build_cmp_branch_terminator(
            lhs, rhs, kind, is_64, branch_when_cmp_true, then_id, else_id, const_defs,
          )
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
  func : @machv.Function,
) -> Map[Int, JumpForwardInfo] {
  let forwarding : Map[Int, JumpForwardInfo] = {}
  for block in func.blocks {
    guard block.insts.length() == 0 else { continue }
    guard block.terminator is Some(Jump(target, args)) else { continue }
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
fn thread_trivial_jump_blocks(func : @machv.Function) -> Int {
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
    let visited : @hashset.HashSet[Int] = HashSet([])
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
    let visited : @hashset.HashSet[Int] = HashSet([])
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
      Some(Jump(target, args)) => {
        let resolved = resolve_jump(target, args, forwarding)
        if resolved.changed {
          block.set_terminator(Jump(resolved.target, resolved.args))
          rewrites = rewrites + 1
        }
      }
      Some(Branch(cond, then_b, else_b)) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(Branch(cond, new_then, new_else))
          rewrites = rewrites + 1
        }
      }
      Some(BranchCmp(lhs, rhs, cond, is_64, then_b, else_b)) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            BranchCmp(lhs, rhs, cond, is_64, new_then, new_else),
          )
          rewrites = rewrites + 1
        }
      }
      Some(BranchZero(reg, is_nonzero, is_64, then_b, else_b)) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            BranchZero(reg, is_nonzero, is_64, new_then, new_else),
          )
          rewrites = rewrites + 1
        }
      }
      Some(BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b)) => {
        let new_then = resolve_target_no_args(then_b, forwarding)
        let new_else = resolve_target_no_args(else_b, forwarding)
        if new_then != then_b || new_else != else_b {
          block.set_terminator(
            BranchCmpImm(lhs, imm, cond, is_64, new_then, new_else),
          )
          rewrites = rewrites + 1
        }
      }
      Some(BrTable(index, targets, default_id)) => {
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
          block.set_terminator(BrTable(index, new_targets, new_default))
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
pub(all) enum PeepholeProfile {
  Full
  Lowering
}

///|
pub fn optimize_vcode(
  func : @machv.Function,
  isa? : @isa.ISA = AArch64,
  profile? : PeepholeProfile = Full,
  runtime_layout? : @abi.RuntimeContextLayout? = None,
) -> Unit {
  let mut inst_count = 0
  for block in func.blocks {
    inst_count = inst_count + block.insts.length()
  }
  // Cranelift-aligned compile-time guardrail:
  // avoid expensive ad-hoc peephole sweeps on very large functions.
  // Large kernels already get most wins from IR/VCode canonicalization and
  // regalloc; extra local sweeps tend to add substantial compile latency.
  let large_func_threshold = 1200
  let is_large_func = inst_count >= large_func_threshold

  let enable_full_passes = profile is Full
  let enable_licm = enable_full_passes &&
    !is_large_func &&
    runtime_layout is Some(_)
  let enable_immutable_load_cse = enable_full_passes &&
    !is_large_func &&
    runtime_layout is Some(_)
  let enable_mem_peepholes = enable_full_passes && !is_large_func
  let enable_inplace_updates = enable_full_passes && !is_large_func
  let enable_copy_prop = true

  // Pass 0: loop-invariant code motion
  if enable_licm {
    licm_hoist_invariants(func, runtime_layout.unwrap(), isa)
  }
  // Pass 0.5: block-local CSE for immutable loads
  if enable_immutable_load_cse {
    cse_immutable_loads(func, runtime_layout.unwrap(), isa)
  }
  // Pass 1: Basic peephole optimizations (constant folding, move elimination)
  for block in func.blocks {
    let state = PeepholeState::new()
    optimize_block(block, func, state, isa) |> ignore
  }
  // Pass 1.5: Copy propagation for single-use moves
  if enable_copy_prop {
    let global_use_counts = collect_use_counts(func)
    for block in func.blocks {
      propagate_single_use_moves(block, global_use_counts)
    }
  }
  // Pass 1.6: Global copy propagation for virtual moves.
  // Keep this disabled for now: global propagation tends to increase
  // live-range pressure in large branch-heavy kernels.
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
  if enable_inplace_updates {
    for block in func.blocks {
      optimize_inplace_updates(block) |> ignore
    }
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
