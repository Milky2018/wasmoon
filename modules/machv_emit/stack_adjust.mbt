///|
pub(all) struct StackAdjustStep {
  amount : Int
  probe_after : Bool
} derive(Debug, Eq)

///|
pub fn plan_stack_pointer_adjustment(
  amount : Int,
  page_size? : Int = 4096,
) -> Array[StackAdjustStep] {
  let steps : Array[StackAdjustStep] = []
  if amount == 0 {
    return steps
  }
  let (abs_amount, is_sub) = if amount < 0 {
    (-amount, true)
  } else {
    (amount, false)
  }
  if is_sub && abs_amount < page_size {
    steps.push({ amount, probe_after: false })
    return steps
  }
  let mut remaining = abs_amount
  while remaining >= page_size {
    steps.push({
      amount: if is_sub {
        -page_size
      } else {
        page_size
      },
      probe_after: is_sub,
    })
    remaining = remaining - page_size
  }
  if remaining > 0 {
    steps.push({
      amount: if is_sub {
        -remaining
      } else {
        remaining
      },
      probe_after: is_sub,
    })
  }
  steps
}
