///|
fn memory_emit(
  function : @milkir.Function,
  block : @milkir.Block,
  opcode : @milkir.Opcode,
  args : Array[@milkir.Value],
  type_ : @milkir.Type,
) -> @milkir.Value {
  let value = function.new_value(type_)
  block.append_inst(function.new_inst(opcode, args, [value]))
  value
}

///|
fn memory_constant(
  function : @milkir.Function,
  block : @milkir.Block,
  type_ : @milkir.Type,
  value : Int64,
) -> @milkir.Value {
  memory_emit(function, block, Scalar(IntConst(value)), [], type_)
}

///|
fn memory_project(
  function : @milkir.Function,
  block : @milkir.Block,
  kind : Projection,
  value : @milkir.Value,
) -> @milkir.Value {
  let type_ : @milkir.Type = if kind is ArrayLength { I32 } else { Ptr }
  memory_emit(
    function,
    block,
    Ext(projection_opcode(kind), Signature([value.ty], [type_])),
    [value],
    type_,
  )
}

///|
priv struct MemoryAccess {
  projection : Projection
  width : Int32
  type_ : @milkir.Type
  signed : Bool
  array : Bool
  write : Bool
  length : Bool
}

///|
fn memory_access(
  inst : @milkir.Inst,
  context : @wasm_milkir.WasmValidationContext,
) -> MemoryAccess? {
  let opcode = @wasm_milkir.decode_opcode(inst.opcode)
  let (contract, projection, array, write, length, signed) = match opcode {
    Some(ArrayLen) =>
      (
        Some(@wasm_milkir.WasmFieldContract::{
          storage: Value(I32),
          mutable_: false,
          defaultable: true,
        }),
        ArrayData(0),
        true,
        false,
        true,
        false,
      )
    Some(
      ArrayGet(type_)
      | ArrayGetS(type_, _)
      | ArrayGetU(type_, _)
      | ArraySet(type_)
    ) =>
      (
        context.array_element(type_),
        ArrayData(0),
        true,
        opcode is Some(ArraySet(_)),
        false,
        opcode is Some(ArrayGetS(_, _)),
      )
    Some(
      StructGet(type_, field)
      | StructGetS(type_, field, _)
      | StructGetU(type_, field, _)
      | StructSet(type_, field)
    ) =>
      (
        context.struct_field(type_, field),
        FieldData(type_, field, 0, 0, false),
        false,
        opcode is Some(StructSet(_, _)),
        false,
        opcode is Some(StructGetS(_, _, _)),
      )
    _ => return None
  }
  if projection is FieldData(type_, _, _, _, _) &&
    struct_view_shape(context, type_) is None {
    return None
  }
  guard contract is Some(field) && field_width(field) is Some(width) else {
    return None
  }
  let type_ : @milkir.Type = match field.storage {
    Value(type_) => type_
    Packed8 | Packed16 => I32
  }
  // Reference writes retain the runtime's barrier and arena admission. Numeric
  // array projections accept only a compact non-reference physical layout.
  if (write && type_ == Ref) || (array && type_ == Ref) {
    return None
  }
  let projection = match projection {
    ArrayData(_) => if length { ArrayData(0) } else { ArrayElements(width) }
    FieldData(type_, field, _, _, _) =>
      FieldData(
        type_,
        field,
        width,
        if contract.unwrap().storage is Value(Ref) {
          1
        } else {
          0
        },
        !write,
      )
    StructData(_) | ArrayElements(_) | ArrayLength => return None
  }
  Some({ projection, width, type_, signed, array, write, length, })
}

