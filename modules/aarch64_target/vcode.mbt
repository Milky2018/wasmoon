///|
pub(all) enum AArch64Inst {
  Nop
  Move64
  Add64
  AddShifted64(Int)
  BranchNonZero
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
) -> Unit raise TargetVCodeVerifyError {
  let operands = function.instruction_operands(instruction)
  let uses = operands.filter(operand => operand.role == Use)
  let defs = operands.filter(operand => operand.role == Def)
  if uses.length() != use_types.length() ||
    defs.length() != def_types.length() ||
    function.instruction_is_terminator(instruction) != terminator {
    raise InvalidInstruction(
      instruction~,
      message="invalid operand or placement shape",
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
pub fn verify_vcode(
  function : @vcode.Function[AArch64Inst],
) -> Unit raise TargetVCodeVerifyError {
  @vcode.verify_selected(function) catch {
    error => raise CommonFailure(cause=error)
  }
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    match function.instruction(instruction).unwrap() {
      Nop => require_instruction_shape(function, instruction, [], [], false)
      Move64 =>
        require_instruction_shape(function, instruction, [I64], [I64], false)
      Add64 =>
        require_instruction_shape(
          function,
          instruction,
          [I64, I64],
          [I64],
          false,
        )
      AddShifted64(amount) => {
        if amount < 0 || amount >= 64 {
          raise InvalidInstruction(
            instruction~,
            message="shift must be in 0..<64",
          )
        }
        require_instruction_shape(
          function,
          instruction,
          [I64, I64],
          [I64],
          false,
        )
      }
      BranchNonZero =>
        require_instruction_shape(function, instruction, [I64], [], true)
      Return => {
        let operands = function.instruction_operands(instruction)
        if !function.instruction_is_terminator(instruction) ||
          operands.any(operand => operand.role != Use) {
          raise InvalidInstruction(instruction~, message="invalid return shape")
        }
      }
    }
  }
}
