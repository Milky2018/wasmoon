///|
priv struct ArrayAccess {
  first : Int32
  width : Int32
  opcode : @wasm_milkir.WasmOpcode
  loop_header : Int32?
}

///|
/// Physical views follow only forward, single-predecessor CFG edges. Only these
/// operations cannot collect, poll, reenter, or replace the embedding heap.
/// Aliasing element writes are allowed: the view caches no element values.
fn array_region_local(inst : @milkir.Inst) -> Bool {
  match inst.opcode {
    Scalar(_) | Vector(_) | GlobalValue(_) => true
    Memory(Load(_) | LoadNarrow(_, _, _)) => true
    _ =>
      match @wasm_milkir.decode_opcode(inst.opcode) {
        Some(
          ArrayGet(_)
          | ArrayGetS(_, _)
          | ArrayGetU(_, _)
          | ArraySet(_)
          | ArrayLen
          | StructGet(_, _)
          | StructGetS(_, _, _)
          | StructGetU(_, _, _)
          | StructSet(_, _)
          | I31New
          | I31GetS
          | I31GetU
        ) => true
        _ => false
      }
  }
}

///|
fn scalar_array_access(
  inst : @milkir.Inst,
  context : @wasm_milkir.WasmValidationContext,
) -> (Int32, @wasm_milkir.WasmOpcode)? {
  let opcode = @wasm_milkir.decode_opcode(inst.opcode)
  let index = match opcode {
    Some(ArrayGet(t) | ArrayGetS(t, _) | ArrayGetU(t, _) | ArraySet(t)) => t
    _ => return None
  }
  guard inst.args.length() == (if opcode is Some(ArraySet(_)) { 3 } else { 2 }) &&
    context.array_element(index) is Some(field) else {
    return None
  }
  let width = match field.storage {
    Packed8 => 1
    Packed16 => 2
    Value(I32 | F32) => 4
    Value(I64 | F64) => 8
    _ => return None
  }
  Some((width, opcode.unwrap()))
}

///|
fn plan_array_accesses(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
) -> Map[Int32, ArrayAccess] {
  let result : Map[Int32, ArrayAccess] = Map([])
  if function.blocks.length() > 4096 {
    return result
  }
  let cfg = @milkir.CFG::build(function)
  let outgoing : Map[Int32, Map[(Int32, Int32), Int32]] = Map([])
  for block in function.blocks {
    let first : Map[(Int32, Int32), Int32] = Map([])
    // Only a predecessor already emitted by the streaming lowerer can supply
    // native SSA values. Backedges and joins always begin a new region.
    if cfg.get_predecessors(block.id) is [previous] &&
      outgoing.get(previous) is Some(inherited) {
      for key, value in inherited {
        first[key] = value
      }
    }
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if !array_region_local(inst) {
        first.clear()
      }
      if scalar_array_access(inst, context) is Some((width, opcode)) {
        let key = (inst.args[0].id, width)
        let start = first.get(key).unwrap_or(id)
        if first.length() >= 128 && !first.contains(key) {
          first.clear()
        }
        first[key] = start
        result[id] = { first: start, width, opcode, loop_header: None, }
      }
    }
    outgoing[block.id] = first
  }
  // A single query is cheaper through the existing one-call accessor.
  let uses : Map[Int32, Int32] = Map([])
  for _, access in result {
    uses[access.first] = uses.get(access.first).unwrap_or(0) + 1
  }
  let single = result.keys().to_array().filter(id => uses[result[id].first] < 2)
  for id in single {
    result.remove(id)
  }
  plan_loop_array_accesses(function, context, cfg, result)
  result
}

///|
fn prepare_array_view(
  context : @adapter.InstructionContext,
  environment : Environment,
  width : Int32,
) -> (@lowering.Value, @lowering.Value) {
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  let pointer = context.emit_call_without_roots(
      @native_types.NativeCall::new(
        External((environment.runtime_symbol)(GcArrayDataHeap)),
        @native_types.Signature::new([Ptr64, GcRef64, I32], [Ptr64]),
        Platform,
        @native_types.CallBehavior::new(Read, true, false, false, false),
      ),
      [heap, context.operands()[0], i32_immediate(context, width)],
      [Ptr64],
    )[0]
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [pointer], [I64])[0]
  let available = context.emit(IntCompareImmediate(NotEqual, 0UL), [bits], [I32])[0]
  let present = context.create_block([])
  let missing = context.create_block([])
  let ready = context.create_block([I32])
  context.branch(available, present, [], missing, [])
  context.switch_to_block(present)
  let length = context.emit(
      Load(@lowering.LoadSpec::new(W32, None, I32, 0UL, Little, None)),
      [pointer],
      [I32],
    )[0]
  context.jump(ready, [length])
  context.switch_to_block(missing)
  context.jump(ready, [i32_immediate(context, 0)])
  context.switch_to_block(ready)
  let view = (pointer, context.block_parameters(ready)[0])
  view
}

