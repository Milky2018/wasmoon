///|
/// Preserve the original operand array unless an actual substitution is needed.
fn rewrite_value_array(
  values : Array[@milkir.Value],
  rewrite : (@milkir.Value) -> @milkir.Value,
) -> Array[@milkir.Value]? {
  let mut updated : Array[@milkir.Value]? = None
  for index, value in values {
    let replacement = rewrite(value)
    if replacement.id != value.id {
      if updated is None {
        updated = Some(values.copy())
      }
      updated.unwrap()[index] = replacement
    }
  }
  updated
}

///|
/// Copy propagation and constant-phi removal share operand traversal; their
/// value resolution and dominance rules remain in their respective analyses.
fn rewrite_terminator_values(
  term : @milkir.Terminator,
  rewrite : (@milkir.Value) -> @milkir.Value,
) -> @milkir.Terminator? {
  match term {
    Jump(target, args) =>
      rewrite_value_array(args, rewrite).map(args => Jump(target, args))
    Return(values) =>
      rewrite_value_array(values, rewrite).map(values => Return(values))
    Branch(cond, true_target, true_args, false_target, false_args) => {
      let replacement = rewrite(cond)
      let new_true = rewrite_value_array(true_args, rewrite)
      let new_false = rewrite_value_array(false_args, rewrite)
      if replacement.id == cond.id && new_true is None && new_false is None {
        None
      } else {
        Some(
          Branch(
            replacement,
            true_target,
            new_true.unwrap_or(true_args),
            false_target,
            new_false.unwrap_or(false_args),
          ),
        )
      }
    }
    Brz(cond, yes, no) | Brnz(cond, yes, no) => {
      let replacement = rewrite(cond)
      if replacement.id == cond.id {
        None
      } else {
        Some(
          if term is Brz(_, _, _) {
            Brz(replacement, yes, no)
          } else {
            Brnz(replacement, yes, no)
          },
        )
      }
    }
    BrTable(index, targets, default_target) => {
      let replacement = rewrite(index)
      if replacement.id == index.id {
        None
      } else {
        Some(BrTable(replacement, targets, default_target))
      }
    }
    Trap(_) | TrapExit(_) => None
  }
}

///|
fn remap_terminator(
  term : @milkir.Terminator,
  target : (Int32) -> Int32,
  value? : (@milkir.Value) -> @milkir.Value,
) -> @milkir.Terminator {
  fn operand(v : @milkir.Value) -> @milkir.Value {
    match value {
      Some(rewrite) => rewrite(v)
      None => v
    }
  }
  fn operands(args : Array[@milkir.Value]) -> Array[@milkir.Value] {
    match value {
      Some(rewrite) => args.map(rewrite)
      None => args
    }
  }
  match term {
    Jump(id, args) => Jump(target(id), operands(args))
    Branch(condition, yes, aa, no, ba) =>
      Branch(
        operand(condition),
        target(yes),
        operands(aa),
        target(no),
        operands(ba),
      )
    Brz(condition, yes, no) => Brz(operand(condition), target(yes), target(no))
    Brnz(condition, yes, no) =>
      Brnz(operand(condition), target(yes), target(no))
    BrTable(index, targets, default_) =>
      BrTable(operand(index), targets.map(target), target(default_))
    Return(args) => Return(operands(args))
    Trap(_) | TrapExit(_) => term
  }
}
