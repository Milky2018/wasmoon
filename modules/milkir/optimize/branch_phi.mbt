///|
/// Thread only an empty dispatch whose parameter values are supplied by this
/// edge. Parameters used outside the dispatch are rejected by the caller.
fn thread_constant_branch(
  function : @milkir.Function,
  block : @milkir.Block,
  incoming : Array[@milkir.Value],
) -> (Int32, Array[@milkir.Value])? {
  let (condition, yes, yes_args, no, no_args, reversed) = match
    block.terminator {
    Some(Branch(condition, yes, yes_args, no, no_args)) =>
      (condition, yes, yes_args, no, no_args, false)
    Some(Brnz(condition, yes, no)) => (condition, yes, [], no, [], false)
    Some(Brz(condition, yes, no)) => (condition, yes, [], no, [], true)
    _ => return None
  }
  guard rewrite_jump_args_through_block(block.params, incoming, [condition])
    is Some([condition]) &&
    function.defining_inst(condition) is Some(inst) &&
    inst.opcode is Scalar(IntConst(bits)) else {
    return None
  }
  let taken = if condition.ty is I32 {
    bits.to_int() != 0
  } else if condition.ty is I64 {
    bits != 0L
  } else {
    return None
  }
  let chosen = taken != reversed
  guard rewrite_jump_args_through_block(
      block.params,
      incoming,
      if chosen {
        yes_args
      } else {
        no_args
      },
    )
    is Some(arguments) else {
    return None
  }
  Some((if chosen { yes } else { no }, arguments))
}
