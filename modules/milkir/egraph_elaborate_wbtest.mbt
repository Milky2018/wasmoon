///|
/// Build the e-graph shape `uextend(narrow << 3) + 3` for `sum`.
///
/// The two `3`s are one e-class: the e-graph interns constants by value, so
/// nothing distinguishes an i32 `3` from an i64 `3`. Elaborating this shape
/// therefore needs the same class materialized at both widths, which is the
/// case a class-keyed plan collapses into one.
fn dual_width_const_function() -> (
  Function,
  Inst,
  EGraphBuilder,
  Map[Int, @egraph.ENode],
) {
  let fb = FunctionBuilder::FunctionBuilder("dual_width_const")
  let wide = fb.add_param(I64)
  let narrow = fb.add_param(I32)
  fb.add_result(I64)
  let sum = fb.iadd(wide, wide)
  fb.return_([sum])
  let func = fb.get_function()
  let builder = EGraphBuilder::new_with_limits_and_ruleset(
    @egraph.SaturationLimits::cranelift_default(),
    @egraph.get_global_ruleset(),
  )
  let eg = builder.egraph
  let three = eg.add_const(3)
  let narrow_var = eg.add_var(narrow.id)
  let shifted = eg.add({ op: Shl, children: [narrow_var, three], })
  let widened = eg.add({ op: Uextend(32, 64), children: [shifted], })
  let root = eg.add({ op: Add, children: [widened, three], })
  // `narrow` is the one value elaboration may reuse; everything else in the
  // shape has to be built.
  builder.class_to_value.set(
    { class_id: eg.find(narrow_var).0, ty: I32, },
    narrow,
  )
  builder.value_map.set(sum.id, root)
  // Each class here holds exactly one node, but read it back rather than
  // reusing the literal: `add` canonicalizes commutative operands.
  let best_nodes : Map[Int, @egraph.ENode] = Map([])
  for class_id in [three, narrow_var, shifted, widened, root] {
    let canonical = eg.find(class_id).0
    best_nodes.set(canonical, eg.get_nodes(class_id)[0])
  }
  let mut sum_inst : Inst? = None
  for inst in func.blocks[0].instructions {
    if inst.first_result() is Some(value) && value.id == sum.id {
      sum_inst = Some(inst)
    }
  }
  (func, sum_inst.unwrap(), builder, best_nodes)
}

///|
/// Splice the instructions elaboration built in ahead of the one it rewrote,
/// the way the dominator walk does, so the result can be verified.
fn splice_before(func : Function, target : Inst, built : Array[Inst]) -> Unit {
  let block = func.blocks[0]
  let rebuilt : Array[Inst] = []
  for inst in block.instructions {
    if inst.id == target.id {
      for inst in built {
        rebuilt.push(inst)
      }
    }
    rebuilt.push(inst)
  }
  block.instructions.clear()
  for inst in rebuilt {
    block.instructions.push(inst)
  }
}

///|
/// A plan that runs past `ELABORATION_BUDGET` is abandoned partway through.
/// Nothing it worked out along the way may reach the caller: the caller
/// binds whatever was appended as a class representative without consulting
/// the return value, so a half-built plan would be spliced into the block.
///
/// "Nothing" includes `func`'s ID counters. `new_value` and `new_inst`
/// advance them, so a rewrite that built anything before deciding to abandon
/// would leak IDs while still appending nothing — invisible in the printed
/// function, which is why the counters are checked directly.
///
/// What this test does not do is separate this implementation from the one
/// before it. Both abandon this input during planning, before anything is
/// built. The previous one could only leak from failure points sitting after
/// the first `new_value` in its commit loop, and those were unreachable:
/// each re-derived what planning had already proved. An unreachable defect
/// cannot be pinned by a test, so it was removed by construction instead —
/// the build loop has no failure points now — and what stays testable is the
/// boundary contract below.
test "an abandoned elaboration appends nothing" {
  let fb = FunctionBuilder::FunctionBuilder("over_budget")
  let wide = fb.add_param(I64)
  fb.add_result(I64)
  let sum = fb.iadd(wide, wide)
  fb.return_([sum])
  let func = fb.get_function()
  let builder = EGraphBuilder::new_with_limits_and_ruleset(
    @egraph.SaturationLimits::cranelift_default(),
    @egraph.get_global_ruleset(),
  )
  let eg = builder.egraph
  // `(1 + 2) + (3 + 4)`: seven classes to build against a budget of four,
  // and the budget runs out with four instructions already planned.
  let left = eg.add({ op: Add, children: [eg.add_const(1), eg.add_const(2)], })
  let right = eg.add({ op: Add, children: [eg.add_const(3), eg.add_const(4)], })
  let root = eg.add({ op: Add, children: [left, right], })
  builder.value_map.set(sum.id, root)
  let best_nodes : Map[Int, @egraph.ENode] = Map([])
  for
    class_id in [
      eg.add_const(1),
      eg.add_const(2),
      eg.add_const(3),
      eg.add_const(4),
      left,
      right,
      root,
    ] {
    best_nodes.set(eg.find(class_id).0, eg.get_nodes(class_id)[0])
  }
  let mut sum_inst : Inst? = None
  for inst in func.blocks[0].instructions {
    if inst.first_result() is Some(value) && value.id == sum.id {
      sum_inst = Some(inst)
    }
  }
  let emitted : Array[Inst] = []
  let values_before = func.next_value_id
  let insts_before = func.next_inst_id
  inspect(
    builder.elaborate_inst(func, best_nodes, sum_inst.unwrap(), emitted),
    content="false",
  )
  inspect(emitted.length(), content="0")
  inspect(func.next_value_id == values_before, content="true")
  inspect(func.next_inst_id == insts_before, content="true")
  // `inst` still holds its original shape too.
  inspect(func.verify(), content="()")
  inspect(
    func.print(),
    content=(
      #|function over_budget(v0:i64) -> i64 {
      #|block0:
      #|    v1:i64 = iadd v0, v0
      #|    return v1
      #|}
      #|
    ),
  )
}

///|
test "elaboration builds a shared constant once per width it is needed at" {
  let (func, sum_inst, builder, best_nodes) = dual_width_const_function()
  let emitted : Array[Inst] = []
  let values_before = func.next_value_id
  let insts_before = func.next_inst_id
  inspect(
    builder.elaborate_inst(func, best_nodes, sum_inst, emitted),
    content="true",
  )
  // A successful rewrite spends exactly one value and one instruction per
  // instruction it emits. Anything more would mean the build loop created
  // something it then dropped.
  inspect(func.next_value_id - values_before, content="4")
  inspect(func.next_inst_id - insts_before, content="4")
  inspect(emitted.length(), content="4")
  splice_before(func, sum_inst, emitted)
  // The whole point: `ishl` needs an i32 shift amount and `iadd` an i64 one.
  // Reusing one built value for both puts an i64 operand on the i32 shift,
  // which is what the verifier rejects.
  inspect(func.verify(), content="()")
  // Two constants, one per width, rather than one shared across both.
  inspect(
    func.print(),
    content=(
      #|function dual_width_const(v0:i64, v1:i32) -> i64 {
      #|block0:
      #|    v3:i32 = iconst 3
      #|    v4:i32 = ishl v1, v3
      #|    v5:i64 = uextend v4
      #|    v6:i64 = iconst 3
      #|    v2:i64 = iadd v5, v6
      #|    return v2
      #|}
      #|
    ),
  )
}
