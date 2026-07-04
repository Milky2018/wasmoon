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

///|
pub fn max_physical_reg_id(regs : Array[PhysicalReg]) -> Int {
  let mut max_id = -1
  for preg in regs {
    if preg.id > max_id {
      max_id = preg.id
    }
  }
  max_id
}

///|
pub fn select_caller_saved_regs(
  allocatable_regs : Array[PhysicalReg],
  callee_saved_regs : Array[PhysicalReg],
) -> Array[PhysicalReg] {
  let mut max_id = max_physical_reg_id(allocatable_regs)
  let callee_max_id = max_physical_reg_id(callee_saved_regs)
  if callee_max_id > max_id {
    max_id = callee_max_id
  }
  let is_callee_saved = Array::make(max_id + 1, false)
  for preg in callee_saved_regs {
    if preg.id >= 0 && preg.id < is_callee_saved.length() {
      is_callee_saved[preg.id] = true
    }
  }
  let caller_saved : Array[PhysicalReg] = []
  for preg in allocatable_regs {
    if preg.id >= 0 &&
      preg.id < is_callee_saved.length() &&
      !is_callee_saved[preg.id] {
      caller_saved.push(preg)
    }
  }
  caller_saved
}

///|
pub(all) enum ParamPreassignDecision {
  PreassignIncoming(Bool)
  HintIncoming
  Defer
} derive(Eq, Debug)

///|
pub fn plan_param_preassignment(
  strict_precolor : Bool,
  is_pinned_special_param : Bool,
  crosses_call : Bool,
) -> ParamPreassignDecision {
  if crosses_call && !is_pinned_special_param {
    Defer
  } else if strict_precolor || is_pinned_special_param {
    PreassignIncoming(
      is_pinned_special_param || (strict_precolor && !crosses_call),
    )
  } else {
    HintIncoming
  }
}
