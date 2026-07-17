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
        let result_types = function.result_types()
        if !function.instruction_is_terminator(instruction) ||
          function.instruction_successor_count(instruction) != 0 ||
          operands.length() != result_types.length() ||
          operands.any(operand => operand.role != Use) {
          raise InvalidInstruction(instruction~, message="invalid return shape")
        }
        for result_index, operand in operands {
          if function.value_type(operand.value) !=
            Some(result_types[result_index]) {
            raise InvalidInstruction(
              instruction~,
              message="return value type does not match function signature",
            )
          }
        }
      }
    }
  }
}
