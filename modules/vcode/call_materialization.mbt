///|
fn abi_home_output(
  ty : @native.ValueType,
  reg : PhysicalReg,
  is_allocatable : (PhysicalReg) -> Bool,
) -> Output {
  let output = Output::any_location(ty)
  if is_allocatable(reg) {
    output.with_preference(reg)
  } else {
    output
  }
}

///|
/// Materialize ABI inputs into stable homes using the target's incoming
/// pseudos. These pseudos have no implicit clobbers.
pub fn[Inst] materialize_entry_arguments(
  builder : CheckedBuilder[Inst],
  types : Array[@native.ValueType],
  arguments : ArrayView[CallArgumentLocation],
  result_area_register : PhysicalReg?,
  incoming_register : (@native.ValueType, PhysicalReg) -> Inst,
  incoming_stack : (@native.ValueType, Int32) -> Inst,
  incoming_result_area : (PhysicalReg) -> Inst,
  is_allocatable : (PhysicalReg) -> Bool,
) -> (Array[Value], Value?) raise VCodeBuildError {
  let entry = builder.entry_block()
  // Batched emission captures registers before stack inputs. Keep this pointer
  // live across every input copy so their homes cannot alias its saved value.
  let result_area = match result_area_register {
    Some(reg) => {
      let (_, results) = builder.append_body(
        entry,
        incoming_result_area(reg),
        [],
        [Output::any_location(Ptr64)],
        [],
        InstructionMetadata::empty(),
      )
      Some(results[0])
    }
    None => None
  }
  let values : Array[Value] = []
  for index, ty in types {
    let raw = builder.parameter(index)
    let (instruction, inputs, output) = match arguments[index] {
      CallRegister(reg) => {
        let output = abi_home_output(ty, reg, is_allocatable)
        (incoming_register(ty, reg), [Input::fixed(raw, reg)], output)
      }
      CallStack(offset) =>
        (incoming_stack(ty, offset), [], Output::any_location(ty))
    }
    let (_, results) = builder.append_body(
      entry,
      instruction,
      inputs,
      [output],
      [],
      InstructionMetadata::empty(),
    )
    values.push(results[0])
  }

  (values, result_area)
}

///|
/// Materialize stable result homes before extending the call's root lifetimes.
/// The target provides its register, result-area, and keepalive pseudos.
pub fn[Inst] materialize_call_results(
  builder : CheckedBuilder[Inst],
  block : Block,
  result_types : Array[@native.ValueType],
  locations : ArrayView[CallResultLocation],
  live_gc_roots : Array[Value],
  incoming_register : (@native.ValueType, PhysicalReg) -> Inst,
  incoming_area : (@native.ValueType, Int32) -> Inst,
  keepalive : Inst,
  is_allocatable : (PhysicalReg) -> Bool,
) -> Array[Value] raise VCodeBuildError {
  let results : Array[Value] = []
  for index, ty in result_types {
    let (instruction, output) = match locations[index] {
      CallResultRegister(reg) =>
        (incoming_register(ty, reg), abi_home_output(ty, reg, is_allocatable))
      CallResultArea(offset, _) =>
        (incoming_area(ty, offset), Output::any_location(ty))
    }
    let (_, materialized) = builder.append_body(
      block,
      instruction,
      [],
      [output],
      [],
      InstructionMetadata::empty(),
    )
    results.push(materialized[0])
  }
  for root in live_gc_roots {
    builder.append_body(
      block,
      keepalive,
      [Input::any(root)],
      [],
      [],
      InstructionMetadata::empty(),
    )
    |> ignore
  }
  results
}

///|
pub(all) suberror CallMaterializationError {
  UnsupportedAbi(String)
  BuildFailure(VCodeBuildError)
}

///|
/// Place the values of a function's return using its ABI.
pub fn[Inst, Failure] DirectLoweringState::materialize_return_values(
  self : DirectLoweringState[Inst, Failure],
  block : Block,
  values : Array[Value],
  platform_result_registers : (Array[@native.ValueType]) -> Array[PhysicalReg],
  outgoing_register : (@native.ValueType, PhysicalReg) -> Inst,
  outgoing_area : (@native.ValueType, Int32) -> Inst,
) -> Unit raise CallMaterializationError {
  let types = self.signature.results
  let locations : ArrayView[CallResultLocation] = match self.protocol {
    Platform => {
      if types.length() > 1 {
        raise UnsupportedAbi(
          "platform functions support at most one direct result",
        )
      }
      platform_result_registers(types).map(reg => CallResultRegister(reg))
    }
    Internal => self.context.internal_abi.result_layout(types).0
  }
  for index, value in values {
    let ty = types[index]
    let (instruction, inputs) = match locations[index] {
      CallResultRegister(reg) =>
        (outgoing_register(ty, reg), [Input::any(value)])
      CallResultArea(offset, _) => {
        guard self.result_area is Some(address) else {
          raise UnsupportedAbi("internal result area is unavailable")
        }
        (outgoing_area(ty, offset), [Input::any(address), Input::any(value)])
      }
    }
    ignore(
      self.builder.append_body(
        block,
        instruction,
        inputs,
        [],
        [],
        InstructionMetadata::empty(),
      ) catch {
        error => raise BuildFailure(error)
      },
    )
  }
}

