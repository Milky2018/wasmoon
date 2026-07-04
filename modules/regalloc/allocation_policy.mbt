///|
pub fn allocation_iteration_limit(bundle_count : Int) -> Int {
  bundle_count * 10
}

///|
pub fn should_force_spill_after_retry(
  attempts : Int,
  retry_limit : Int,
  is_pinned : Bool,
  has_fixed_constraint : Bool,
) -> Bool {
  attempts > retry_limit && !is_pinned && !has_fixed_constraint
}

///|
pub fn should_force_spill_for_class_and_call(
  class : RegClass,
  crosses_call : Bool,
) -> Bool {
  class == Vector && crosses_call
}

///|
pub fn select_available_regs_for_bundle(
  class : RegClass,
  crosses_call : Bool,
  available_regs : Array[PhysicalReg],
  callee_saved_regs : Array[PhysicalReg],
) -> Array[PhysicalReg] {
  if crosses_call {
    match class {
      Int | Float => callee_saved_regs
      Vector => []
    }
  } else {
    available_regs
  }
}
