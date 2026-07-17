///|
pub(all) enum GprWidth {
  W32
  W64
} derive(Eq, Debug)

///|
pub(all) enum AArch64IntUnary {
  Mvn
  Clz
  Rbit
  Neg
} derive(Eq, Debug)

///|
pub(all) enum AArch64IntBinary {
  Add
  Sub
  Mul
  And
  Orr
  Eor
  Lsl
  Asr
  Lsr
  Ror
  Sdiv
  Udiv
} derive(Eq, Debug)

///|
pub(all) enum AArch64Condition {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  Lo
  Ls
  Hi
  Hs
} derive(Eq, Debug)

///|
pub(all) enum AArch64FloatUnary {
  Negate
  Absolute
  SquareRoot
  Ceil
  Floor
  Truncate
  Nearest
} derive(Eq, Debug)

///|
pub(all) enum AArch64FloatBinary {
  Add
  Sub
  Mul
  Div
  Min
  Max
  CopySign
} derive(Eq, Debug)

///|
pub(all) enum AArch64FloatTernary {
  Fmadd
  Fmsub
  Fnmadd
  Fnmsub
} derive(Eq, Debug)

///|
pub(all) enum AArch64VectorIntUnary {
  Absolute
  Negate
} derive(Eq, Debug)

///|
pub(all) enum AArch64VectorIntBinary {
  Add
  Sub
  Mul
} derive(Eq, Debug)

///|
pub(all) enum AArch64FloatCondition {
  Equal
  NotEqual
  LessThan
  LessOrEqual
  GreaterThan
  GreaterOrEqual
  Ordered
  Unordered
} derive(Eq, Debug)

///|
pub(all) enum AArch64FloatTrapCondition {
  Unordered
  LessThan
  LessOrEqual
  GreaterOrEqual
} derive(Eq, Debug)

///|
pub(all) enum AArch64Address {
  Code(@semantic.CodeSymbol)
  External(@semantic.ExternalSymbol)
  Data(@semantic.DataSymbol)
} derive(Eq, Debug)

///|
pub(all) enum AArch64Conversion {
  WrapI64ToI32
  ExtendI32ToI64(@semantic.Signedness)
  SignExtend(@semantic.IntegerType, @semantic.AccessWidth)
  DemoteF64ToF32
  PromoteF32ToF64
  Bitcast(@semantic.ValueType, @semantic.ValueType)
  IntToFloat(@semantic.IntegerType, @semantic.FloatType, @semantic.Signedness)
  FloatToInt(@semantic.FloatType, @semantic.IntegerType, @semantic.Signedness)
} derive(Eq, Debug)

///|
pub struct AArch64StackObject {
  offset : Int
  size : Int
  alignment : Int
  area_size : Int
  area_alignment : Int
} derive(Eq, Debug)

///|
pub fn AArch64StackObject::new(
  offset : Int,
  size : Int,
  alignment : Int,
  area_size : Int,
  area_alignment : Int,
) -> AArch64StackObject {
  { offset, size, alignment, area_size, area_alignment }
}

///|
fn is_power_of_two(value : Int) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}

///|
fn AArch64StackObject::is_valid(self : AArch64StackObject) -> Bool {
  self.offset >= 0 &&
  self.size > 0 &&
  is_power_of_two(self.alignment) &&
  self.offset % self.alignment == 0 &&
  self.area_size >= self.offset + self.size &&
  is_power_of_two(self.area_alignment) &&
  self.area_alignment >= self.alignment &&
  self.area_size % self.area_alignment == 0
}

