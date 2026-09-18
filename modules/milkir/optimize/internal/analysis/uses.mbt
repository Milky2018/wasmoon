///|
/// Compute use counts for all values in a function
pub fn compute_use_counts(func : @milkir.Function) -> Array[Int] {
  let counts = Array::make(func.next_value_id, 0)
  fn count(value : @milkir.Value) -> Unit {
    counts[value.id] = counts[value.id] + 1
  }
  for block in func.blocks {
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      for op in inst.operands {
        count(op)
      }
    }
    if block.terminator is Some(term) {
      match term {
        Jump(_, args) | Return(args) =>
          for value in args {
            count(value)
          }
        Branch(cond, _, true_args, _, false_args) => {
          count(cond)
          for value in true_args {
            count(value)
          }
          for value in false_args {
            count(value)
          }
        }
        Brz(cond, _, _) | Brnz(cond, _, _) => count(cond)
        BrTable(index, _, _) => count(index)
        Trap(_) | TrapExit(_) => ()
      }
    }
  }
  counts
}
