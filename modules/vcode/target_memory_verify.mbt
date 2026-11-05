///|
pub fn[Inst] TargetInstructionVerifier::scalar_load(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
  extension : @native.LoadExtension,
  result_type : @native.ValueType,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if !@native.valid_scalar_load(width, extension, result_type) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} scalar load type or extension",
    )
  }
  self.shape([Ptr64], [result_type])
}

///|
pub fn[Inst] TargetInstructionVerifier::scalar_store(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
  value_type : @native.ValueType,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if !@native.valid_scalar_store(width, value_type) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} scalar store type or width",
    )
  }
  self.shape([Ptr64, value_type], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::atomic_load(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
  ty : @native.ValueType,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if !@native.valid_atomic_access(width, ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} atomic load width or type",
    )
  }
  self.shape([Ptr64], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::atomic_store(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
  ty : @native.ValueType,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if !@native.valid_atomic_access(width, ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} atomic store width or type",
    )
  }
  self.shape([Ptr64, ty], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::atomic_rmw(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
  ty : @native.ValueType,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if !@native.valid_atomic_access(width, ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} atomic RMW width or type",
    )
  }
  self.shape([Ptr64, ty], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::atomic_compare_exchange(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
  ty : @native.ValueType,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if !@native.valid_atomic_access(width, ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} atomic compare-exchange width or type",
    )
  }
  self.shape([Ptr64, ty, ty], [ty])
  self.atomic_early_def(
    "atomic compare-exchange result must be an early definition",
  )
}

///|
pub fn[Inst] TargetInstructionVerifier::atomic_early_def(
  self : TargetInstructionVerifier[Inst],
  message : String,
) -> Unit raise TargetVCodeVerifyError {
  let result = self.function
    .instruction_operands(self.instruction)
    .filter(operand => operand.role == Def)[0]
  if result.timing != Early {
    raise InvalidInstruction(instruction=self.instruction, message~)
  }
}

///|
pub fn[Inst] TargetInstructionVerifier::store_repeated64(
  self : TargetInstructionVerifier[Inst],
  offset : UInt64,
  count : UInt32,
) -> Unit raise TargetVCodeVerifyError {
  if count == 0U || offset > 0xFFFFFFFFFFFFFFFFUL - count.to_uint64() * 8UL {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid repeated word range",
    )
  }
  self.shape([Ptr64], [Ptr64, I64, I64])
  for index, operand in self.function.instruction_operands(self.instruction) {
    if operand.timing != (if index == 0 { Late } else { Early }) ||
      operand.tie_id >= 0 ||
      !(operand.constraint is AnyReg || operand.constraint is FixedReg(_)) {
      raise InvalidInstruction(
        instruction=self.instruction,
        message="word fill requires a late address and three independent early register temporaries",
      )
    }
  }
}
