///|
/// Which locals a control merge has to carry.
///
/// A merge block needs a parameter for a local only when the edges reaching it
/// can disagree about that local's value. Every edge into a structured region's
/// merge point leaves from inside that region, and every one of them starts
/// from the state at the region's entry, so two edges can disagree only about a
/// local the region writes. For any other local each edge carries the one value
/// that flowed in, and a parameter for it would be a phi whose arguments are
/// all the same value.
///
/// So a merge carries exactly the locals written somewhere in its region,
/// nested regions included. That is a fact about the values, not a heuristic: a
/// local outside the set provably cannot differ between predecessors, which is
/// what lets the translator keep using the value it already holds instead of
/// reading a parameter back.
///
/// This says nothing about locals that are written and then never read. That
/// half needs whole-function liveness, `eliminate_dead_block_params` in
/// `milkir` already computes it, and it can answer precisely what a pass over
/// the region tree here could only approximate.

///|
/// Mark every local index written anywhere in `body`, nested regions included.
/// `local.set` and `local.tee` are the only instructions that write a local.
fn mark_written_locals(
  body : Array[@types.Instruction],
  written : Array[Bool],
) -> Unit {
  for instr in body {
    match instr {
      LocalSet(idx) | LocalTee(idx) =>
        if idx >= 0 && idx < written.length() {
          written[idx] = true
        }
      Block(_, inner) | Loop(_, inner) => mark_written_locals(inner, written)
      If(_, then_body, else_body) => {
        mark_written_locals(then_body, written)
        mark_written_locals(else_body, written)
      }
      TryTable(_, _, inner) => mark_written_locals(inner, written)
      _ => ()
    }
  }
}

///|
/// The local indices a region's merge block carries, ascending, which is also
/// the order they appear in the block's parameter list. `bodies` is every
/// instruction sequence the region covers -- two of them for an `if`.
fn Translator::region_local_params(
  self : Translator,
  bodies : Array[Array[@types.Instruction]],
) -> Array[Int] {
  let written = Array::make(self.locals.length(), false)
  for body in bodies {
    mark_written_locals(body, written)
  }
  let indices = []
  for idx, is_written in written {
    if is_written {
      indices.push(idx)
    }
  }
  indices
}

///|
/// Give `block` one parameter per carried local, typed from the local it
/// stands for. Call once, right after the block's explicit parameters.
fn Translator::add_local_block_params(
  self : Translator,
  block : Block,
  local_params : Array[Int],
) -> Unit {
  for idx in local_params {
    self.builder.add_block_param(block, self.locals[idx].ty) |> ignore
  }
}

///|
/// Append the current value of each local the target block carries, in
/// parameter order, to a branch's argument list.
fn Translator::push_local_args(
  self : Translator,
  args : Array[Value],
  local_params : Array[Int],
) -> Unit {
  for idx in local_params {
    args.push(self.locals[idx])
  }
}

///|
/// Adopt a merge block's parameters as the current values of the locals it
/// carries. Locals it does not carry are left alone: they hold the same value
/// on every edge into the block, so the value already in hand is correct.
fn Translator::adopt_local_params(
  self : Translator,
  block : Block,
  local_params : Array[Int],
  start : Int,
) -> Unit {
  for i, idx in local_params {
    self.locals[idx] = block.params[start + i].0
  }
}