///|
/// Restore ABI types for erased raw-word bitcasts. Register allocation may
/// coalesce the copy, while spilled arguments retain correctly typed homes.
pub fn[Inst] CheckedBuilder::materialize_abi_words(
  self : CheckedBuilder[Inst],
  block : Block,
  operands : Array[Value],
  types : Array[@native.ValueType],
  make_move : (@native.ValueType) -> Inst,
  operand_start~ : Int32 = 0,
) -> Array[Value] raise VCodeBuildError {
  let mut materialized : Array[Value]? = None
  for index, expected in types {
    let operand_index = operand_start + index
    let value = operands[operand_index]
    let actual = self.value_type(value)
    if (expected == I64 && actual == Some(Ptr64)) ||
      (expected == Ptr64 && actual == Some(I64)) {
      let (_, results) = self.append_body(
        block,
        make_move(expected),
        [Input::any(value)],
        [Output::any(expected)],
        [],
        InstructionMetadata::empty(),
      )
      let values = match materialized {
        Some(values) => values
        None => {
          let values = operands.copy()
          materialized = Some(values)
          values
        }
      }
      values[operand_index] = results[0]
    }
  }
  materialized.unwrap_or(operands)
}

///|
pub fn call_argument_inputs(
  operands : Array[Value],
  locations : ArrayView[CallArgumentLocation],
  is_allocatable : (PhysicalReg) -> Bool,
) -> Array[Input] {
  operands.mapi((index, operand) => {
    let input = Input::any_location(operand)
    match locations[index] {
      CallRegister(reg) if is_allocatable(reg) => input.with_preference(reg)
      CallRegister(_) | CallStack(_) => input
    }
  })
}

///|
/// Registers in each ABI bank are assigned in result order.
pub fn platform_result_registers(
  types : Array[@native.ValueType],
  integer_registers? : ArrayView[Int32],
) -> Array[PhysicalReg] {
  let registers : Array[PhysicalReg] = []
  let mut int_index = 0
  let mut fp_index = 0
  for ty in types {
    let class = reg_class_for_value_type(ty)
    let index = if class == Int {
      let current = int_index
      int_index += 1
      match integer_registers {
        Some(indices) => indices[current]
        None => current
      }
    } else {
      let current = fp_index
      fp_index += 1
      current
    }
    registers.push(PhysicalReg::new(index, class))
  }
  registers
}

///|
/// Prepare internal tail-call arguments, including the caller's result area.
pub fn[Inst, Failure] DirectLoweringState::tail_call_inputs(
  self : DirectLoweringState[Inst, Failure],
  call : @native.NativeCall,
  operands : Array[Value],
  is_allocatable : (PhysicalReg) -> Bool,
) -> (InternalCallPlan, Array[Input]) raise CallMaterializationError {
  if self.protocol != Internal || call.protocol != Internal {
    raise UnsupportedAbi(
      "true tail calls require Internal caller and callee protocols",
    )
  }
  let plan = self.context.internal_abi.call_plan(call.signature) catch {
    error => raise UnsupportedAbi(error.to_string())
  }
  let operands = operands.copy()
  if plan.result_area_size > 0 {
    guard self.result_area is Some(address) else {
      raise UnsupportedAbi("tail-call result area is unavailable")
    }
    operands.push(address)
  }
  let start = match call.callee {
    Internal(_) => 0
    Indirect => 1
    External(_) =>
      raise UnsupportedAbi(
        "internal tail calls cannot target an external symbol",
      )
  }
  let inputs = call_argument_inputs(
    operands[start:start + call.signature.params.length()].to_owned(),
    plan.arguments,
    is_allocatable,
  )
  if start == 1 {
    inputs.insert(0, Input::any_location(operands[0]))
  }
  if plan.result_area_size > 0 {
    let input = Input::any_location(operands[inputs.length()])
    inputs.push(
      match plan.result_area_register() {
        Some(reg) if is_allocatable(reg) => input.with_preference(reg)
        _ => input
      },
    )
  }
  (plan, inputs)
}

///|
/// Materialize and validate a tail call with the target's instruction and clobbers.
pub fn[Inst, Failure] DirectLoweringState::emit_tail_call(
  self : DirectLoweringState[Inst, Failure],
  block : Block,
  call : @native.NativeCall,
  operands : Array[Value],
  metadata : InstructionMetadata,
  make_move : (@native.ValueType) -> Inst,
  is_allocatable : (PhysicalReg) -> Bool,
  select : (InternalCallPlan) -> (Inst, Array[PhysicalReg]),
) -> Unit raise CallMaterializationError {
  let operands = self.builder.materialize_abi_words(
    block,
    operands,
    call.signature.params,
    make_move,
    operand_start=if call.callee is Indirect { 1 } else { 0 },
  ) catch {
    error => raise BuildFailure(error)
  }
  let (plan, inputs) = self.tail_call_inputs(call, operands, is_allocatable)
  let (target, clobbers) = select(plan)
  let metadata = direct_source_metadata(
    metadata.source,
    None,
    metadata.live_gc_roots,
    call.behavior.semantics(),
  )
  (self.builder.set_terminator(block, target, inputs, [], clobbers, metadata)
  |> ignore) catch {
    error => raise BuildFailure(error)
  }
}