///|
/// Split an access into a checked compatibility edge and ordinary typed memory.
/// Its original result remains a copy from a join parameter, preserving every
/// user/DFG identity without cloning a function or maintaining a second graph.
fn expand_memory_access(
  function : @milkir.Function,
  block : @milkir.Block,
  inst : @milkir.Inst,
  access : MemoryAccess,
) -> @milkir.Block {
  let source = match access.projection {
    FieldData(type_, _, _, _, _) =>
      memory_project(function, block, StructData(type_), inst.args[0])
    ArrayElements(_) =>
      memory_project(function, block, ArrayData(0), inst.args[0])
    _ => inst.args[0]
  }
  let pointer = memory_project(function, block, access.projection, source)
  if access.projection is FieldData(_, _, _, _, true) {
    let zero = memory_constant(function, block, I64, 0L)
    let opcode : @milkir.Opcode = if access.width < 4 {
      Memory(LoadNarrow(access.type_, access.width * 8, access.signed))
    } else {
      Memory(Load(access.type_))
    }
    inst.set_opcode(opcode)
    inst.operands.clear()
    inst.operands.append([pointer, zero])
    block.append_inst(inst)
    return block
  }
  let length = if access.array {
    Some(memory_project(function, block, ArrayLength, pointer))
  } else {
    None
  }
  let within = if access.array && !access.length {
    memory_emit(
      function,
      block,
      Scalar(IntCompare(Ult)),
      [inst.args[1], length.unwrap()],
      I32,
    )
  } else {
    let bits = memory_emit(
      function,
      block,
      Scalar(Convert(Bitcast)),
      [pointer],
      I64,
    )
    let zero = memory_constant(function, block, I64, 0L)
    memory_emit(function, block, Scalar(IntCompare(Ne)), [bits, zero], I32)
  }
  let fast = function.new_block0()
  let slow = function.new_block0()
  let join = function.new_block0()
  block.set_terminator(Branch(within, fast.id, [], slow.id, []))
  let old_args = inst.args.copy()
  let old_opcode = inst.opcode
  let slow_results = inst.results.map(result => function.new_value(result.ty))
  let fallback = function.new_inst(old_opcode, old_args, slow_results)
  slow.append_inst(fallback)
  slow.set_terminator(Jump(join.id, slow_results))
  let offset = if access.array && !access.length {
    let index = memory_emit(
      function,
      fast,
      Scalar(Convert(UnsignedExtend)),
      [old_args[1]],
      I64,
    )
    let stride = memory_constant(function, fast, I64, access.width.to_int64())
    let element = memory_emit(
      function,
      fast,
      Scalar(IntBinary(Mul)),
      [index, stride],
      I64,
    )
    let start = memory_constant(function, fast, I64, 16L)
    memory_emit(function, fast, Scalar(IntBinary(Add)), [element, start], I64)
  } else {
    memory_constant(function, fast, I64, 0L)
  }
  let fast_results : Array[@milkir.Value] = []
  if access.length {
    fast_results.push(length.unwrap())
  } else if access.write {
    let opcode : @milkir.Opcode = if access.width < 4 {
      Memory(StoreNarrow(access.width * 8))
    } else {
      Memory(Store(access.type_))
    }
    fast.append_inst(
      function.new_inst(
        opcode,
        [pointer, old_args[if access.array { 2 } else { 1 }], offset],
        [],
      ),
    )
  } else {
    let opcode : @milkir.Opcode = if access.width < 4 {
      Memory(LoadNarrow(access.type_, access.width * 8, access.signed))
    } else {
      Memory(Load(access.type_))
    }
    fast_results.push(
      memory_emit(function, fast, opcode, [pointer, offset], access.type_),
    )
  }
  fast.set_terminator(Jump(join.id, fast_results))
  if inst.results.is_empty() {
    function.discard_inst(inst)
  } else {
    let result = function.append_block_param(join, inst.results[0].ty)
    inst.set_opcode(Scalar(Copy))
    inst.operands.clear()
    inst.operands.push(result)
    join.append_inst(inst)
  }
  join
}

