///|
/// Machine-level calling-convention layout chosen by an embedding or frontend.
///
/// MachV treats this as data: target packages expose machine facts, while an
/// embedding chooses which registers implement its internal ABI.
pub(all) struct CallConventionLayout {
  context_arg : PReg
  user_arg_gprs : Array[PReg]
  arg_fprs : Array[PReg]
  ret_gprs : Array[PReg]
  ret_fprs : Array[PReg]
}

///|
/// Stack slot size (bytes) for overflow arguments in this convention.
pub fn CallConventionLayout::stack_slot_size(
  self : CallConventionLayout,
  class : RegClass,
) -> Int {
  ignore(self)
  match class {
    Vector => 16
    _ => 8
  }
}

///|
/// Stack slot alignment (bytes) for overflow arguments in this convention.
pub fn CallConventionLayout::stack_slot_align(
  self : CallConventionLayout,
  class : RegClass,
) -> Int {
  ignore(self)
  match class {
    Vector => 16
    _ => 8
  }
}

///|
/// Compute overflow argument stack layout for this convention.
///
/// Layout: [int_overflow...][float_overflow...] with V128 aligned to 16.
/// Returned offsets are relative to the start of the overflow area.
pub fn CallConventionLayout::layout_overflow_stack(
  self : CallConventionLayout,
  int_overflow_count : Int,
  float_overflow_classes : Array[RegClass],
) -> (Array[Int], Array[Int], Int) {
  let int_offsets : Array[Int] = []
  for i in 0..<int_overflow_count {
    int_offsets.push(i * 8)
  }
  let float_offsets : Array[Int] = []
  let mut cur = int_overflow_count * 8
  for class in float_overflow_classes {
    cur = align_up(cur, self.stack_slot_align(class))
    float_offsets.push(cur)
    cur = cur + self.stack_slot_size(class)
  }
  let total = align_up(cur, 16)
  (int_offsets, float_offsets, total)
}