///|
pub(all) enum AArch64Inst {
  IncomingReg(@semantic.ValueType, @vcode.PhysicalReg)
  IncomingStack(@semantic.ValueType, Int)
  IncomingCallResult(@semantic.ValueType, @vcode.PhysicalReg)
  OutgoingReg(@semantic.ValueType, @vcode.PhysicalReg)
  KeepAlive(@semantic.ValueType)
  LoadConstant(GprWidth, UInt64)
  LoadVectorConstant(UInt64, UInt64)
  LoadNull(@semantic.ValueType)
  LoadAddress(AArch64Address)
  StackAddress(AArch64StackObject)
  LoadFloatConstant(@semantic.ValueType, UInt64)
  Move(@semantic.ValueType)
  CarrierMove(@semantic.ValueType, @semantic.ValueType)
  Select(@semantic.ValueType)
  VectorSelect
  VectorSplat(@semantic.VectorLane)
  VectorExtractLane(@semantic.VectorLane, Int, @semantic.Signedness?)
  VectorReplaceLane(@semantic.VectorLane, Int)
  VectorShuffle(FixedArray[Int])
  VectorSwizzle
  VectorBitwise(@semantic.VectorBitwiseOp)
  VectorIntUnary(@semantic.VectorLane, AArch64VectorIntUnary)
  VectorIntBinary(@semantic.VectorLane, AArch64VectorIntBinary)
  VectorIntShift(@semantic.VectorLane, @semantic.VectorIntShiftOp)
  VectorIntCompare(@semantic.VectorLane, @semantic.VectorIntComparison)
  IntUnary(GprWidth, AArch64IntUnary)
  IntBinary(GprWidth, AArch64IntBinary)
  PopulationCount(GprWidth)
  IntHighMultiply(GprWidth, @semantic.Signedness)
  IntWithOverflow(GprWidth, @semantic.IntOverflowOp)
  IntRemainder(GprWidth, @semantic.Signedness)
  TrapIfZero(GprWidth)
  TrapIfSignedDivOverflow(GprWidth)
  CompareSet(GprWidth, AArch64Condition)
  ReferenceCompareSet(@semantic.ValueType, AArch64Condition)
  FloatUnary(@semantic.ValueType, AArch64FloatUnary)
  FloatBinary(@semantic.ValueType, AArch64FloatBinary)
  FloatTernary(@semantic.ValueType, AArch64FloatTernary)
  FloatCompareSet(@semantic.ValueType, AArch64FloatCondition)
  TrapIfFloat(@semantic.ValueType, AArch64FloatTrapCondition)
  Convert(AArch64Conversion)
  AddAddress
  ScalarLoad(
    @semantic.AccessWidth,
    @semantic.LoadExtension,
    @semantic.ValueType,
    UInt64
  )
  ScalarStore(@semantic.AccessWidth, @semantic.ValueType, UInt64)
  PlatformCall(@semantic.ExternalSymbol, @semantic.Signature)
  InternalCall(@semantic.CodeSymbol, @semantic.Signature, InternalCallPlan)
  InternalCallIndirect(@semantic.Signature, InternalCallPlan)
  TailCallDirect(@semantic.CodeSymbol, @semantic.Signature, InternalCallPlan)
  TailCallIndirect(@semantic.Signature, InternalCallPlan)
  Jump
  BranchNonZero32
  Return
} derive(Eq, Debug)

///|
pub suberror TargetVCodeVerifyError {
  CommonFailure(cause~ : @vcode.VCodeVerifyError)
  InvalidInstruction(instruction~ : @vcode.Instruction, message~ : String)
} derive(Eq, Debug)

///|
pub impl Show for TargetVCodeVerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn require_fixed_use(
  function : @vcode.Function[AArch64Inst],
  instruction : @vcode.Instruction,
  operand_index : Int,
  expected : @vcode.PhysicalReg,
) -> Unit raise TargetVCodeVerifyError {
  let operand = function
    .instruction_operand_at(instruction, operand_index)
    .unwrap()
  if operand.constraint != Fixed(expected) {
    raise InvalidInstruction(
      instruction~,
      message="operand does not use the required ABI register",
    )
  }
}

///|
enum CallArgumentLocation {
  CallRegister(@vcode.PhysicalReg)
  CallStack(Int)
} derive(Eq, Debug)

///|
struct CallLayout {
  arguments : Array[CallArgumentLocation]
  stack_size : Int
} derive(Eq, Debug)

///|
fn call_align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}

///|
fn call_stack_size(ty : @semantic.ValueType) -> Int {
  if ty == V128 {
    16
  } else {
    8
  }
}

