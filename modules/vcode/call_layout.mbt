///|
/// Register assignment shared by the native backends' internal calls.
pub struct InternalAbi {
  priv context_argument : PhysicalReg
  result_area_argument : PhysicalReg
  priv integer_arguments : Array[PhysicalReg]
  priv fp_arguments : Array[PhysicalReg]
  priv integer_results : Array[PhysicalReg]
  priv fp_results : Array[PhysicalReg]
}

///|
#derive(Eq, Debug)
pub struct InternalCallPlan {
  arguments : ArrayView[CallArgumentLocation]
  results : ArrayView[CallResultLocation]
  stack_size : Int32
  result_area_size : Int32
}

///|
#derive(Eq, Debug)
pub suberror InternalAbiError {
  InvalidRegister(role~ : String, index~ : Int32)
  DuplicateRegister(role~ : String, index~ : Int32)
  ContextRegisterReused(index~ : Int32)
  ResultAreaRegisterReused(index~ : Int32)
  InvalidSignature(message~ : String)
}

///|
pub impl Show for InternalAbiError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn checked_registers(
  role : String,
  indices : Array[Int32],
  class : RegClass,
) -> Array[PhysicalReg] raise InternalAbiError {
  let registers : Array[PhysicalReg] = []
  for index in indices {
    if index < 0 || index >= 16 {
      raise InvalidRegister(role~, index~)
    }
    if registers.contains(PhysicalReg::new(index, class)) {
      raise DuplicateRegister(role~, index~)
    }
    registers.push(PhysicalReg::new(index, class))
  }
  registers
}

///|
pub fn InternalAbi::new(
  context_argument : Int32,
  result_area_argument : Int32,
  integer_arguments : Array[Int32],
  fp_arguments : Array[Int32],
  integer_results : Array[Int32],
  fp_results : Array[Int32],
) -> InternalAbi raise InternalAbiError {
  if context_argument < 0 || context_argument >= 16 {
    raise InvalidRegister(role="context argument", index=context_argument)
  }
  let context = PhysicalReg::new(context_argument, Int)
  if result_area_argument < 0 || result_area_argument >= 16 {
    raise InvalidRegister(
      role="result area argument",
      index=result_area_argument,
    )
  }
  let result_area = PhysicalReg::new(result_area_argument, Int)
  let integer_arguments = checked_registers(
    "integer argument",
    integer_arguments,
    Int,
  )
  if integer_arguments.contains(context) {
    raise ContextRegisterReused(index=context_argument)
  }
  if result_area == context || integer_arguments.contains(result_area) {
    raise ResultAreaRegisterReused(index=result_area_argument)
  }
  let integer_results = checked_registers(
    "integer result",
    integer_results,
    Int,
  )
  if integer_results.contains(result_area) {
    raise ResultAreaRegisterReused(index=result_area_argument)
  }
  {
    context_argument: context,
    result_area_argument: result_area,
    integer_arguments,
    fp_arguments: checked_registers("FP argument", fp_arguments, FpVector),
    integer_results,
    fp_results: checked_registers("FP result", fp_results, FpVector),
  }
}

///|
pub fn InternalAbi::call_layout(
  self : InternalAbi,
  signature : @native.Signature,
) -> CallLayout raise InternalAbiError {
  if signature.params.is_empty() || signature.params[0] != Ptr64 {
    raise InvalidSignature(
      message="internal signature must start with an explicit ptr64 execution environment",
    )
  }
  let mut integer_count = 0
  for index in 1..<signature.params.length() {
    if reg_class_for_value_type(signature.params[index]) == Int {
      integer_count += 1
    }
  }
  let integer_overflow = if integer_count > self.integer_arguments.length() {
    integer_count - self.integer_arguments.length()
  } else {
    0
  }
  let arguments : Array[CallArgumentLocation] = [
    CallRegister(self.context_argument),
  ]
  let mut integer_index = 0
  let mut fp_index = 0
  let mut integer_stack_index = 0
  let mut fp_stack_offset = integer_overflow * 8
  for index in 1..<signature.params.length() {
    let ty = signature.params[index]
    if reg_class_for_value_type(ty) == Int {
      if integer_index < self.integer_arguments.length() {
        arguments.push(CallRegister(self.integer_arguments[integer_index]))
      } else {
        arguments.push(CallStack(integer_stack_index * 8))
        integer_stack_index += 1
      }
      integer_index += 1
    } else {
      if fp_index < self.fp_arguments.length() {
        arguments.push(CallRegister(self.fp_arguments[fp_index]))
      } else {
        let alignment = call_stack_size(ty)
        fp_stack_offset = call_align_up(fp_stack_offset, alignment)
        arguments.push(CallStack(fp_stack_offset))
        fp_stack_offset += alignment
      }
      fp_index += 1
    }
  }
  { arguments: arguments[:], stack_size: call_align_up(fp_stack_offset, 16), }
}

