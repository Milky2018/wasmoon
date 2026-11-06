///|
#derive(Eq, Debug)
pub(all) suberror TargetVCodeVerifyError {
  CommonFailure(cause~ : VCodeVerifyError)
  InvalidInstruction(instruction~ : Instruction, message~ : String)
}

///|
pub impl Show for TargetVCodeVerifyError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub fn[Inst] require_fixed_use(
  function : Function[Inst],
  instruction : Instruction,
  operand_index : Int32,
  expected : PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  let operand = function
    .instruction_operand_at(instruction, operand_index)
    .unwrap()
  if operand.constraint != FixedReg(expected) {
    raise InvalidInstruction(
      instruction~,
      message="operand does not use the required ABI register",
    )
  }
}

///|
pub fn[Inst] require_home_def(
  function : Function[Inst],
  instruction : Instruction,
  operand_index : Int32,
) -> Unit raise TargetVCodeVerifyError {
  if function.instruction_operand_at(instruction, operand_index).unwrap().constraint !=
    AnyLocation {
    raise InvalidInstruction(
      instruction~,
      message="ABI materialization result must use its stable home",
    )
  }
}

///|
fn call_preference(
  location : CallArgumentLocation,
  is_allocatable : (PhysicalReg) -> Bool,
) -> PhysicalReg? {
  match location {
    CallRegister(reg) if is_allocatable(reg) => Some(reg)
    CallRegister(_) | CallStack(_) => None
  }
}

///|
pub fn[Inst] require_call_argument_inputs(
  function : Function[Inst],
  instruction : Instruction,
  operand_start : Int32,
  locations : ArrayView[CallArgumentLocation],
  is_allocatable : (PhysicalReg) -> Bool,
) -> Unit raise TargetVCodeVerifyError {
  for index, location in locations {
    let operand = function
      .instruction_operand_at(instruction, operand_start + index)
      .unwrap()
    if operand.constraint != AnyLocation ||
      operand.preference != call_preference(location, is_allocatable) {
      raise InvalidInstruction(
        instruction~,
        message="call argument does not match its ABI preference",
      )
    }
  }
}

///|
pub fn[Inst] require_instruction_shape(
  function : Function[Inst],
  instruction : Instruction,
  use_types : Array[@native.ValueType],
  def_types : Array[@native.ValueType],
  terminator : Bool,
  successor_count : Int32,
) -> Unit raise TargetVCodeVerifyError {
  let operands = function.instruction_operands(instruction)
  let uses = operands.filter(operand => operand.role == Use)
  let defs = operands.filter(operand => operand.role == Def)
  if uses.length() != use_types.length() ||
    defs.length() != def_types.length() ||
    function.instruction_is_terminator(instruction) != terminator ||
    function.instruction_successor_count(instruction) != successor_count {
    raise InvalidInstruction(
      instruction~,
      message="invalid operand, placement, or successor shape",
    )
  }
  for index, operand in uses {
    let expected = use_types[index]
    let actual = function.value_type(operand.value)
    if actual != Some(expected) &&
      !((actual == Some(I64) && expected == Ptr64) ||
      (actual == Some(Ptr64) && expected == I64)) {
      raise InvalidInstruction(instruction~, message="invalid use value type")
    }
  }
  for index, operand in defs {
    if function.value_type(operand.value) != Some(def_types[index]) {
      raise InvalidInstruction(instruction~, message="invalid def value type")
    }
  }
}

///|
pub fn[Inst] require_tail_call_plan(
  function : Function[Inst],
  instruction : Instruction,
  signature : @native.Signature,
  plan : InternalCallPlan,
  indirect : Bool,
  is_allocatable : (PhysicalReg) -> Bool,
  expected_clobbers : Array[PhysicalReg],
) -> Unit raise TargetVCodeVerifyError {
  if plan.arguments.length() != signature.params.length() ||
    !plan.valid_results(signature.results) ||
    plan.stack_size < 0 ||
    plan.stack_size % 16 != 0 ||
    function.protocol() != Internal ||
    signature.results != function.result_types() {
    raise InvalidInstruction(
      instruction~,
      message="tail-call plan is not compatible with the current function",
    )
  }
  let use_types : Array[@native.ValueType] = if indirect {
    [Ptr64, ..signature.params]
  } else {
    signature.params.copy()
  }
  if plan.result_area_size > 0 {
    use_types.push(Ptr64)
  }
  require_instruction_shape(function, instruction, use_types, [], true, 0)
  let operand_start = if indirect { 1 } else { 0 }
  if indirect {
    let callee = function.instruction_operand_at(instruction, 0).unwrap()
    if callee.constraint != AnyLocation || callee.preference is Some(_) {
      raise InvalidInstruction(
        instruction~,
        message="tail-call callee must remain allocatable without a preference",
      )
    }
  }
  require_call_argument_inputs(
    function,
    instruction,
    operand_start,
    plan.arguments,
    is_allocatable,
  )
  if plan.result_area_size > 0 {
    let operand = function
      .instruction_operand_at(
        instruction,
        operand_start + signature.params.length(),
      )
      .unwrap()
    let expected = plan
      .result_area_register()
      .bind(reg => if is_allocatable(reg) { Some(reg) } else { None })
    if operand.constraint != AnyLocation || operand.preference != expected {
      raise InvalidInstruction(
        instruction~,
        message="tail-call result area does not match its ABI preference",
      )
    }
  }
  if function.instruction_clobbers(instruction) != expected_clobbers {
    raise InvalidInstruction(
      instruction~,
      message="tail call has an invalid caller-saved clobber set",
    )
  }
}