///|
fn platform_call_layout(types : Array[@semantic.ValueType]) -> CallLayout {
  let arguments : Array[CallArgumentLocation] = []
  let mut int_index = 0
  let mut fp_index = 0
  let mut stack_size = 0
  for ty in types {
    let class = @vcode.reg_class_for_value_type(ty)
    let index = if class == Int {
      let current = int_index
      int_index += 1
      current
    } else {
      let current = fp_index
      fp_index += 1
      current
    }
    if index < 8 {
      arguments.push(CallRegister(@vcode.PhysicalReg::new(index, class)))
    } else {
      let alignment = call_stack_size(ty)
      stack_size = call_align_up(stack_size, alignment)
      arguments.push(CallStack(stack_size))
      stack_size += alignment
    }
  }
  { arguments, stack_size: call_align_up(stack_size, 16) }
}

///|
fn platform_result_registers(
  types : Array[@semantic.ValueType],
) -> Array[@vcode.PhysicalReg] {
  let registers : Array[@vcode.PhysicalReg] = []
  let mut int_index = 0
  let mut fp_index = 0
  for ty in types {
    let class = @vcode.reg_class_for_value_type(ty)
    let index = if class == Int {
      let current = int_index
      int_index += 1
      current
    } else {
      let current = fp_index
      fp_index += 1
      current
    }
    registers.push(@vcode.PhysicalReg::new(index, class))
  }
  registers
}

///|
fn platform_call_clobbers() -> Array[@vcode.PhysicalReg] {
  let clobbers : Array[@vcode.PhysicalReg] = []
  for index in 0..<18 {
    clobbers.push(@vcode.PhysicalReg::new(index, Int))
  }
  // The unified FP/vector bank must conservatively treat v8-v15 as clobbered:
  // AAPCS64 preserves only their low 64 bits, not a complete V128 value.
  for index in 0..<32 {
    clobbers.push(@vcode.PhysicalReg::new(index, FpVector))
  }
  clobbers
}

