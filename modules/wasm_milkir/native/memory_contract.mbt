///|
/// Native refinements retain the semantic Wasm dialect but are owned and
/// validated here, before selection. Checked object projections retain their
/// traps; field/array refinements are nontrapping metadata reads. Every physical
/// address expires at a moving or reentrant edge.
priv enum Projection {
  ArrayData(Int32)
  ArrayElements(Int32)
  ArrayLength
  StructData(Int32)
  FieldData(Int32, Int32, Int32, Int32, Bool)
}

///|
fn projection_opcode(projection : Projection) -> @milkir.ExtOp {
  let (name, immediates) : (String, FixedArray[Int32]) = match projection {
    ArrayData(width) => ("native_array_data", [width])
    ArrayElements(width) => ("native_array_elements", [width])
    ArrayLength => ("native_array_length", [])
    StructData(type_) => ("native_struct_data", [type_])
    FieldData(type_, field, width, reference, read) =>
      (
        "native_field_data",
        [type_, field, width, reference, if read { 1 } else { 0 }],
      )
  }
  ExtOp(
    @wasm_milkir.WASM_DIALECT,
    name,
    immediates,
    effects=Some({
      read: if projection is (FieldData(_, _, _, _, _) | ArrayElements(_)) {
        None
      } else {
        Some(Context)
      },
      write: None,
      may_trap: projection is StructData(_),
      observable: false,
      pointer_bytes: match projection {
        FieldData(_, _, width, _, true) => width
        _ => 0
      },
      pointer_region: match projection {
        ArrayLength => None
        StructData(_) => Some(Context)
        ArrayData(_) | ArrayElements(_) => Some(Heap(-1))
        FieldData(_, field, _, _, _) => Some(Heap(-2 - field))
      },
    }),
  )
}

///|
fn decode_projection(extension : @milkir.ExtOp) -> Projection? {
  if extension.dialect != @wasm_milkir.WASM_DIALECT {
    return None
  }
  match (extension.opcode, extension.immediates) {
    ("native_array_data", [width]) if width == 0 ||
      width == 1 ||
      width == 2 ||
      width == 4 ||
      width == 8 => Some(ArrayData(width))
    ("native_array_elements", [width]) if width == 1 ||
      width == 2 ||
      width == 4 ||
      width == 8 => Some(ArrayElements(width))
    ("native_array_length", []) => Some(ArrayLength)
    ("native_struct_data", [type_]) if type_ >= 0 => Some(StructData(type_))
    ("native_field_data", [type_, field, width, reference, read]) if type_ >= 0 &&
      field >= 0 &&
      (width == 1 || width == 2 || width == 4 || width == 8) &&
      (reference == 0 || reference == 1) &&
      (read == 0 || read == 1) =>
      Some(FieldData(type_, field, width, reference, read == 1))
    _ => None
  }
}

///|
fn semantic_effects(opcode : @milkir.Opcode) -> @milkir.ExtensionEffects {
  let effects = @effects.analyze(opcode)
  let write = if !effects.preserves_physical_addresses() {
    Some(@milkir.AliasRegion::Other)
  } else {
    match effects.write {
      None => None
      Some(Unknown) => Some(Other)
      Some(StructField(_, field)) => Some(Heap(-2 - field))
      Some(_) => Some(Heap(-1))
    }
  }
  let read = match effects.read {
    None => None
    Some(Unknown) => Some(@milkir.AliasRegion::Other)
    Some(ArrayLength) => Some(Context)
    Some(StructField(_, field)) => Some(Heap(-2 - field))
    Some(_) => Some(Heap(-1))
  }
  {
    read,
    write,
    may_trap: effects.may_trap,
    observable: effects.may_collect ||
    effects.may_reenter ||
    effects.may_suspend ||
    effects.may_replace_heap,
    pointer_region: None,
    pointer_bytes: 0,
  }
}

///|
fn annotate_semantic(
  extension : @milkir.ExtOp,
  signature : @milkir.Signature,
) -> @milkir.ExtOp {
  let plain = @milkir.ExtOp(
    extension.dialect,
    extension.opcode,
    extension.immediates,
  )
  ExtOp(
    plain.dialect,
    plain.opcode,
    plain.immediates,
    effects=Some(semantic_effects(Ext(plain, signature))),
  )
}