///|
/// Expose GC memory before target selection. Public semantic validation occurs
/// before refinements, and native effect/lifetime validation occurs after the
/// generic optimizer. Repeated target compilation is idempotent.
pub fn prepare_gc_memory(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  exclusive_poll_controls~ : Bool = false,
  on_event~ : (@milkir_native.NativeLowerEvent) -> Unit = fn(_) { () },
) -> Unit raise @milkir.VerifyError {
  fn validate(view : @milkir.ExtensionInstView) -> String? {
    validate_memory_extension(view, context, function.results)
  }
  fn validate_global(value : @milkir.GlobalValueData) -> String? {
    context.validate_global_value(value)
  }
  on_event(PreparationStarted(name="gc_memory_input_validation"))
  function.verify_with_dialect_validator(
    @wasm_milkir.WASM_DIALECT,
    validate,
    validate_global,
  )
  on_event(PreparationStarted(name="gc_memory_scan"))
  let old_blocks = function.blocks.copy()
  let has_access = old_blocks.any(block => {
    function
    .block_instruction_ids(block)
    .any(id => {
      memory_access(function.instruction_by_id(id).unwrap(), context) is Some(_)
    })
  })
  let already_prepared = old_blocks.any(block => {
    function
    .block_instruction_ids(block)
    .any(id => {
      function.instruction_by_id(id).unwrap().opcode is Ext(extension, _) &&
      extension.effects is Some(_)
    })
  })
  let expand = has_access &&
    !already_prepared &&
    // Bound the expansion graph, not just individual rewrite work. Large
    // generated initializers keep checked helpers; expanding thousands of
    // stores would dominate cold compilation without helping a hot loop.
    old_blocks.fold(init=0, fn(total, block) {
      total + block.instruction_count()
    }) <=
    1200 &&
    old_blocks.length() <= 2048
  if expand {
    if exclusive_poll_controls {
      version_poll_loops(function, context)
    }
    if poll_region_error(function) is Some(error) {
      raise @milkir.VerifyError::unverifiable_instruction(error)
    }
    function.verify_with_dialect_validator(
      @wasm_milkir.WASM_DIALECT,
      validate,
      validate_global,
    )
    // Logical reads use the same effect/versioned GVN before their checked
    // physical expansion, including cloned loops and immutable length.
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Ext(extension, signature) {
          inst.set_opcode(
            Ext(annotate_semantic(extension, signature), signature),
          )
        }
      }
    }
    on_event(PreparationStarted(name="gc_memory_logical_optimization"))
    @generic.optimize_with_level(function, O3) |> ignore
    on_event(PreparationStarted(name="gc_memory_expansion"))
    for block in function.blocks.copy() {
      let ids = function.block_instruction_ids(block).to_owned()
      let term = block.terminator
      let term_metadata = block.terminator_metadata()
      block.clear_instructions_for_move()
      let mut current = block
      for id in ids {
        let inst = function.instruction_by_id(id).unwrap()
        let access = memory_access(inst, context)
        if inst.opcode is Ext(extension, signature) {
          inst.set_opcode(
            Ext(annotate_semantic(extension, signature), signature),
          )
        }
        if access is Some(access) {
          let first_generated = function.next_inst_id
          let source_metadata = inst.metadata.copy()
          current = expand_memory_access(function, current, inst, access)
          // Checked projections can carry the original null/type trap. Keep
          // its source location on every generated part, including fallback.
          for id in first_generated..<function.next_inst_id {
            if function.instruction_by_id(id) is Some(generated) {
              for metadata in source_metadata {
                generated.add_metadata(metadata)
              }
            }
          }
        } else {
          current.append_inst(inst)
        }
      }
      current.set_terminator(term.unwrap(), metadata=term_metadata)
    }
    // New split blocks dominate some original blocks. Keep SSA producers in
    // reverse postorder for streaming selectors while retaining stable IDs.
    on_event(PreparationStarted(name="gc_memory_schedule"))
    let cfg = @milkir.CFG::build(function)
    let blocks : Map[Int32, @milkir.Block] = Map([])
    for block in function.blocks {
      blocks[block.id] = block
    }
    let order = cfg.reverse_postorder()
    function.blocks.clear()
    for id in order {
      function.blocks.push(blocks[id])
      blocks.remove(id)
    }
    for _, block in blocks {
      function.blocks.push(block)
    }
    on_event(PreparationStarted(name="gc_memory_physical_optimization"))
    @generic.optimize_with_level(function, O3) |> ignore
    on_event(PreparationStarted(name="gc_memory_placement"))
    if @generic.hoist_loop_invariants(function, guard_entries=true).changed {
      // Finish scalar cleanup once, after CFG-aware placement converges.
      on_event(PreparationStarted(name="gc_memory_cleanup"))
      @generic.optimize_with_level(function, O2) |> ignore
    }
  }
  if expand {
    on_event(PreparationStarted(name="gc_memory_output_validation"))
    function.verify_with_dialect_validator(
      @wasm_milkir.WASM_DIALECT,
      validate,
      validate_global,
    )
  }
  on_event(PreparationStarted(name="gc_memory_borrow_validation"))
  if gc_borrow_error(function) is Some(error) {
    raise @milkir.VerifyError::unverifiable_instruction(
      "GC memory in \{function.name}: \{error}",
    )
  }
}
