// IR Rematerialization Pass (Cranelift-style)
//
// This pass mirrors Cranelift's behavior in:
// - cranelift/codegen/src/opts/remat.isle (select remat candidates)
// - cranelift/codegen/src/egraph/elaborate.rs::maybe_remat_arg (clone def into each use-block)
//
// Goal: shrink cross-block live ranges for cheap + pure values (constants and
// ALU-with-imm) to reduce register pressure and spills in the JIT backend.

///|
/// Rematerialize cheap, pure SSA defs into each use block (once per block).
///
/// This pass is intentionally non-recursive (it does not attempt to remat the
/// operands of a rematted instruction), matching Cranelift's current behavior.
pub fn rematerialize_across_blocks(func : Function) -> OptResult {
  let result = OptResult::new()

  // value_id -> defining block id (for inst results and blockparams).
  let def_block : @hashmap.HashMap[Int, Int] = @hashmap.new()
  // value_id -> defining instruction (only for single-result instructions).
  let def_inst : @hashmap.HashMap[Int, Inst] = @hashmap.new()

  // Track which SSA values are integer constants; used to detect ALU-with-imm.
  let iconst_values : @hashmap.HashMap[Int, Unit] = @hashmap.new()
  for block in func.blocks {
    // Blockparams are defs at block entry.
    for pair in block.params {
      let (v, _) = pair
      def_block.set(v.id, block.id)
    }
    for inst in block.instructions {
      if inst.results.length() == 1 {
        let v = inst.results[0]
        def_block.set(v.id, block.id)
        def_inst.set(v.id, inst)
        if inst.opcode is Iconst(_) {
          iconst_values.set(v.id, ())
        }
      }
    }
  }

  // Identify remat candidates by SSA value id.
  let remat_values : @hashmap.HashMap[Int, Unit] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      if inst.results.length() == 1 && is_remat_candidate(inst, iconst_values) {
        remat_values.set(inst.results[0].id, ())
      }
    }
  }
  for block in func.blocks {
    // Cranelift-style behavior: insert the cloned def immediately before the
    // first use in this block (not at block entry), then reuse it for
    // subsequent uses in this block.
    let cache : @hashmap.HashMap[Int, Value] = @hashmap.new()
    let new_insts : Array[Inst] = []
    let orig_len = block.instructions.length()
    fn get_or_insert_copy(
      func : Function,
      use_block_id : Int,
      value : Value,
      def_block : @hashmap.HashMap[Int, Int],
      def_inst : @hashmap.HashMap[Int, Inst],
      cache : @hashmap.HashMap[Int, Value],
      insertion_point : Array[Inst],
      result : OptResult,
    ) -> Value? {
      // Only remat when the value is defined in a different block.
      match def_block.get(value.id) {
        Some(bid) => if bid == use_block_id { return None }
        None => return None
      }
      match cache.get(value.id) {
        Some(v) => Some(v)
        None => {
          let inst = match def_inst.get(value.id) {
            Some(i) => i
            None => return None
          }
          if inst.results.length() != 1 {
            return None
          }
          let new_value = func.new_value(value.ty)
          let ops : Array[Value] = []
          for op in inst.operands {
            ops.push(op)
          }
          insertion_point.push(Inst::new(Some(new_value), inst.opcode, ops))
          cache.set(value.id, new_value)
          result.mark_changed()
          Some(new_value)
        }
      }
    }

    // Rewrite uses in ordinary instructions, inserting cloned defs before the
    // first use.
    for inst in block.instructions {
      for i in 0..<inst.operands.length() {
        let op = inst.operands[i]
        if remat_values.get(op.id) is Some(_) {
          match
            get_or_insert_copy(
              func,
              block.id,
              op,
              def_block,
              def_inst,
              cache,
              new_insts,
              result,
            ) {
            Some(new_op) => inst.operands[i] = new_op
            None => ()
          }
        }
      }
      new_insts.push(inst)
    }

    // Rewrite uses in the terminator.
    if block.terminator is Some(term) {
      let new_term = rewrite_terminator_values(
        func,
        block.id,
        term,
        remat_values,
        def_block,
        def_inst,
        cache,
        new_insts,
        result,
      )
      block.terminator = Some(new_term)
    }

    // Replace instruction list if we inserted any cloned defs.
    if new_insts.length() != orig_len {
      block.instructions.clear()
      for inst in new_insts {
        block.instructions.push(inst)
      }
    }
  }
  result
}

