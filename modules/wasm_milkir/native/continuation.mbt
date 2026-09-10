///|
fn continuation_call(
  context : @adapter.InstructionContext,
  environment : Environment,
  helper : @wasm_milkir.WasmRuntimeHelper,
  arguments : Array[@lowering.Value],
  params : Array[@native_types.ValueType],
  results : Array[@native_types.ValueType],
) -> Array[@lowering.Value] {
  context.emit_call(
    @native_types.NativeCall::new(
      External((environment.runtime_symbol)(helper)),
      @native_types.Signature::new(params, results),
      Platform,
      @native_types.CallBehavior::conservative(),
    ),
    arguments,
    results,
  )
}

///|
fn lower_cont_new(
  context : @adapter.InstructionContext,
  environment : Environment,
  index : Int,
) -> Unit {
  let args = context.environment()
  args.push(i32_immediate(context, index))
  args.append(context.operands())
  context.forward_results(
    continuation_call(
      context,
      environment,
      ContNew,
      args,
      [Ptr64, I32, GcRef64],
      [GcRef64],
    ),
  )
}

///|
fn lower_cont_bind(
  context : @adapter.InstructionContext,
  environment : Environment,
  input : Int,
) -> Unit {
  let values = context.operands()
  let types = context.operand_types()
  let (buffer, words) = emit_payload_word_buffer(
    context,
    values[1:].to_owned(),
    types[1:].to_owned(),
  )
  let args = context.environment()
  args.append([
    i32_immediate(context, input),
    values[0],
    buffer,
    i32_immediate(context, words),
  ])
  context.forward_results(
    continuation_call(
      context,
      environment,
      ContBind,
      args,
      [Ptr64, I32, GcRef64, Ptr64, I32],
      [GcRef64],
    ),
  )
}

///|
fn continuation_result_buffer(
  context : @adapter.InstructionContext,
  types : Array[@native_types.ValueType],
) -> (@lowering.Value, Int) {
  let mut words = 0
  for ty in types {
    words += if ty == V128 { 2 } else { 1 }
  }
  if words == 0 {
    return (context.emit(NullPtr, [], [Ptr64])[0], 0)
  }
  let object = context.create_stack_object(words * 8, 16)
  let address = context.emit(StackAddress(object), [], [Ptr64])[0]
  let zero = context.emit(I64Const(0UL), [], [I64])[0]
  for i in 0..<words {
    context.emit(
      Store(
        @lowering.StoreSpec::new(W64, I64, (i * 8).to_uint64(), Little, None),
      ),
      [address, zero],
      [],
    )
    |> ignore
  }
  (address, words)
}

///|
fn continuation_read_results(
  context : @adapter.InstructionContext,
  address : @lowering.Value,
  types : Array[@native_types.ValueType],
) -> Array[@lowering.Value] {
  let values : Array[@lowering.Value] = []
  let mut offset = 0
  for ty in types {
    if ty == V128 {
      values.push(
        context.emit(
          Load(
            @lowering.LoadSpec::new(
              W128,
              None,
              V128,
              offset.to_uint64(),
              Little,
              None,
            ),
          ),
          [address],
          [V128],
        )[0],
      )
      offset += 16
    } else {
      let word = context.emit(
          Load(
            @lowering.LoadSpec::new(
              W64,
              None,
              I64,
              offset.to_uint64(),
              Little,
              None,
            ),
          ),
          [address],
          [I64],
        )[0]
      let value = match ty {
        I64 => word
        I32 => context.emit(Convert(I32WrapI64), [word], [I32])[0]
        F32 => {
          let bits = context.emit(Convert(I32WrapI64), [word], [I32])[0]
          context.emit(Convert(Bitcast(I32, F32)), [bits], [F32])[0]
        }
        F64 => context.emit(Convert(Bitcast(I64, F64)), [word], [F64])[0]
        Ptr64 => context.emit(Convert(Bitcast(I64, Ptr64)), [word], [Ptr64])[0]
        GcRef64 => context.emit(GcRefFromBits, [word], [GcRef64])[0]
        V128 => abort("vector handled above")
      }
      values.push(value)
      offset += 8
    }
  }
  values
}

///|
fn lower_cont_effect(
  context : @adapter.InstructionContext,
  environment : Environment,
  tag : Int,
  switch_ : Bool,
) -> Unit {
  let operands = context.operands()
  let operand_types = context.operand_types()
  let start = if switch_ { 1 } else { 0 }
  let (inputs, input_words) = emit_payload_word_buffer(
    context,
    operands[start:].to_owned(),
    operand_types[start:].to_owned(),
  )
  let types = context.result_types()
  let (outputs, output_words) = continuation_result_buffer(context, types)
  let args = context.environment()
  args.push(i32_immediate(context, tag))
  let params : Array[@native_types.ValueType] = [Ptr64, I32]
  if switch_ {
    args.push(operands[0])
    params.push(GcRef64)
  }
  args.append([
    inputs,
    i32_immediate(context, input_words),
    outputs,
    i32_immediate(context, output_words),
  ])
  params.append([Ptr64, I32, Ptr64, I32])
  continuation_call(
    context,
    environment,
    if switch_ {
      ContSwitch
    } else {
      ContSuspend
    },
    args,
    params,
    [],
  )
  |> ignore
  context.forward_results(continuation_read_results(context, outputs, types))
}

///|
fn lower_cont_resume(
  context : @adapter.InstructionContext,
  environment : Environment,
  inputs : Int,
  handlers : Int,
  exception_tag : Int,
) -> Unit {
  let values = context.operands()
  let operand_types = context.operand_types()
  let (input, words) = emit_payload_word_buffer(
    context,
    values[1:inputs + 1].to_owned(),
    operand_types[1:inputs + 1].to_owned(),
  )
  let descriptors = emit_runtime_word_buffer(
    context,
    values[inputs + 1:].to_owned(),
    operand_types[inputs + 1:].to_owned(),
  )
  let types = context.result_types()[1:].to_owned()
  let (output, _) = continuation_result_buffer(context, types)
  let args = context.environment()
  args.append([
    values[0],
    input,
    i32_immediate(context, words),
    descriptors,
    i32_immediate(context, handlers),
    output,
    i32_immediate(context, exception_tag),
  ])
  let results = continuation_call(
    context,
    environment,
    ContResume,
    args,
    [Ptr64, GcRef64, Ptr64, I32, Ptr64, I32, Ptr64, I32],
    [I32],
  )
  results.append(continuation_read_results(context, output, types))
  context.forward_results(results)
}