///|
fn field_width(field : @wasm_milkir.WasmFieldContract) -> Int32? {
  match field.storage {
    Packed8 => Some(1)
    Packed16 => Some(2)
    Value(I32 | F32) => Some(4)
    Value(I64 | F64 | Ref) => Some(8)
    _ => None
  }
}

///|
fn validate_memory_extension(
  view : @milkir.ExtensionInstView,
  context : @wasm_milkir.WasmValidationContext,
  results : Array[@milkir.Type],
) -> String? {
  if decode_projection(view.op) is Some(projection) {
    if view.op != projection_opcode(projection) {
      return Some("invalid projection memory effects")
    }
    let (parameters, returns) : (Array[@milkir.Type], Array[@milkir.Type]) = match
      projection {
      ArrayLength => ([Ptr], [I32])
      ArrayElements(_) => ([Ptr], [Ptr])
      FieldData(_, _, _, _, _) => ([Ptr], [Ptr])
      _ => ([Ref], [Ptr])
    }
    if view.operand_types.length() != parameters.length() ||
      view.result_types.length() != returns.length() {
      return Some("invalid projection signature")
    }
    for i, type_ in parameters {
      if view.operand_types[i] != type_ {
        return Some("invalid projection operand")
      }
    }
    for i, type_ in returns {
      if view.result_types[i] != type_ {
        return Some("invalid projection result")
      }
    }
    if projection is StructData(type_) &&
      struct_view_shape(context, type_) is None {
      // Empty structs have no field access and never need this projection.
      return Some("invalid struct projection contract")
    }
    if projection is FieldData(type_, field, width, reference, _) {
      guard context.struct_field(type_, field) is Some(contract) &&
        field_width(contract) == Some(width) else {
        return Some("invalid field projection contract")
      }
      if (if contract.storage is Value(Ref) { 1 } else { 0 }) != reference {
        return Some("invalid reference projection contract")
      }
    }
    return None
  }
  let plain = @milkir.ExtOp(view.op.dialect, view.op.opcode, view.op.immediates)
  if view.op.effects is Some(_) &&
    view.op !=
    annotate_semantic(
      plain,
      Signature(
        Array::makei(view.operand_types.length(), i => view.operand_types[i]),
        Array::makei(view.result_types.length(), i => view.result_types[i]),
      ),
    ) {
    return Some("invalid refined Wasm memory effects")
  }
  context.validate_extension(view.with_op(plain), results)
}