///|
/// Operand and metadata checks for one instruction in an already verified
/// function. The target selects the rule from its original opcode.
#valtype
pub struct TargetInstructionVerifier[Inst] {
  priv function : Function[Inst]
  priv instruction : Instruction
}

///|
pub fn[Inst] TargetInstructionVerifier::new(
  function : Function[Inst],
  instruction : Instruction,
) -> TargetInstructionVerifier[Inst] {
  { function, instruction, }
}

///|
pub fn[Inst] TargetInstructionVerifier::shape(
  self : TargetInstructionVerifier[Inst],
  uses : Array[@native.ValueType],
  defs : Array[@native.ValueType],
  successors? : Int32,
) -> Unit raise TargetVCodeVerifyError {
  require_instruction_shape(
    self.function,
    self.instruction,
    uses,
    defs,
    successors is Some(_),
    successors.unwrap_or(0),
  )
}

///|
fn[Inst] TargetInstructionVerifier::fixed_use(
  self : TargetInstructionVerifier[Inst],
  index : Int32,
  register : PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  require_fixed_use(self.function, self.instruction, index, register)
}

///|
fn[Inst] TargetInstructionVerifier::home_def(
  self : TargetInstructionVerifier[Inst],
  index : Int32,
) -> Unit raise TargetVCodeVerifyError {
  require_home_def(self.function, self.instruction, index)
}

///|
pub fn[Inst] TargetInstructionVerifier::incoming_reg(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  reg : PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  if reg.class != reg_class_for_value_type(ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="incoming register class does not match value type",
    )
  }
  self.shape([ty], [ty])
  self.fixed_use(0, reg)
  self.home_def(1)
}

///|
pub fn[Inst] TargetInstructionVerifier::incoming_stack(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  offset : Int32,
) -> Unit raise TargetVCodeVerifyError {
  if offset < 0 || offset % 8 != 0 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="incoming stack offset must be non-negative and 8-byte aligned",
    )
  }
  self.shape([], [ty])
  self.home_def(0)
}

///|
pub fn[Inst] TargetInstructionVerifier::incoming_result_area(
  self : TargetInstructionVerifier[Inst],
  reg : PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  if reg.id < 0 || reg.id >= 16 || reg.class != Int {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="incoming result-area register must be an integer ABI register",
    )
  }
  self.shape([], [Ptr64])
  self.home_def(0)
}

///|
pub fn[Inst] TargetInstructionVerifier::incoming_call_result(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  reg : PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  if reg.class != reg_class_for_value_type(ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="call result register class does not match value type",
    )
  }
  self.shape([], [ty])
  self.home_def(0)
}

///|
pub fn[Inst] TargetInstructionVerifier::incoming_call_area_result(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  offset : Int32,
) -> Unit raise TargetVCodeVerifyError {
  let size = call_stack_size(ty)
  if offset < 0 || offset % size != 0 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="call result-area offset is invalid for its value type",
    )
  }
  self.shape([], [ty])
  self.home_def(0)
}

///|
pub fn[Inst] TargetInstructionVerifier::outgoing_reg(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  reg : PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  if reg.class != reg_class_for_value_type(ty) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="outgoing register class does not match value type",
    )
  }
  self.shape([ty], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::outgoing_area_result(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  offset : Int32,
) -> Unit raise TargetVCodeVerifyError {
  let size = call_stack_size(ty)
  if offset < 0 || offset % size != 0 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="outgoing result-area offset is invalid for its value type",
    )
  }
  self.shape([Ptr64, ty], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::load_null(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty != Ptr64 && ty != GcRef64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="null materialization requires ptr64 or gcref64",
    )
  }
  self.shape([], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::load_float_constant(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  bits : UInt64,
) -> Unit raise TargetVCodeVerifyError {
  if (ty != F32 && ty != F64) || (ty == F32 && bits > 0xFFFFFFFFUL) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid scalar floating-point constant",
    )
  }
  self.shape([], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::carrier_move(
  self : TargetInstructionVerifier[Inst],
  from : @native.ValueType,
  to : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if !((from == GcRef64 && to == Ptr64) || (from == I64 && to == GcRef64)) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="carrier move requires gcref64-to-ptr64 or i64-to-gcref64",
    )
  }
  self.shape([from], [to])
}

///|
pub fn[Inst] TargetInstructionVerifier::scalar_select(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty == V128 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="scalar select does not accept v128",
    )
  }
  self.shape([I32, ty, ty], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::reference_compare(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty != Ptr64 && ty != GcRef64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="reference comparison requires ptr64 or gcref64",
    )
  }
  self.shape([ty, ty], [I32])
}