///|
fn require_instruction_shape(
  function : @vcode.Function[AArch64Inst],
  instruction : @vcode.Instruction,
  use_types : Array[@semantic.ValueType],
  def_types : Array[@semantic.ValueType],
  terminator : Bool,
  successor_count : Int,
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
    if function.value_type(operand.value) != Some(use_types[index]) {
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
fn incoming_stack_capacity(function : @vcode.Function[AArch64Inst]) -> Int {
  let mut size = 0
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    if function.instruction(instruction) is Some(IncomingStack(ty, offset)) {
      let end = offset + call_stack_size(ty)
      if end > size {
        size = end
      }
    }
  }
  call_align_up(size, 16)
}

///|
fn require_tail_call_plan(
  function : @vcode.Function[AArch64Inst],
  instruction : @vcode.Instruction,
  signature : @semantic.Signature,
  plan : InternalCallPlan,
  indirect : Bool,
) -> Unit raise TargetVCodeVerifyError {
  if plan.arguments.length() != signature.params.length() ||
    plan.results.length() != signature.results.length() ||
    plan.stack_size < 0 ||
    plan.stack_size % 16 != 0 ||
    plan.stack_size > incoming_stack_capacity(function) ||
    signature.results != function.result_types() {
    raise InvalidInstruction(
      instruction~,
      message="tail-call plan is not compatible with the current function",
    )
  }
  let use_types : Array[@semantic.ValueType] = if indirect {
    [Ptr64, ..signature.params]
  } else {
    signature.params.copy()
  }
  require_instruction_shape(function, instruction, use_types, [], true, 0)
  for operand in function.instruction_operands(instruction) {
    if operand.constraint != Any {
      raise InvalidInstruction(
        instruction~,
        message="tail-call operands must remain allocatable before ABI moves",
      )
    }
  }
  if function.instruction_clobbers(instruction) != platform_call_clobbers() {
    raise InvalidInstruction(
      instruction~,
      message="tail call has an invalid caller-saved clobber set",
    )
  }
}

///|
fn integer_type(width : GprWidth) -> @semantic.ValueType {
  match width {
    W32 => I32
    W64 => I64
  }
}

///|
fn valid_scalar_load(
  width : @semantic.AccessWidth,
  extension : @semantic.LoadExtension,
  result_type : @semantic.ValueType,
) -> Bool {
  match (result_type, width, extension) {
    (I32, W8 | W16, Signed | Unsigned) | (I32, W32, None) => true
    (I64, W8 | W16 | W32, Signed | Unsigned) | (I64, W64, None) => true
    (Ptr64 | GcRef64, W64, None) => true
    (F32, W32, None) | (F64, W64, None) => true
    _ => false
  }
}

///|
fn valid_scalar_store(
  width : @semantic.AccessWidth,
  value_type : @semantic.ValueType,
) -> Bool {
  match (value_type, width) {
    (I32, W8 | W16 | W32) => true
    (I64, W8 | W16 | W32 | W64) => true
    (Ptr64 | GcRef64, W64) => true
    (F32, W32) | (F64, W64) => true
    _ => false
  }
}

///|
fn vector_lane_scalar_type(lane : @semantic.VectorLane) -> @semantic.ValueType {
  match lane {
    I8x16 | I16x8 | I32x4 => I32
    I64x2 => I64
    F32x4 => F32
    F64x2 => F64
  }
}

///|
fn vector_lane_count(lane : @semantic.VectorLane) -> Int {
  match lane {
    I8x16 => 16
    I16x8 => 8
    I32x4 | F32x4 => 4
    I64x2 | F64x2 => 2
  }
}

///|
fn is_integer_vector_lane(lane : @semantic.VectorLane) -> Bool {
  match lane {
    I8x16 | I16x8 | I32x4 | I64x2 => true
    F32x4 | F64x2 => false
  }
}

///|
fn valid_scalar_bitcast(
  from : @semantic.ValueType,
  to : @semantic.ValueType,
) -> Bool {
  match (from, to) {
    (I32, I32 | F32) | (F32, I32 | F32) => true
    (I64, I64 | Ptr64 | F64)
    | (Ptr64, I64 | Ptr64 | F64)
    | (F64, I64 | Ptr64 | F64) => true
    _ => false
  }
}

///|
fn conversion_shape(
  conversion : AArch64Conversion,
) -> (@semantic.ValueType, @semantic.ValueType)? {
  match conversion {
    WrapI64ToI32 => Some((I64, I32))
    ExtendI32ToI64(_) => Some((I32, I64))
    SignExtend(I32, W8 | W16) => Some((I32, I32))
    SignExtend(I64, W8 | W16 | W32) => Some((I64, I64))
    DemoteF64ToF32 => Some((F64, F32))
    PromoteF32ToF64 => Some((F32, F64))
    Bitcast(from, to) =>
      if valid_scalar_bitcast(from, to) {
        Some((from, to))
      } else {
        None
      }
    IntToFloat(I32, F32, _) => Some((I32, F32))
    IntToFloat(I32, F64, _) => Some((I32, F64))
    IntToFloat(I64, F32, _) => Some((I64, F32))
    IntToFloat(I64, F64, _) => Some((I64, F64))
    FloatToInt(F32, I32, _) => Some((F32, I32))
    FloatToInt(F32, I64, _) => Some((F32, I64))
    FloatToInt(F64, I32, _) => Some((F64, I32))
    FloatToInt(F64, I64, _) => Some((F64, I64))
    _ => None
  }
}

///|
pub fn verify_vcode(
  function : @vcode.Function[AArch64Inst],
) -> Unit raise TargetVCodeVerifyError {
  @vcode.verify_selected(function) catch {
    error => raise CommonFailure(cause=error)
  }
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    match function.instruction(instruction).unwrap() {
      IncomingReg(ty, reg) => {
        if reg.class != @vcode.reg_class_for_value_type(ty) {
          raise InvalidInstruction(
            instruction~,
            message="incoming register class does not match value type",
          )
        }
        require_instruction_shape(function, instruction, [ty], [ty], false, 0)
        require_fixed_use(function, instruction, 0, reg)
      }
      IncomingStack(ty, offset) => {
        if offset < 0 || offset % 8 != 0 {
          raise InvalidInstruction(
            instruction~,
            message="incoming stack offset must be non-negative and 8-byte aligned",
          )
        }
        require_instruction_shape(function, instruction, [], [ty], false, 0)
      }
      IncomingCallResult(ty, reg) => {
        if reg.class != @vcode.reg_class_for_value_type(ty) {
          raise InvalidInstruction(
            instruction~,
            message="call result register class does not match value type",
          )
        }
        require_instruction_shape(function, instruction, [], [ty], false, 0)
      }
      LoadConstant(width, bits) => {
        if width == W32 && bits > 0xFFFFFFFFUL {
          raise InvalidInstruction(
            instruction~,
            message="32-bit constant has non-zero high bits",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [],
          [integer_type(width)],
          false,
          0,
        )
      }
      LoadVectorConstant(_, _) =>
        require_instruction_shape(function, instruction, [], [V128], false, 0)
      LoadNull(ty) => {
        if ty != Ptr64 && ty != GcRef64 {
          raise InvalidInstruction(
            instruction~,
            message="null materialization requires ptr64 or gcref64",
          )
        }
        require_instruction_shape(function, instruction, [], [ty], false, 0)
      }
      LoadAddress(_) =>
        require_instruction_shape(function, instruction, [], [Ptr64], false, 0)
      StackAddress(object) => {
        if !object.is_valid() {
          raise InvalidInstruction(
            instruction~,
            message="invalid target stack-object descriptor",
          )
        }
        require_instruction_shape(function, instruction, [], [Ptr64], false, 0)
      }
      LoadFloatConstant(ty, bits) => {
        if (ty != F32 && ty != F64) || (ty == F32 && bits > 0xFFFFFFFFUL) {
          raise InvalidInstruction(
            instruction~,
            message="invalid scalar floating-point constant",
          )
        }
        require_instruction_shape(function, instruction, [], [ty], false, 0)
      }
      OutgoingReg(ty, reg) => {
        if reg.class != @vcode.reg_class_for_value_type(ty) {
          raise InvalidInstruction(
            instruction~,
            message="outgoing register class does not match value type",
          )
        }
        require_instruction_shape(function, instruction, [ty], [], false, 0)
      }
      KeepAlive(ty) =>
        require_instruction_shape(function, instruction, [ty], [], false, 0)
      Move(ty) =>
        require_instruction_shape(function, instruction, [ty], [ty], false, 0)
      CarrierMove(from, to) => {
        if !((from == GcRef64 && to == Ptr64) || (from == I64 && to == GcRef64)) {
          raise InvalidInstruction(
            instruction~,
            message="carrier move requires gcref64-to-ptr64 or i64-to-gcref64",
          )
        }
        require_instruction_shape(function, instruction, [from], [to], false, 0)
      }
      Select(ty) => {
        if ty == V128 {
          raise InvalidInstruction(
            instruction~,
            message="scalar select does not accept v128",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [I32, ty, ty],
          [ty],
          false,
          0,
        )
      }
      VectorSelect =>
        require_instruction_shape(
          function,
          instruction,
          [I32, V128, V128],
          [V128],
          false,
          0,
        )
      VectorSplat(lane) =>
        require_instruction_shape(
          function,
          instruction,
          [vector_lane_scalar_type(lane)],
          [V128],
          false,
          0,
        )
      VectorExtractLane(lane, index, extension) => {
        let requires_extension = lane == I8x16 || lane == I16x8
        let has_extension = extension is Some(_)
        if index < 0 ||
          index >= vector_lane_count(lane) ||
          requires_extension != has_extension {
          raise InvalidInstruction(
            instruction~,
            message="invalid vector lane extraction contract",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [V128],
          [vector_lane_scalar_type(lane)],
          false,
          0,
        )
      }
      VectorReplaceLane(lane, index) => {
        if index < 0 || index >= vector_lane_count(lane) {
          raise InvalidInstruction(
            instruction~,
            message="invalid vector lane replacement index",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [V128, vector_lane_scalar_type(lane)],
          [V128],
          false,
          0,
        )
        if function.instruction_operand_at(instruction, 2).unwrap().constraint !=
          TiedTo(0) {
          raise InvalidInstruction(
            instruction~,
            message="vector lane replacement result must be tied to its source vector",
          )
        }
      }
      VectorShuffle(mask) => {
        if mask.length() != 16 {
          raise InvalidInstruction(
            instruction~,
            message="vector shuffle requires exactly 16 lane indices",
          )
        }
        for lane in mask {
          if lane < 0 || lane >= 32 {
            raise InvalidInstruction(
              instruction~,
              message="vector shuffle lane index is out of range",
            )
          }
        }
        require_instruction_shape(
          function,
          instruction,
          [V128, V128],
          [V128],
          false,
          0,
        )
      }
      VectorSwizzle =>
        require_instruction_shape(
          function,
          instruction,
          [V128, V128],
          [V128],
          false,
          0,
        )
      VectorIntUnary(lane, _) => {
        if !is_integer_vector_lane(lane) {
          raise InvalidInstruction(
            instruction~,
            message="vector integer unary operation requires integer lanes",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [V128],
          [V128],
          false,
          0,
        )
      }
      VectorIntBinary(lane, _) => {
        if !is_integer_vector_lane(lane) {
          raise InvalidInstruction(
            instruction~,
            message="vector integer binary operation requires integer lanes",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [V128, V128],
          [V128],
          false,
          0,
        )
      }
      VectorIntShift(lane, _) => {
        if !is_integer_vector_lane(lane) {
          raise InvalidInstruction(
            instruction~,
            message="vector integer shift requires integer lanes",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [V128, I32],
          [V128],
          false,
          0,
        )
      }
      VectorIntCompare(lane, _) => {
        if !is_integer_vector_lane(lane) {
          raise InvalidInstruction(
            instruction~,
            message="vector integer comparison requires integer lanes",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [V128, V128],
          [V128],
          false,
          0,
        )
      }
      VectorBitwise(operation) => {
        let arity = match operation {
          Not => 1
          And | Or | Xor | AndNot => 2
          BitSelect => 3
        }
        require_instruction_shape(
          function,
          instruction,
          Array::make(arity, V128),
          [V128],
          false,
          0,
        )
      }
      IntUnary(width, _) => {
        let ty = integer_type(width)
        require_instruction_shape(function, instruction, [ty], [ty], false, 0)
      }
      IntBinary(width, _) => {
        let ty = integer_type(width)
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [ty],
          false,
          0,
        )
      }
      PopulationCount(width) => {
        let ty = integer_type(width)
        require_instruction_shape(function, instruction, [ty], [ty], false, 0)
      }
      IntHighMultiply(width, _) => {
        let ty = integer_type(width)
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [ty],
          false,
          0,
        )
      }
      IntWithOverflow(width, _) => {
        let ty = integer_type(width)
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [ty, I32],
          false,
          0,
        )
      }
      IntRemainder(width, _) => {
        let ty = integer_type(width)
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [ty],
          false,
          0,
        )
      }
      TrapIfZero(width) => {
        let ty = integer_type(width)
        if function.instruction_metadata(instruction).unwrap().trap !=
          Some(IntegerDivisionByZero) {
          raise InvalidInstruction(
            instruction~,
            message="zero-divisor check requires division-by-zero trap metadata",
          )
        }
        require_instruction_shape(function, instruction, [ty], [], false, 0)
      }
      TrapIfSignedDivOverflow(width) => {
        let ty = integer_type(width)
        if function.instruction_metadata(instruction).unwrap().trap !=
          Some(IntegerOverflow) {
          raise InvalidInstruction(
            instruction~,
            message="signed-division check requires overflow trap metadata",
          )
        }
        require_instruction_shape(function, instruction, [ty, ty], [], false, 0)
      }
      CompareSet(width, _) => {
        let ty = integer_type(width)
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [I32],
          false,
          0,
        )
      }
      ReferenceCompareSet(ty, _) => {
        if ty != Ptr64 && ty != GcRef64 {
          raise InvalidInstruction(
            instruction~,
            message="reference comparison requires ptr64 or gcref64",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [I32],
          false,
          0,
        )
      }
      FloatUnary(ty, _) => {
        if ty != F32 && ty != F64 {
          raise InvalidInstruction(
            instruction~,
            message="scalar floating-point unary operation requires f32 or f64",
          )
        }
        require_instruction_shape(function, instruction, [ty], [ty], false, 0)
      }
      FloatBinary(ty, _) => {
        if ty != F32 && ty != F64 {
          raise InvalidInstruction(
            instruction~,
            message="scalar floating-point binary operation requires f32 or f64",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [ty],
          false,
          0,
        )
      }
      FloatTernary(ty, _) => {
        if ty != F32 && ty != F64 {
          raise InvalidInstruction(
            instruction~,
            message="scalar floating-point ternary operation requires f32 or f64",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [ty, ty, ty],
          [ty],
          false,
          0,
        )
      }
      FloatCompareSet(ty, _) => {
        if ty != F32 && ty != F64 {
          raise InvalidInstruction(
            instruction~,
            message="scalar floating-point comparison requires f32 or f64",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [ty, ty],
          [I32],
          false,
          0,
        )
      }
      TrapIfFloat(ty, condition) => {
        if (ty != F32 && ty != F64) ||
          function.instruction_metadata(instruction).unwrap().trap !=
          Some(InvalidConversionToInteger) {
          raise InvalidInstruction(
            instruction~,
            message="float trap check requires a scalar float and invalid-conversion metadata",
          )
        }
        let uses = if condition == Unordered { [ty] } else { [ty, ty] }
        require_instruction_shape(function, instruction, uses, [], false, 0)
      }
      Convert(conversion) => {
        guard conversion_shape(conversion) is Some((source, result)) else {
          raise InvalidInstruction(
            instruction~,
            message="invalid AArch64 scalar conversion",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [source],
          [result],
          false,
          0,
        )
      }
      AddAddress =>
        require_instruction_shape(
          function,
          instruction,
          [Ptr64, I64],
          [Ptr64],
          false,
          0,
        )
      ScalarLoad(width, extension, result_type, _) => {
        if !valid_scalar_load(width, extension, result_type) {
          raise InvalidInstruction(
            instruction~,
            message="invalid AArch64 scalar load type or extension",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [Ptr64],
          [result_type],
          false,
          0,
        )
      }
      ScalarStore(width, value_type, _) => {
        if !valid_scalar_store(width, value_type) {
          raise InvalidInstruction(
            instruction~,
            message="invalid AArch64 scalar store type or width",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [Ptr64, value_type],
          [],
          false,
          0,
        )
      }
      PlatformCall(_, signature) => {
        if signature.results.length() > 1 {
          raise InvalidInstruction(
            instruction~,
            message="platform call supports at most one direct result",
          )
        }
        let argument_layout = platform_call_layout(signature.params)
        let result_registers = platform_result_registers(signature.results)
        require_instruction_shape(
          function,
          instruction,
          signature.params,
          [],
          false,
          0,
        )
        ignore(argument_layout)
        for operand in function.instruction_operands(instruction) {
          if operand.constraint != Any {
            raise InvalidInstruction(
              instruction~,
              message="direct call arguments must remain allocatable before ABI moves",
            )
          }
        }
        ignore(result_registers)
        if function.instruction_clobbers(instruction) !=
          platform_call_clobbers() {
          raise InvalidInstruction(
            instruction~,
            message="platform call has an invalid caller-saved clobber set",
          )
        }
      }
      InternalCall(_, signature, plan) => {
        if plan.arguments.length() != signature.params.length() ||
          plan.results.length() != signature.results.length() ||
          plan.stack_size < 0 ||
          plan.stack_size % 16 != 0 {
          raise InvalidInstruction(
            instruction~,
            message="internal call plan does not match its signature",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          signature.params,
          [],
          false,
          0,
        )
        for index, ty in signature.params {
          match plan.arguments[index] {
            CallRegister(reg) =>
              if reg.id < 0 ||
                reg.id >= 16 ||
                reg.class != @vcode.reg_class_for_value_type(ty) {
                raise InvalidInstruction(
                  instruction~,
                  message="internal call has an invalid argument register",
                )
              }
            CallStack(offset) => {
              let size = call_stack_size(ty)
              if offset < 0 ||
                offset % size != 0 ||
                offset + size > plan.stack_size {
                raise InvalidInstruction(
                  instruction~,
                  message="internal call has an invalid stack argument",
                )
              }
            }
          }
        }
        for index, ty in signature.results {
          let reg = plan.results[index]
          if reg.id < 0 ||
            reg.id >= 16 ||
            reg.class != @vcode.reg_class_for_value_type(ty) {
            raise InvalidInstruction(
              instruction~,
              message="internal call has an invalid result register",
            )
          }
        }
        for operand in function.instruction_operands(instruction) {
          if operand.constraint != Any {
            raise InvalidInstruction(
              instruction~,
              message="internal call arguments must remain allocatable before ABI moves",
            )
          }
        }
        if function.instruction_clobbers(instruction) !=
          platform_call_clobbers() {
          raise InvalidInstruction(
            instruction~,
            message="internal call has an invalid caller-saved clobber set",
          )
        }
      }
      InternalCallIndirect(signature, plan) => {
        if plan.arguments.length() != signature.params.length() ||
          plan.results.length() != signature.results.length() ||
          plan.stack_size < 0 ||
          plan.stack_size % 16 != 0 {
          raise InvalidInstruction(
            instruction~,
            message="indirect internal call plan does not match its signature",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [Ptr64, ..signature.params],
          [],
          false,
          0,
        )
        for index, ty in signature.params {
          match plan.arguments[index] {
            CallRegister(reg) =>
              if reg.id < 0 ||
                reg.id >= 16 ||
                reg.class != @vcode.reg_class_for_value_type(ty) {
                raise InvalidInstruction(
                  instruction~,
                  message="indirect call has an invalid argument register",
                )
              }
            CallStack(offset) => {
              let size = call_stack_size(ty)
              if offset < 0 ||
                offset % size != 0 ||
                offset + size > plan.stack_size {
                raise InvalidInstruction(
                  instruction~,
                  message="indirect call has an invalid stack argument",
                )
              }
            }
          }
        }
        for index, ty in signature.results {
          let reg = plan.results[index]
          if reg.id < 0 ||
            reg.id >= 16 ||
            reg.class != @vcode.reg_class_for_value_type(ty) {
            raise InvalidInstruction(
              instruction~,
              message="indirect call has an invalid result register",
            )
          }
        }
        for operand in function.instruction_operands(instruction) {
          if operand.constraint != Any {
            raise InvalidInstruction(
              instruction~,
              message="indirect call operands must remain allocatable before ABI moves",
            )
          }
        }
        if function.instruction_clobbers(instruction) !=
          platform_call_clobbers() {
          raise InvalidInstruction(
            instruction~,
            message="indirect call has an invalid caller-saved clobber set",
          )
        }
      }
      TailCallDirect(_, signature, plan) =>
        require_tail_call_plan(function, instruction, signature, plan, false)
      TailCallIndirect(signature, plan) =>
        require_tail_call_plan(function, instruction, signature, plan, true)
      Jump => require_instruction_shape(function, instruction, [], [], true, 1)
      BranchNonZero32 =>
        require_instruction_shape(function, instruction, [I32], [], true, 2)
      Return => {
        let operands = function.instruction_operands(instruction)
        if !function.instruction_is_terminator(instruction) ||
          function.instruction_successor_count(instruction) != 0 ||
          !operands.is_empty() {
          raise InvalidInstruction(instruction~, message="invalid return shape")
        }
      }
    }
  }
  for block in function.layout() {
    let body = function.block_body(block)
    let consumed_results = Array::make(body.length(), false)
    for index, instruction in body {
      let call_results = match function.instruction(instruction) {
        Some(PlatformCall(_, signature)) =>
          Some((signature, platform_result_registers(signature.results)))
        Some(InternalCall(_, signature, plan)) =>
          Some((signature, plan.results))
        Some(InternalCallIndirect(signature, plan)) =>
          Some((signature, plan.results))
        _ => None
      }
      if call_results is Some((signature, registers)) {
        for result_index, ty in signature.results {
          let body_index = index + result_index + 1
          if body_index >= body.length() ||
            function.instruction(body[body_index]) !=
            Some(IncomingCallResult(ty, registers[result_index])) {
            raise InvalidInstruction(
              instruction~,
              message="direct call results are not materialized in ABI order",
            )
          }
          consumed_results[body_index] = true
        }
      }
    }
    for index, instruction in body {
      if function.instruction(instruction) is Some(IncomingCallResult(_, _)) &&
        !consumed_results[index] {
        raise InvalidInstruction(
          instruction~,
          message="call result is not attached to a preceding direct call",
        )
      }
    }
  }
  for block in function.layout() {
    let terminator = function.block_terminator(block).unwrap()
    if function.instruction(terminator) == Some(Return) {
      let body = function.block_body(block)
      let result_types = function.result_types()
      if body.length() < result_types.length() {
        raise InvalidInstruction(
          instruction=terminator,
          message="return is missing ABI result materialization",
        )
      }
      let start = body.length() - result_types.length()
      for result_index, ty in result_types {
        let valid = match function.instruction(body[start + result_index]) {
          Some(OutgoingReg(actual_ty, _)) => actual_ty == ty
          _ => false
        }
        if !valid {
          raise InvalidInstruction(
            instruction=terminator,
            message="return ABI materialization does not match function signature",
          )
        }
      }
    }
  }
}