///|
fn lower_projection(
  context : @adapter.InstructionContext,
  environment : Environment,
  projection : Projection,
  validation : @wasm_milkir.WasmValidationContext,
) -> String? {
  if projection is FieldData(type_, field, _, _, read) {
    let mut offset = 0
    for index in 0..<=field {
      let contract = validation.struct_field(type_, index).unwrap()
      let width = if contract.storage is Value(V128) {
        16
      } else {
        field_width(contract).unwrap()
      }
      offset = (offset + width - 1) / width * width
      if index != field {
        offset += width
      }
    }
    let view = context.emit(Convert(Bitcast(Ptr64, I64)), context.operands(), [
        I64,
      ])[0]
    let raw = context.emit(
        IntBinaryImmediate(And, 0xFFFFFFFFFFFFFFFCUL),
        [view],
        [I64],
      )[0]
    let flag = context.emit(
        IntBinaryImmediate(And, if read { 1UL } else { 2UL }),
        [view],
        [I64],
      )[0]
    let condition = context.emit(IntCompareImmediate(Equal, 0UL), [flag], [I32])[0]
    let selected_offset = if read {
      let typed = context.emit(I64Const(offset.to_uint64()), [], [I64])[0]
      let legacy = context.emit(I64Const((field * 16).to_uint64()), [], [I64])[0]
      context.emit(Select, [condition, typed, legacy], [I64])[0]
    } else {
      context.emit(I64Const(offset.to_uint64()), [], [I64])[0]
    }
    let address = context.emit(IntBinary(Add), [raw, selected_offset], [I64])[0]
    let address = if read {
      address
    } else {
      let null = context.emit(I64Const(0UL), [], [I64])[0]
      context.emit(Select, [condition, address, null], [I64])[0]
    }
    let pointer = context.emit(Convert(Bitcast(I64, Ptr64)), [address], [Ptr64])[0]
    context.forward_results([pointer])
    return None
  }
  if projection is ArrayElements(width) {
    let view = context.emit(Convert(Bitcast(Ptr64, I64)), context.operands(), [
        I64,
      ])[0]
    let tag = context.emit(IntBinaryImmediate(And, 15UL), [view], [I64])[0]
    let code = match width {
      1 => 1UL
      2 => 2UL
      4 => 3UL
      _ => 4UL
    }
    let compatible = context.emit(IntCompareImmediate(Equal, code), [tag], [I32])[0]
    let raw = context.emit(
        IntBinaryImmediate(And, 0xFFFFFFFFFFFFFFF0UL),
        [view],
        [I64],
      )[0]
    let zero = context.emit(I64Const(0UL), [], [I64])[0]
    let bits = context.emit(Select, [compatible, raw, zero], [I64])[0]
    context.forward_results([
      context.emit(Convert(Bitcast(I64, Ptr64)), [bits], [Ptr64])[0],
    ])
    return None
  }
  if projection is ArrayLength {
    let tagged = context.emit(
        Convert(Bitcast(Ptr64, I64)),
        context.operands(),
        [I64],
      )[0]
    let bits = context.emit(
        IntBinaryImmediate(And, 0xFFFFFFFFFFFFFFF0UL),
        [tagged],
        [I64],
      )[0]
    let pointer = context.emit(Convert(Bitcast(I64, Ptr64)), [bits], [Ptr64])[0]
    let available = context.emit(IntCompareImmediate(NotEqual, 0UL), [bits], [
        I32,
      ])[0]
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
    context.forward_results(context.block_parameters(ready))
    return None
  }
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  let operands = [heap, context.operands()[0]]
  let parameters : Array[@native_types.ValueType] = [
    Ptr64,
    if projection is (FieldData(_, _, _, _, _) | ArrayElements(_)) {
      Ptr64
    } else {
      GcRef64
    },
  ]
  let helper = match projection {
    StructData(type_) => {
      operands[0] = context.environment()[0]
      operands.push(i32_immediate(context, type_))
      parameters.push(I32)
      let (shape, fields) = struct_view_shape(validation, type_).unwrap()
      operands.push(context.emit(I64Const(shape), [], [I64])[0])
      parameters.push(I64)
      operands.push(i32_immediate(context, fields))
      parameters.push(I32)
      @wasm_milkir.WasmRuntimeHelper::GcStructData
    }
    ArrayElements(_) => return Some("unexpected array element projection")
    ArrayData(width) => {
      operands.push(i32_immediate(context, width))
      parameters.push(I32)
      GcArrayDataHeap
    }
    FieldData(_, _, _, _, _) => return Some("unexpected field projection")
    ArrayLength => return Some("unexpected array length projection")
  }
  context.finish_call_without_roots(
    @native_types.NativeCall::new(
      External((environment.runtime_symbol)(helper)),
      @native_types.Signature::new(parameters, [Ptr64]),
      Platform,
      @native_types.CallBehavior::new(
        Read,
        projection is StructData(_),
        false,
        false,
        false,
      ),
    ),
    operands,
  )
  None
}

///|
/// An exact bounded prefix encoding, not a collision-prone type fingerprint.
/// Larger declarations keep the checked compatibility accessor.
fn struct_view_shape(
  context : @wasm_milkir.WasmValidationContext,
  type_ : Int32,
) -> (UInt64, Int32)? {
  let mut shape = 0UL
  let mut count = 0
  while context.struct_field(type_, count) is Some(field) {
    if count == 16 {
      return None
    }
    let code = match field.storage {
      Packed8 => 1UL
      Packed16 => 2UL
      Value(I32 | F32) => 3UL
      Value(I64 | F64) => 4UL
      Value(V128) => 5UL
      Value(Ref) => 12UL
      _ => return None
    }
    shape = shape | (code << (count * 4))
    count += 1
  }
  if count == 0 {
    None
  } else {
    Some((shape, count))
  }
}