///|
pub fn[Inst] TargetInstructionVerifier::safepoint_marker(
  self : TargetInstructionVerifier[Inst],
) -> Unit raise TargetVCodeVerifyError {
  if self.function
    .instruction_annotations(self.instruction)
    .unwrap()
    .safepoint()
    is None {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="safepoint marker requires safepoint metadata",
    )
  }
  self.shape([], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::trap(
  self : TargetInstructionVerifier[Inst],
  reason : @native.TrapReason,
) -> Unit raise TargetVCodeVerifyError {
  if self.function.instruction_annotations(self.instruction).unwrap().trap() !=
    Some(reason) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="trap terminator metadata does not match its reason",
    )
  }
  self.shape([], [], successors=0)
}

///|
pub fn[Inst] TargetInstructionVerifier::return_shape(
  self : TargetInstructionVerifier[Inst],
) -> Unit raise TargetVCodeVerifyError {
  let operands = self.function.instruction_operands(self.instruction)
  if !self.function.instruction_is_terminator(self.instruction) ||
    self.function.instruction_successor_count(self.instruction) != 0 ||
    !operands.is_empty() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid return shape",
    )
  }
}

///|
pub fn[Inst] TargetInstructionVerifier::stack_address(
  self : TargetInstructionVerifier[Inst],
  valid : Bool,
) -> Unit raise TargetVCodeVerifyError {
  if !valid {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid target stack-object descriptor",
    )
  }
  self.shape([], [Ptr64])
}

///|
pub fn[Inst] TargetInstructionVerifier::load_constant(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  bits : UInt64,
) -> Unit raise TargetVCodeVerifyError {
  if ty == I32 && bits > 0xFFFFFFFFUL {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="32-bit constant has non-zero high bits",
    )
  }
  self.shape([], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::trap_if_zero(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if self.function.instruction_annotations(self.instruction).unwrap().trap() !=
    Some(IntegerDivisionByZero) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="zero-divisor check requires division-by-zero trap metadata",
    )
  }
  self.shape([ty], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::trap_if_signed_div_overflow(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if self.function.instruction_annotations(self.instruction).unwrap().trap() !=
    Some(IntegerOverflow) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="signed-division check requires overflow trap metadata",
    )
  }
  self.shape([ty, ty], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::switch_shape(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  cases : Array[UInt64],
) -> Unit raise TargetVCodeVerifyError {
  if self.function.instruction_successor_count(self.instruction) !=
    cases.length() + 1 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="switch successor count does not match its cases",
    )
  }
  for index, bits in cases {
    let mut duplicate = false
    for previous in 0..<index {
      if cases[previous] == bits {
        duplicate = true
      }
    }
    if (ty == I32 && bits > 0xFFFFFFFFUL) || duplicate {
      raise InvalidInstruction(
        instruction=self.instruction,
        message="switch cases must be unique values of the index width",
      )
    }
  }
  self.shape([ty], [], successors=cases.length() + 1)
}

///|
pub fn[Inst] TargetInstructionVerifier::float_unary(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty != F32 && ty != F64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="scalar floating-point unary operation requires f32 or f64",
    )
  }
  self.shape([ty], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::float_binary(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty != F32 && ty != F64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="scalar floating-point binary operation requires f32 or f64",
    )
  }
  self.shape([ty, ty], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::float_ternary(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty != F32 && ty != F64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="scalar floating-point ternary operation requires f32 or f64",
    )
  }
  self.shape([ty, ty, ty], [ty])
}

///|
pub fn[Inst] TargetInstructionVerifier::float_compare(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
) -> Unit raise TargetVCodeVerifyError {
  if ty != F32 && ty != F64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="scalar floating-point comparison requires f32 or f64",
    )
  }
  self.shape([ty, ty], [I32])
}

///|
pub fn[Inst] TargetInstructionVerifier::trap_if_float(
  self : TargetInstructionVerifier[Inst],
  ty : @native.ValueType,
  unordered : Bool,
) -> Unit raise TargetVCodeVerifyError {
  let reason : @native.TrapReason = if unordered {
    InvalidConversionToInteger
  } else {
    IntegerOverflow
  }
  if (ty != F32 && ty != F64) ||
    self.function.instruction_annotations(self.instruction).unwrap().trap() !=
    Some(reason) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="float trap check requires a scalar float and matching conversion trap metadata",
    )
  }
  let uses = if unordered { [ty] } else { [ty, ty] }
  self.shape(uses, [])
}

///|
pub fn[Inst] TargetInstructionVerifier::conversion(
  self : TargetInstructionVerifier[Inst],
  shape : (@native.ValueType, @native.ValueType)?,
  raw_word_bitcast : Bool,
  target~ : String,
) -> Unit raise TargetVCodeVerifyError {
  if raw_word_bitcast {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="raw-word pointer bitcasts must be erased before VCode",
    )
  }
  guard shape is Some((source, result)) else {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid \{target} scalar conversion",
    )
  }
  self.shape([source], [result])
}
