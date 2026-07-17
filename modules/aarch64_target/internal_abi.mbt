///|
pub struct InternalAbi {
  priv context_argument : @vcode.PhysicalReg
  priv integer_arguments : Array[@vcode.PhysicalReg]
  priv fp_arguments : Array[@vcode.PhysicalReg]
  priv integer_results : Array[@vcode.PhysicalReg]
  priv fp_results : Array[@vcode.PhysicalReg]
}

///|
pub struct InternalCallPlan {
  priv arguments : Array[CallArgumentLocation]
  priv results : Array[@vcode.PhysicalReg]
  priv stack_size : Int
} derive(Eq, Debug)

///|
pub suberror InternalAbiError {
  InvalidRegister(role~ : String, index~ : Int)
  DuplicateRegister(role~ : String, index~ : Int)
  ContextRegisterReused(index~ : Int)
  InvalidSignature(message~ : String)
  ResultAreaRequired(integer_count~ : Int, fp_count~ : Int)
} derive(Eq, Debug)

///|
pub impl Show for InternalAbiError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn checked_registers(
  role : String,
  indices : Array[Int],
  class : @vcode.RegClass,
) -> Array[@vcode.PhysicalReg] raise InternalAbiError {
  let registers : Array[@vcode.PhysicalReg] = []
  for index in indices {
    if index < 0 || index >= 16 {
      raise InvalidRegister(role~, index~)
    }
    if registers.contains(@vcode.PhysicalReg::new(index, class)) {
      raise DuplicateRegister(role~, index~)
    }
    registers.push(@vcode.PhysicalReg::new(index, class))
  }
  registers
}

///|
pub fn InternalAbi::new(
  context_argument : Int,
  integer_arguments : Array[Int],
  fp_arguments : Array[Int],
  integer_results : Array[Int],
  fp_results : Array[Int],
) -> InternalAbi raise InternalAbiError {
  if context_argument < 0 || context_argument >= 16 {
    raise InvalidRegister(role="context argument", index=context_argument)
  }
  let context = @vcode.PhysicalReg::new(context_argument, Int)
  let integer_arguments = checked_registers(
    "integer argument",
    integer_arguments,
    Int,
  )
  if integer_arguments.contains(context) {
    raise ContextRegisterReused(index=context_argument)
  }
  {
    context_argument: context,
    integer_arguments,
    fp_arguments: checked_registers("FP argument", fp_arguments, FpVector),
    integer_results: checked_registers("integer result", integer_results, Int),
    fp_results: checked_registers("FP result", fp_results, FpVector),
  }
}

///|
fn InternalAbi::copy(self : InternalAbi) -> InternalAbi {
  {
    context_argument: self.context_argument,
    integer_arguments: self.integer_arguments.copy(),
    fp_arguments: self.fp_arguments.copy(),
    integer_results: self.integer_results.copy(),
    fp_results: self.fp_results.copy(),
  }
}

///|
fn InternalAbi::call_layout(
  self : InternalAbi,
  signature : @semantic.Signature,
) -> CallLayout raise InternalAbiError {
  if signature.params.is_empty() || signature.params[0] != Ptr64 {
    raise InvalidSignature(
      message="internal signature must start with an explicit ptr64 execution environment",
    )
  }
  let mut integer_count = 0
  for index in 1..<signature.params.length() {
    if @vcode.reg_class_for_value_type(signature.params[index]) == Int {
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
    if @vcode.reg_class_for_value_type(ty) == Int {
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
  { arguments, stack_size: call_align_up(fp_stack_offset, 16) }
}

///|
fn InternalAbi::result_registers(
  self : InternalAbi,
  result_types : Array[@semantic.ValueType],
) -> Array[@vcode.PhysicalReg] raise InternalAbiError {
  let registers : Array[@vcode.PhysicalReg] = []
  let mut integer_index = 0
  let mut fp_index = 0
  for ty in result_types {
    if @vcode.reg_class_for_value_type(ty) == Int {
      if integer_index >= self.integer_results.length() {
        raise ResultAreaRequired(
          integer_count=integer_index + 1,
          fp_count=fp_index,
        )
      }
      registers.push(self.integer_results[integer_index])
      integer_index += 1
    } else {
      if fp_index >= self.fp_results.length() {
        raise ResultAreaRequired(
          integer_count=integer_index,
          fp_count=fp_index + 1,
        )
      }
      registers.push(
        @vcode.PhysicalReg::new(
          self.fp_results[fp_index].id,
          @vcode.reg_class_for_value_type(ty),
        ),
      )
      fp_index += 1
    }
  }
  registers
}

///|
fn InternalAbi::call_plan(
  self : InternalAbi,
  signature : @semantic.Signature,
) -> InternalCallPlan raise InternalAbiError {
  let layout = self.call_layout(signature)
  {
    arguments: layout.arguments,
    results: self.result_registers(signature.results),
    stack_size: layout.stack_size,
  }
}