///|
/// Is this instruction's result safe + cheap to rematerialize?
///
/// Mirrors Cranelift `remat.isle`: iconst/fconst, bnot, and ALU-with-imm.
fn is_remat_candidate(
  inst : Inst,
  iconst_values : @hashmap.HashMap[Int, Unit],
) -> Bool {
  match inst.opcode {
    Iconst(_) | Fconst(_) | Bnot => true
    Iadd | Isub | Band | Bor | Bxor =>
      if inst.operands.length() == 2 {
        let a = inst.operands[0].id
        let b = inst.operands[1].id
        iconst_values.get(a) is Some(_) || iconst_values.get(b) is Some(_)
      } else {
        false
      }
    _ => false
  }
}

///|
/// Rewrite values used by a terminator in-place, rematerializing where needed.
fn rewrite_terminator_values(
  func : Function,
  use_block_id : Int,
  term : Terminator,
  remat_values : @hashmap.HashMap[Int, Unit],
  def_block : @hashmap.HashMap[Int, Int],
  def_inst : @hashmap.HashMap[Int, Inst],
  cache : @hashmap.HashMap[Int, Value],
  insertion_point : Array[Inst],
  result : OptResult,
) -> Terminator {
  fn maybe_remat(
    func : Function,
    use_block_id : Int,
    v : Value,
    remat_values : @hashmap.HashMap[Int, Unit],
    def_block : @hashmap.HashMap[Int, Int],
    def_inst : @hashmap.HashMap[Int, Inst],
    cache : @hashmap.HashMap[Int, Value],
    insertion_point : Array[Inst],
    result : OptResult,
  ) -> Value {
    if remat_values.get(v.id) is None {
      return v
    }
    let db = def_block.get(v.id)
    match db {
      Some(bid) => if bid == use_block_id { return v }
      None => return v
    }
    match cache.get(v.id) {
      Some(existing) => existing
      None => {
        let inst = match def_inst.get(v.id) {
          Some(i) => i
          None => return v
        }
        if inst.results.length() != 1 {
          return v
        }
        let new_value = func.new_value(v.ty)
        let ops : Array[Value] = []
        for op in inst.operands {
          ops.push(op)
        }
        insertion_point.push(Inst::new(Some(new_value), inst.opcode, ops))
        cache.set(v.id, new_value)
        result.mark_changed()
        new_value
      }
    }
  }

  match term {
    Jump(target, args) => {
      let new_args : Array[Value] = []
      for v in args {
        new_args.push(
          maybe_remat(
            func, use_block_id, v, remat_values, def_block, def_inst, cache, insertion_point,
            result,
          ),
        )
      }
      Terminator::Jump(target, new_args)
    }
    Brz(cond, t, f) =>
      Terminator::Brz(
        maybe_remat(
          func, use_block_id, cond, remat_values, def_block, def_inst, cache, insertion_point,
          result,
        ),
        t,
        f,
      )
    Brnz(cond, t, f) =>
      Terminator::Brnz(
        maybe_remat(
          func, use_block_id, cond, remat_values, def_block, def_inst, cache, insertion_point,
          result,
        ),
        t,
        f,
      )
    BrTable(index, targets, default) =>
      Terminator::BrTable(
        maybe_remat(
          func, use_block_id, index, remat_values, def_block, def_inst, cache, insertion_point,
          result,
        ),
        targets,
        default,
      )
    Return(values) => {
      let new_values : Array[Value] = []
      for v in values {
        new_values.push(
          maybe_remat(
            func, use_block_id, v, remat_values, def_block, def_inst, cache, insertion_point,
            result,
          ),
        )
      }
      Terminator::Return(new_values)
    }
    Trap(s) => Terminator::Trap(s)
  }
}
