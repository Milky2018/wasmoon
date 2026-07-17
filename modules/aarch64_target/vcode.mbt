///|
pub(all) enum GprWidth {
  W32
  W64
} derive(Eq, Debug)

///|
pub(all) enum AArch64IntUnary {
  Mvn
  Clz
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
pub(all) enum AArch64Inst {
  IncomingReg(@semantic.ValueType, @vcode.PhysicalReg)
  IncomingStack(@semantic.ValueType, Int)
  OutgoingReg(@semantic.ValueType, @vcode.PhysicalReg)
  LoadConstant(GprWidth, UInt64)
  Move(@semantic.ValueType)
  IntUnary(GprWidth, AArch64IntUnary)
  IntBinary(GprWidth, AArch64IntBinary)
  CompareSet(GprWidth, AArch64Condition)
  AddAddress
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
fn integer_type(width : GprWidth) -> @semantic.ValueType {
  match width {
    W32 => I32
    W64 => I64
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
      OutgoingReg(ty, reg) => {
        if reg.class != @vcode.reg_class_for_value_type(ty) {
          raise InvalidInstruction(
            instruction~,
            message="outgoing register class does not match value type",
          )
        }
        require_instruction_shape(function, instruction, [ty], [], false, 0)
      }
      Move(ty) =>
        require_instruction_shape(function, instruction, [ty], [ty], false, 0)
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
      AddAddress =>
        require_instruction_shape(
          function,
          instruction,
          [Ptr64, I64],
          [Ptr64],
          false,
          0,
        )
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
      let mut int_index = 0
      let mut fp_index = 0
      let start = body.length() - result_types.length()
      for result_index, ty in result_types {
        let expected_id = if @vcode.reg_class_for_value_type(ty) == Int {
          let index = int_index
          int_index += 1
          index
        } else {
          let index = fp_index
          fp_index += 1
          index
        }
        let expected = OutgoingReg(
          ty,
          @vcode.PhysicalReg::new(
            expected_id,
            @vcode.reg_class_for_value_type(ty),
          ),
        )
        if function.instruction(body[start + result_index]) != Some(expected) {
          raise InvalidInstruction(
            instruction=terminator,
            message="return ABI materialization does not match function signature",
          )
        }
      }
    }
  }
}