///|
fn lower_array_access(
  context : @adapter.InstructionContext,
  environment : Environment,
  access : ArrayAccess,
  views : Map[Int32, (@lowering.Value, @lowering.Value)],
) -> String? {
  let (payload, length) = match views.get(access.first) {
    Some(view) => view
    None => {
      if access.first != context.instruction_id() {
        return Some("GC view does not dominate its physical access")
      }
      let view = prepare_array_view(context, environment, access.width)
      views[access.first] = view
      view
    }
  }
  let fast = context.create_block([])
  let slow = context.create_block([])
  let join = context.create_block(context.result_types())
  let source = context.operands()
  let within = context.emit(IntCompare(UnsignedLessThan), [source[1], length], [
      I32,
    ])[0]
  context.branch(within, fast, [], slow, [])
  context.switch_to_block(slow)
  // Compatibility layouts and verification retain the original helpers.
  let write = access.opcode is ArraySet(_)
  let type_index = match access.opcode {
    ArrayGet(t) | ArrayGetS(t, _) | ArrayGetU(t, _) | ArraySet(t) => t
    _ => return Some("invalid array access plan")
  }
  let operands = [source[0], i32_immediate(context, type_index), source[1]]
  let parameters : Array[@native_types.ValueType] = [GcRef64, I32, I32]
  let slow_values : Array[@lowering.Value] = []
  if write {
    operands.push(
      encode_runtime_word(context, source[2], context.operand_types()[2]),
    )
    parameters.push(I64)
    emit_runtime_void_call(
      context,
      environment,
      GcArraySetHeap,
      // Explicit-heap helpers have the same first two arguments as below.
      [
        context.emit(
          EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
          context.environment(),
          [Ptr64],
        )[0],
        source[0],
        source[1],
        operands[3],
      ],
      [Ptr64, GcRef64, I32, I64],
      ReadWrite,
    )
  } else {
    let word = emit_runtime_word_call(
      context,
      environment,
      GcArrayGet,
      operands,
      parameters,
      Read,
    )
    let value = match context.result_types()[0] {
      I32 => {
        let narrow = context.emit(Convert(I32WrapI64), [word], [I32])[0]
        match access.opcode {
          ArrayGetS(_, width) =>
            context.emit(
              Convert(SignExtend(I32, if width == 1 { W8 } else { W16 })),
              [narrow],
              [I32],
            )[0]
          ArrayGetU(_, width) => {
            let mask = i32_immediate(
              context,
              if width == 1 {
                255
              } else {
                65535
              },
            )
            context.emit(IntBinary(And), [narrow, mask], [I32])[0]
          }
          _ => narrow
        }
      }
      I64 => word
      F32 => {
        let narrow = context.emit(Convert(I32WrapI64), [word], [I32])[0]
        context.emit(Convert(Bitcast(I32, F32)), [narrow], [F32])[0]
      }
      F64 => context.emit(Convert(Bitcast(I64, F64)), [word], [F64])[0]
      _ => return Some("invalid scalar array result")
    }
    slow_values.push(value)
  }
  context.jump(join, slow_values)
  context.switch_to_block(fast)
  let index = context.emit(Convert(I64ExtendI32(Unsigned)), [source[1]], [I64])[0]
  let stride = context.emit(I64Const(access.width.to_uint64()), [], [I64])[0]
  let offset = context.emit(IntBinary(Mul), [index, stride], [I64])[0]
  let address = context.emit(PointerOffset, [payload, offset], [Ptr64])[0]
  let width : @native_types.AccessWidth = match access.width {
    1 => W8
    2 => W16
    4 => W32
    _ => W64
  }
  if write {
    context.emit(
      Store(
        @lowering.StoreSpec::new(
          width,
          context.operand_types()[2],
          16UL,
          Little,
          None,
        ),
      ),
      [address, source[2]],
      [],
    )
    |> ignore
    context.jump(join, [])
  } else {
    let type_ = context.result_types()[0]
    let extension : @native_types.LoadExtension = if access.width < 4 {
      if access.opcode is ArrayGetS(_, _) {
        Signed
      } else {
        Unsigned
      }
    } else {
      None
    }
    let value = context.emit(
        Load(
          @lowering.LoadSpec::new(width, extension, type_, 16UL, Little, None),
        ),
        [address],
        [type_],
      )[0]
    context.jump(join, [value])
  }
  context.switch_to_block(join)
  context.forward_results(context.block_parameters(join))
  None
}