///|
pub fn InternalAbi::result_layout(
  self : InternalAbi,
  result_types : Array[@native.ValueType],
) -> (ArrayView[CallResultLocation], Int32) {
  let locations : Array[CallResultLocation] = []
  let mut integer_index = 0
  let mut fp_index = 0
  let mut integer_area_offset = 0
  for ty in result_types {
    if reg_class_for_value_type(ty) == Int &&
      integer_index >= self.integer_results.length() {
      integer_area_offset += 8
    }
    if reg_class_for_value_type(ty) == Int {
      integer_index += 1
    }
  }
  integer_index = 0
  let mut fp_area_offset = integer_area_offset
  for ty in result_types {
    if reg_class_for_value_type(ty) == Int {
      if integer_index < self.integer_results.length() {
        locations.push(CallResultRegister(self.integer_results[integer_index]))
      } else {
        locations.push(
          CallResultArea(
            (integer_index - self.integer_results.length()) * 8,
            self.result_area_argument,
          ),
        )
      }
      integer_index += 1
    } else {
      if fp_index < self.fp_results.length() {
        locations.push(
          CallResultRegister(
            PhysicalReg::new(
              self.fp_results[fp_index].id,
              reg_class_for_value_type(ty),
            ),
          ),
        )
      } else {
        let size = call_stack_size(ty)
        fp_area_offset = call_align_up(fp_area_offset, size)
        locations.push(
          CallResultArea(fp_area_offset, self.result_area_argument),
        )
        fp_area_offset += size
      }
      fp_index += 1
    }
  }
  (locations[:], call_align_up(fp_area_offset, 16))
}

///|
pub fn InternalAbi::call_plan(
  self : InternalAbi,
  signature : @native.Signature,
) -> InternalCallPlan raise InternalAbiError {
  let layout = self.call_layout(signature)
  let (results, result_area_size) = self.result_layout(signature.results)
  {
    arguments: layout.arguments,
    results,
    stack_size: layout.stack_size,
    result_area_size,
  }
}

///|
#derive(Eq, Debug)
pub(all) enum CallArgumentLocation {
  CallRegister(PhysicalReg)
  CallStack(Int32)
}

///|
#derive(Eq, Debug)
pub struct CallLayout {
  arguments : ArrayView[CallArgumentLocation]
  stack_size : Int32
}

///|
#derive(Eq, Debug)
pub(all) enum CallResultLocation {
  CallResultRegister(PhysicalReg)
  CallResultArea(Int32, PhysicalReg)
}

///|
fn call_align_up(value : Int32, alignment : Int32) -> Int32 {
  (value + alignment - 1) / alignment * alignment
}

///|
pub fn call_stack_size(ty : @native.ValueType) -> Int32 {
  if ty == V128 {
    16
  } else {
    8
  }
}

///|
pub fn InternalCallPlan::valid_results(
  plan : InternalCallPlan,
  types : Array[@native.ValueType],
) -> Bool {
  if plan.results.length() != types.length() ||
    plan.result_area_size < 0 ||
    plan.result_area_size % 16 != 0 {
    return false
  }
  let mut area_end = 0
  let mut area_register : PhysicalReg? = None
  for index, ty in types {
    match plan.results[index] {
      CallResultRegister(reg) =>
        if reg.id < 0 ||
          reg.id >= 16 ||
          reg.class != reg_class_for_value_type(ty) {
          return false
        }
      CallResultArea(offset, reg) => {
        let size = call_stack_size(ty)
        if offset < 0 ||
          offset % size != 0 ||
          reg.id < 0 ||
          reg.id >= 16 ||
          reg.class != Int {
          return false
        }
        match area_register {
          Some(expected) if expected != reg => return false
          None => area_register = Some(reg)
          _ => ()
        }
        let end = offset + size
        if end > area_end {
          area_end = end
        }
      }
    }
  }
  call_align_up(area_end, 16) == plan.result_area_size
}

///|
/// Lay out platform arguments with the target's integer registers and eight FP slots.
pub fn platform_call_layout(
  types : Array[@native.ValueType],
  integer_registers : ArrayView[Int32],
) -> CallLayout {
  let arguments : Array[CallArgumentLocation] = []
  let mut int_index = 0
  let mut fp_index = 0
  let mut stack_size = 0
  for ty in types {
    let class = reg_class_for_value_type(ty)
    let index = if class == Int {
      let current = int_index
      int_index += 1
      current
    } else {
      let current = fp_index
      fp_index += 1
      current
    }
    let register_capacity = if class == Int {
      integer_registers.length()
    } else {
      8
    }
    if index < register_capacity {
      arguments.push(
        CallRegister(
          PhysicalReg::new(
            if class == Int {
              integer_registers[index]
            } else {
              index
            },
            class,
          ),
        ),
      )
    } else {
      let alignment = call_stack_size(ty)
      stack_size = call_align_up(stack_size, alignment)
      arguments.push(CallStack(stack_size))
      stack_size += alignment
    }
  }
  { arguments: arguments[:], stack_size: call_align_up(stack_size, 16), }
}

///|
pub fn InternalCallPlan::result_area_register(
  plan : InternalCallPlan,
) -> PhysicalReg? {
  for result in plan.results {
    if result is CallResultArea(_, reg) {
      return Some(reg)
    }
  }
  None
}
