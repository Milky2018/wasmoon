///|
pub fn[Inst] TargetInstructionVerifier::platform_call(
  self : TargetInstructionVerifier[Inst],
  signature : @native.Signature,
  layout : (Array[@native.ValueType]) -> CallLayout,
  is_allocatable : (PhysicalReg) -> Bool,
  clobbers : () -> Array[PhysicalReg],
) -> Unit raise TargetVCodeVerifyError {
  if signature.results.length() > 1 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="platform call supports at most one direct result",
    )
  }
  let arguments = layout(signature.params).arguments
  self.shape(signature.params, [])
  require_call_argument_inputs(
    self.function,
    self.instruction,
    0,
    arguments,
    is_allocatable,
  )
  if self.function.instruction_clobbers(self.instruction) != clobbers() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="platform call has an invalid caller-saved clobber set",
    )
  }
}

///|
pub fn[Inst] TargetInstructionVerifier::internal_call(
  self : TargetInstructionVerifier[Inst],
  signature : @native.Signature,
  plan : InternalCallPlan,
  indirect~ : Bool,
  is_allocatable : (PhysicalReg) -> Bool,
  clobbers : (InternalCallPlan) -> Array[PhysicalReg],
) -> Unit raise TargetVCodeVerifyError {
  if plan.arguments.length() != signature.params.length() ||
    !plan.valid_results(signature.results) ||
    plan.stack_size < 0 ||
    plan.stack_size % 16 != 0 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message=if indirect {
        "indirect internal call plan does not match its signature"
      } else {
        "internal call plan does not match its signature"
      },
    )
  }
  let uses : Array[@native.ValueType] = if indirect {
    [Ptr64, ..signature.params]
  } else {
    signature.params
  }
  self.shape(uses, [])
  let kind = if indirect { "indirect" } else { "internal" }
  for index, ty in signature.params {
    match plan.arguments[index] {
      CallRegister(reg) =>
        if reg.id < 0 ||
          reg.id >= 16 ||
          reg.class != reg_class_for_value_type(ty) {
          raise InvalidInstruction(
            instruction=self.instruction,
            message="\{kind} call has an invalid argument register",
          )
        }
      CallStack(offset) => {
        let size = call_stack_size(ty)
        if offset < 0 || offset % size != 0 || offset + size > plan.stack_size {
          raise InvalidInstruction(
            instruction=self.instruction,
            message="\{kind} call has an invalid stack argument",
          )
        }
      }
    }
  }
  if indirect {
    let callee = self.function
      .instruction_operand_at(self.instruction, 0)
      .unwrap()
    if callee.constraint != AnyLocation || callee.preference is Some(_) {
      raise InvalidInstruction(
        instruction=self.instruction,
        message="indirect callee must remain allocatable without a preference",
      )
    }
  }
  require_call_argument_inputs(
    self.function,
    self.instruction,
    if indirect {
      1
    } else {
      0
    },
    plan.arguments,
    is_allocatable,
  )
  if self.function.instruction_clobbers(self.instruction) != clobbers(plan) {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="\{kind} call has an invalid caller-saved clobber set",
    )
  }
}

///|
/// ABI roles used after checking every instruction's local operand shape.
pub(all) enum AbiMaterialization {
  Ordinary
  PlatformResults(@native.Signature)
  InternalResults(@native.Signature, InternalCallPlan)
  ForwardResultArea(Int32, indirect~ : Bool)
  ReceiveResultArea
  ReceiveRegisterResult(@native.ValueType, PhysicalReg)
  ReceiveAreaResult(@native.ValueType, Int32)
  ReturnRegisterResult(@native.ValueType)
  ReturnAreaResult(@native.ValueType)
  Return
}

///|
pub fn[Inst] verify_abi_materialization(
  function : Function[Inst],
  classify : (Inst) -> AbiMaterialization,
  platform_results : (Array[@native.ValueType]) -> Array[PhysicalReg],
) -> Unit raise TargetVCodeVerifyError {
  let mut incoming_result_area : Value? = None
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    match classify(function.instruction(instruction).unwrap()) {
      ReceiveResultArea => {
        let value = function.instruction_operand_at(instruction, 0).unwrap().value
        if incoming_result_area is Some(_) {
          raise InvalidInstruction(
            instruction~,
            message="function has more than one incoming result area",
          )
        }
        incoming_result_area = Some(value)
      }
      ReturnAreaResult(_) => {
        let address = function.instruction_operand_at(instruction, 0).unwrap().value
        if incoming_result_area != Some(address) {
          raise InvalidInstruction(
            instruction~,
            message="outgoing area result does not use the incoming result area",
          )
        }
      }
      ForwardResultArea(operand_index, indirect~) => {
        let address = function
          .instruction_operand_at(instruction, operand_index)
          .unwrap().value
        if incoming_result_area != Some(address) {
          raise InvalidInstruction(
            instruction~,
            message=if indirect {
              "indirect tail call does not forward the incoming result area"
            } else {
              "tail call does not forward the incoming result area"
            },
          )
        }
      }
      _ => ()
    }
  }
  for block in function.layout() {
    let body = function.block_body(block)
    let consumed_results = Array::make(body.length(), false)
    for index, instruction in body {
      let call_results : (@native.Signature, ArrayView[CallResultLocation])? = match
        classify(function.instruction(instruction).unwrap()) {
        PlatformResults(signature) =>
          Some(
            (
              signature,
              platform_results(signature.results).map(reg => {
                CallResultRegister(reg)
              })[:],
            ),
          )
        InternalResults(signature, plan) => Some((signature, plan.results))
        _ => None
      }
      if call_results is Some((signature, locations)) {
        for result_index, ty in signature.results {
          let body_index = index + result_index + 1
          let valid = if body_index < body.length() {
            let actual = classify(
              function.instruction(body[body_index]).unwrap(),
            )
            match (locations[result_index], actual) {
              (
                CallResultRegister(reg),
                ReceiveRegisterResult(actual_ty, actual_reg),
              ) => ty == actual_ty && reg == actual_reg
              (
                CallResultArea(offset, _),
                ReceiveAreaResult(actual_ty, actual_offset),
              ) => ty == actual_ty && offset == actual_offset
              _ => false
            }
          } else {
            false
          }
          if !valid {
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
      if classify(function.instruction(instruction).unwrap())
        is (ReceiveRegisterResult(_, _) | ReceiveAreaResult(_, _)) &&
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
    if classify(function.instruction(terminator).unwrap()) is Return {
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
        let valid = match
          classify(function.instruction(body[start + result_index]).unwrap()) {
          ReturnRegisterResult(actual_ty) | ReturnAreaResult(actual_ty) =>
            actual_ty == ty
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
