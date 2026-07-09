///|
fn type_byte_size(ty : @milkir.Type) -> Int {
  match ty {
    I32 | F32 => 4
    I64 | F64 | Ptr | Ref | CallableRef | OpaqueRef => 8
    V128 => 16
  }
}

///|
fn zero_value(
  builder : @milkir.FunctionBuilder,
  ty : @milkir.Type,
) -> @milkir.Value? {
  match ty {
    I32 => Some(builder.iconst_i32(0))
    I64 | Ref | Ptr | CallableRef | OpaqueRef => Some(builder.iconst_i64(0L))
    F32 => Some(builder.fconst_f32(0.0))
    F64 => Some(builder.fconst_f64(0.0))
    _ => None
  }
}

///|
fn pop_value(stack : Array[@milkir.Value]) -> @milkir.Value? {
  match stack.pop() {
    Some(value) => Some(value)
    None => None
  }
}

///|
fn push_binary(
  stack : Array[@milkir.Value],
  op : (@milkir.Value, @milkir.Value) -> @milkir.Value,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  stack.push(op(lhs, rhs))
  true
}

///|
fn emit_op(
  builder : @milkir.FunctionBuilder,
  ty : @milkir.Type,
  opcode : @milkir.Opcode,
  operands : Array[@milkir.Value],
) -> @milkir.Value? {
  guard builder.current_block() is Some(_) else { return None }
  Some(builder.emit_inst(ty, opcode, operands))
}

///|
fn emit_void_op(
  builder : @milkir.FunctionBuilder,
  opcode : @milkir.Opcode,
  operands : Array[@milkir.Value],
) -> Bool {
  guard builder.current_block() is Some(_) else { return false }
  builder.emit_void_inst(opcode, operands)
  true
}

///|
fn emit_multi_op(
  builder : @milkir.FunctionBuilder,
  result_types : Array[@milkir.Type],
  opcode : @milkir.Opcode,
  operands : Array[@milkir.Value],
) -> Array[@milkir.Value]? {
  guard builder.current_block() is Some(_) else { return None }
  Some(builder.emit_multi_inst(result_types, opcode, operands))
}

///|
fn push_unary_opcode(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, value.ty, opcode, [value]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_unary_opcode_as(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  ty : @milkir.Type,
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, ty, opcode, [value]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_binary_opcode(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, lhs.ty, opcode, [lhs, rhs]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_i32_binary_opcode(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, I32, opcode, [lhs, rhs]) is Some(raw) else {
    return false
  }
  guard emit_op(builder, I32, Ireduce, [raw]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_i32_shift_opcode(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  opcode : @milkir.Opcode,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, I32, Band, [rhs, builder.iconst_i32(31)])
    is Some(masked) else {
    return false
  }
  guard emit_op(builder, I32, opcode, [lhs, masked]) is Some(raw) else {
    return false
  }
  guard emit_op(builder, I32, Ireduce, [raw]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_i32_clz(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, I64, Uextend, [value]) is Some(extended) else {
    return false
  }
  guard emit_op(builder, I64, Clz, [extended]) is Some(raw_count) else {
    return false
  }
  guard emit_op(builder, I64, Isub, [raw_count, builder.iconst_i64(32L)])
    is Some(i32_count) else {
    return false
  }
  guard emit_op(builder, I32, Ireduce, [i32_count]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_i32_ctz(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, I64, Uextend, [value]) is Some(extended) else {
    return false
  }
  guard emit_op(builder, I64, Bor, [
      extended,
      builder.iconst_i64(0x1_0000_0000L),
    ])
    is Some(nonzero) else {
    return false
  }
  guard emit_op(builder, I64, Ctz, [nonzero]) is Some(raw_count) else {
    return false
  }
  guard emit_op(builder, I32, Ireduce, [raw_count]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_i32_popcnt(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  guard emit_op(builder, I64, Uextend, [value]) is Some(extended) else {
    return false
  }
  guard emit_op(builder, I64, Popcnt, [extended]) is Some(raw_count) else {
    return false
  }
  guard emit_op(builder, I32, Ireduce, [raw_count]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_int_cmp(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  cc : @milkir.IntCC,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, I32, Icmp(cc), [lhs, rhs]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_float_cmp(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  cc : @milkir.FloatCC,
) -> Bool {
  guard pop_value(stack) is Some(rhs) else { return false }
  guard pop_value(stack) is Some(lhs) else { return false }
  guard emit_op(builder, I32, Fcmp(cc), [lhs, rhs]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_float_copysign(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  float_ty : @milkir.Type,
  int_ty : @milkir.Type,
  magnitude_mask : Int64,
  sign_mask : Int64,
) -> Bool {
  guard pop_value(stack) is Some(sign_source) else { return false }
  guard pop_value(stack) is Some(magnitude_source) else { return false }
  guard emit_op(builder, int_ty, Bitcast, [magnitude_source]) is Some(x_bits) else {
    return false
  }
  guard emit_op(builder, int_ty, Bitcast, [sign_source]) is Some(y_bits) else {
    return false
  }
  let magnitude_mask_value = builder.iconst(int_ty, magnitude_mask)
  guard emit_op(builder, int_ty, Band, [x_bits, magnitude_mask_value])
    is Some(magnitude) else {
    return false
  }
  let sign_mask_value = builder.iconst(int_ty, sign_mask)
  guard emit_op(builder, int_ty, Band, [y_bits, sign_mask_value]) is Some(sign) else {
    return false
  }
  guard emit_op(builder, int_ty, Bor, [magnitude, sign]) is Some(result_bits) else {
    return false
  }
  guard emit_op(builder, float_ty, Bitcast, [result_bits]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_i31_new(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  let masked = builder.iconst_i32(@types.I32_MAX)
  guard emit_op(builder, I32, Band, [value, masked]) is Some(payload) else {
    return false
  }
  guard emit_op(builder, I64, Uextend, [payload]) is Some(payload64) else {
    return false
  }
  let shift = builder.iconst_i64(1L)
  guard emit_op(builder, I64, Ishl, [payload64, shift]) is Some(shifted) else {
    return false
  }
  let tag = builder.iconst_i64(1L)
  guard emit_op(builder, Ref, Bor, [shifted, tag]) is Some(encoded) else {
    return false
  }
  stack.push(encoded)
  true
}

///|
fn emit_i31_null_check(
  builder : @milkir.FunctionBuilder,
  value : @milkir.Value,
) -> Bool {
  guard builder.current_block() is Some(_) else { return false }
  guard emit_op(builder, value.ty, Iconst(@wasm_milkir.NULL_REF), [])
    is Some(null_ref) else {
    return false
  }
  guard emit_op(builder, I32, Icmp(Eq), [value, null_ref]) is Some(is_null) else {
    return false
  }
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(is_null, trap_block, continue_block)
  builder.switch_to_block(trap_block)
  builder.trap("null i31 reference")
  builder.switch_to_block(continue_block)
  true
}

///|
fn push_i31_get(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  signed : Bool,
) -> Bool {
  guard pop_value(stack) is Some(value) else { return false }
  if !emit_i31_null_check(builder, value) {
    return false
  }
  guard emit_op(builder, I64, Bitcast, [value]) is Some(bits) else {
    return false
  }
  let shift = builder.iconst_i64(1L)
  guard emit_op(builder, I64, Ushr, [bits, shift]) is Some(decoded64) else {
    return false
  }
  guard emit_op(builder, I32, Ireduce, [decoded64]) is Some(decoded32) else {
    return false
  }
  if signed {
    let sign_shift = builder.iconst_i32(1)
    guard emit_op(builder, I32, Ishl, [decoded32, sign_shift]) is Some(left) else {
      return false
    }
    guard emit_op(builder, I32, Sshr, [left, sign_shift]) is Some(result) else {
      return false
    }
    stack.push(result)
  } else {
    let mask = builder.iconst_i32(@types.I32_MAX)
    guard emit_op(builder, I32, Band, [decoded32, mask]) is Some(result) else {
      return false
    }
    stack.push(result)
  }
  true
}

///|
fn push_select(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(cond) else { return false }
  guard pop_value(stack) is Some(false_value) else { return false }
  guard pop_value(stack) is Some(true_value) else { return false }
  stack.push(builder.select(cond, true_value, false_value))
  true
}

///|
fn get_global_func_type(
  mod_ : @types.Module,
  func_idx : Int,
) -> @types.FuncType? {
  if func_idx < 0 {
    return None
  }
  if func_idx < mod_.imports.length() {
    match mod_.imports[func_idx].desc {
      Func(type_idx) =>
        if type_idx >= 0 && type_idx < mod_.types.length() {
          match mod_.types[type_idx].composite {
            Func(func_type) => Some(func_type)
            _ => None
          }
        } else {
          None
        }
      _ => None
    }
  } else {
    let local_idx = func_idx - mod_.imports.length()
    if local_idx >= 0 && local_idx < mod_.funcs.length() {
      let type_idx = mod_.funcs[local_idx]
      if type_idx >= 0 && type_idx < mod_.types.length() {
        match mod_.types[type_idx].composite {
          Func(func_type) => Some(func_type)
          _ => None
        }
      } else {
        None
      }
    } else {
      None
    }
  }
}

///|
fn collect_global_types(mod_ : @types.Module) -> Array[@types.GlobalType] {
  let globals : Array[@types.GlobalType] = []
  for import_ in mod_.imports {
    if import_.desc is Global(global_type) {
      globals.push(global_type)
    }
  }
  for global in mod_.globals {
    globals.push(global.type_)
  }
  globals
}

///|
fn collect_table_types(mod_ : @types.Module) -> Array[@types.TableType] {
  let tables : Array[@types.TableType] = []
  for import_ in mod_.imports {
    if import_.desc is Table(table_type) {
      tables.push(table_type)
    }
  }
  for table in mod_.tables {
    tables.push(table.type_)
  }
  tables
}

///|
fn collect_memory_types(mod_ : @types.Module) -> Array[@types.MemoryType] {
  let memories : Array[@types.MemoryType] = []
  for import_ in mod_.imports {
    if import_.desc is Memory(memory_type) {
      memories.push(memory_type)
    }
  }
  for memory in mod_.memories {
    memories.push(memory)
  }
  memories
}

///|
fn push_direct_call(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  mod_ : @types.Module,
  vmctx : @milkir.Value?,
  func_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard env.runtime_layout() is Some(layout) else { return false }
  guard get_global_func_type(mod_, func_idx) is Some(func_type) else {
    return false
  }
  let wasm_args : Array[@milkir.Value] = []
  for _ in 0..<func_type.params.length() {
    guard pop_value(stack) is Some(value) else { return false }
    wasm_args.push(value)
  }
  wasm_args.rev_in_place()

  let func_table = builder.load_ptr(
    Ptr,
    context,
    builder.iconst_i64(layout.func_table_offset.to_int64()),
  )
  let callee = builder.load_ptr(
    Ptr,
    func_table,
    builder.iconst_i64((func_idx * layout.func_table_entry_stride).to_int64()),
  )
  let args : Array[@milkir.Value] = [callee, context]
  for arg in wasm_args {
    args.push(arg)
  }
  let result_types = func_type.results.map(wasm_value_type_to_milkir)
  if result_types.length() == 0 {
    emit_void_op(builder, CallPtr(func_type.params.length(), 0), args)
  } else {
    guard emit_multi_op(
        builder,
        result_types,
        CallPtr(func_type.params.length(), result_types.length()),
        args,
      )
      is Some(results) else {
      return false
    }
    for result in results {
      stack.push(result)
    }
    true
  }
}

///|
fn push_global_get(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  global_types : Array[@types.GlobalType],
  global_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard env.runtime_layout() is Some(layout) else { return false }
  if global_idx < 0 || global_idx >= global_types.length() {
    return false
  }
  let ty = wasm_value_type_to_milkir(global_types[global_idx].value_type)
  let globals_offset = builder.iconst_i64(layout.globals_offset.to_int64())
  let globals_ptr = builder.load_ptr(I64, context, globals_offset)
  let field_offset = builder.iconst_i64(
    (global_idx * layout.global_value_stride).to_int64(),
  )
  stack.push(builder.load_ptr(ty, globals_ptr, field_offset))
  true
}

///|
fn push_global_set(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  global_types : Array[@types.GlobalType],
  global_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard env.runtime_layout() is Some(layout) else { return false }
  if global_idx < 0 || global_idx >= global_types.length() {
    return false
  }
  guard pop_value(stack) is Some(value) else { return false }
  let ty = wasm_value_type_to_milkir(global_types[global_idx].value_type)
  let globals_offset = builder.iconst_i64(layout.globals_offset.to_int64())
  let globals_ptr = builder.load_ptr(I64, context, globals_offset)
  let field_offset = builder.iconst_i64(
    (global_idx * layout.global_value_stride).to_int64(),
  )
  builder.store_ptr(ty, globals_ptr, value, field_offset)
  true
}

///|
fn table_is_64(table_types : Array[@types.TableType], table_idx : Int) -> Bool? {
  if table_idx < 0 || table_idx >= table_types.length() {
    None
  } else {
    Some(table_types[table_idx].is_table64)
  }
}

///|
fn push_table_size(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  table_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard env.runtime_layout() is Some(layout) else { return false }
  guard table_is_64(table_types, table_idx) is Some(is_table64) else {
    return false
  }
  let size_i64 = if table_idx == 0 {
    builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.table0_elements_offset.to_int64()),
    )
  } else {
    let sizes_ptr = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.table_sizes_offset.to_int64()),
    )
    builder.load_ptr(
      I64,
      sizes_ptr,
      builder.iconst_i64((table_idx * layout.pointer_stride).to_int64()),
    )
  }
  if is_table64 {
    stack.push(size_i64)
  } else {
    guard emit_op(builder, I32, Ireduce, [size_i64]) is Some(size_i32) else {
      return false
    }
    stack.push(size_i32)
  }
  true
}

///|
fn load_table_size_and_base(
  builder : @milkir.FunctionBuilder,
  env : EmbeddingEnvironment,
  context : @milkir.Value,
  table_idx : Int,
) -> (@milkir.Value, @milkir.Value)? {
  guard env.runtime_layout() is Some(layout) else { return None }
  if table_idx == 0 {
    let size = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.table0_elements_offset.to_int64()),
    )
    let base = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.table0_base_offset.to_int64()),
    )
    Some((size, base))
  } else {
    let idx_offset = builder.iconst_i64(
      (table_idx * layout.pointer_stride).to_int64(),
    )
    let sizes_ptr = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.table_sizes_offset.to_int64()),
    )
    let size = builder.load_ptr(I64, sizes_ptr, idx_offset)
    let tables_ptr = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.tables_offset.to_int64()),
    )
    let base = builder.load_ptr(I64, tables_ptr, idx_offset)
    Some((size, base))
  }
}

///|
fn push_table_get(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  table_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard env.runtime_layout() is Some(layout) else { return false }
  guard table_is_64(table_types, table_idx) is Some(is_table64) else {
    return false
  }
  guard pop_value(stack) is Some(elem_idx) else { return false }
  guard load_table_size_and_base(builder, env, context, table_idx)
    is Some((table_size, table_base)) else {
    return false
  }
  let elem_idx_i64 = if is_table64 {
    elem_idx
  } else {
    guard emit_op(builder, I64, Uextend, [elem_idx]) is Some(extended) else {
      return false
    }
    extended
  }
  guard emit_op(builder, I32, Icmp(Ult), [elem_idx_i64, table_size])
    is Some(in_bounds) else {
    return false
  }
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)
  builder.switch_to_block(trap_block)
  builder.trap("table out of bounds")
  builder.switch_to_block(continue_block)
  let byte_offset = builder.imul(
    elem_idx_i64,
    builder.iconst_i64(layout.table_entry_stride.to_int64()),
  )
  let addr = builder.iadd(table_base, byte_offset)
  stack.push(
    builder.load_ptr(
      I64,
      addr,
      builder.iconst_i64(layout.table_entry_value_offset.to_int64()),
    ),
  )
  true
}

///|
fn push_table_set(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  table_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard table_is_64(table_types, table_idx) is Some(_) else { return false }
  guard pop_value(stack) is Some(value) else { return false }
  guard pop_value(stack) is Some(elem_idx) else { return false }
  let one = if elem_idx.ty == I32 {
    builder.iconst_i32(1)
  } else {
    builder.iconst_i64(1L)
  }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.table_fill)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(table_idx),
    elem_idx,
    value,
    one,
  ])
  |> ignore
  true
}

///|
fn push_table_fill(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  table_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard table_is_64(table_types, table_idx) is Some(_) else { return false }
  guard pop3(stack) is Some((dst, value, size)) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.table_fill)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(table_idx),
    dst,
    value,
    size,
  ])
  |> ignore
  true
}

///|
fn memory_is_64(memory_types : Array[@types.MemoryType], memidx : Int) -> Bool? {
  if memidx < 0 || memidx >= memory_types.length() {
    None
  } else {
    Some(memory_types[memidx].is_memory64)
  }
}

///|
fn memory_index_type(
  memory_types : Array[@types.MemoryType],
  memidx : Int,
) -> @milkir.Type? {
  match memory_is_64(memory_types, memidx) {
    Some(true) => Some(I64)
    Some(false) => Some(I32)
    None => None
  }
}

///|
fn load_memory_base(
  builder : @milkir.FunctionBuilder,
  env : EmbeddingEnvironment,
  context : @milkir.Value,
  memidx : Int,
) -> @milkir.Value? {
  guard env.runtime_layout() is Some(layout) else { return None }
  if memidx == 0 {
    Some(
      builder.load_ptr(
        I64,
        context,
        builder.iconst_i64(layout.memory0_base_offset.to_int64()),
      ),
    )
  } else {
    guard env.memory_descriptor_layout() is Some(memory_layout) else {
      return None
    }
    let memories_ptr = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.memories_offset.to_int64()),
    )
    let memory_ptr = builder.load_ptr(
      I64,
      memories_ptr,
      builder.iconst_i64((memidx * layout.pointer_stride).to_int64()),
    )
    Some(
      builder.load_ptr(
        I64,
        memory_ptr,
        builder.iconst_i64(memory_layout.base_offset.to_int64()),
      ),
    )
  }
}

///|
fn load_memory_size_bytes(
  builder : @milkir.FunctionBuilder,
  env : EmbeddingEnvironment,
  context : @milkir.Value,
  memidx : Int,
) -> @milkir.Value? {
  guard env.runtime_layout() is Some(layout) else { return None }
  if memidx == 0 {
    Some(
      builder.load_ptr(
        I64,
        context,
        builder.iconst_i64(layout.memory0_size_offset.to_int64()),
      ),
    )
  } else {
    guard env.memory_descriptor_layout() is Some(memory_layout) else {
      return None
    }
    let memories_ptr = builder.load_ptr(
      I64,
      context,
      builder.iconst_i64(layout.memories_offset.to_int64()),
    )
    let memory_ptr = builder.load_ptr(
      I64,
      memories_ptr,
      builder.iconst_i64((memidx * layout.pointer_stride).to_int64()),
    )
    Some(
      builder.load_ptr(
        I64,
        memory_ptr,
        builder.iconst_i64(memory_layout.current_length_offset.to_int64()),
      ),
    )
  }
}

///|
fn push_memory_size(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard memory_index_type(memory_types, memidx) is Some(result_ty) else {
    return false
  }
  guard load_memory_size_bytes(builder, env, context, memidx)
    is Some(size_bytes) else {
    return false
  }
  let page_shift = builder.iconst_i64(
    memory_types[memidx].page_size_log2.to_int64(),
  )
  guard emit_op(builder, I64, Ushr, [size_bytes, page_shift]) is Some(pages_i64) else {
    return false
  }
  if result_ty == I64 {
    stack.push(pages_i64)
  } else {
    guard emit_op(builder, I32, Ireduce, [pages_i64]) is Some(pages_i32) else {
      return false
    }
    stack.push(pages_i32)
  }
  true
}

///|
fn push_memory_grow(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard memory_index_type(memory_types, memidx) is Some(result_ty) else {
    return false
  }
  guard pop_value(stack) is Some(delta) else { return false }
  let delta_i64 = if delta.ty == I64 {
    delta
  } else {
    guard emit_op(builder, I64, Uextend, [delta]) is Some(extended) else {
      return false
    }
    extended
  }
  let max_pages = memory_types[memidx].limits.max
    .map(fn(max) { max.to_int() })
    .unwrap_or(-1)
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.memory_grow)
  guard builder.call_symbol(symbol, Some(I32), [
      context,
      builder.iconst_i32(memidx),
      delta_i64,
      builder.iconst_i32(max_pages),
    ])
    is Some(call_result_i32) else {
    return false
  }
  let result = if result_ty == I64 {
    guard emit_op(builder, I64, Sextend, [call_result_i32]) is Some(extended) else {
      return false
    }
    extended
  } else {
    call_result_i32
  }
  stack.push(result)
  true
}

///|
fn pop3(
  stack : Array[@milkir.Value],
) -> (@milkir.Value, @milkir.Value, @milkir.Value)? {
  guard pop_value(stack) is Some(third) else { return None }
  guard pop_value(stack) is Some(second) else { return None }
  guard pop_value(stack) is Some(first) else { return None }
  Some((first, second, third))
}

///|
fn push_memory_fill(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard memory_index_type(memory_types, memidx) is Some(I32) else {
    // TODO(wasm_frontend): add memory64-capable runtime helper ABI before enabling
    // this reusable call path for memory64 memory.fill.
    return false
  }
  guard pop3(stack) is Some((dst, value, size)) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.memory_fill)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(memidx),
    dst,
    value,
    size,
  ])
  |> ignore
  true
}

///|
fn push_memory_copy(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  memory_types : Array[@types.MemoryType],
  dst_memidx : Int,
  src_memidx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard memory_index_type(memory_types, dst_memidx) is Some(I32) else {
    // TODO(wasm_frontend): add memory64-capable runtime helper ABI before enabling
    // this reusable call path for memory64 destination memories.
    return false
  }
  guard memory_index_type(memory_types, src_memidx) is Some(I32) else {
    // TODO(wasm_frontend): add memory64-capable runtime helper ABI before enabling
    // this reusable call path for memory64 source memories.
    return false
  }
  guard pop3(stack) is Some((dst, src, size)) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.memory_copy)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(dst_memidx),
    builder.iconst_i32(src_memidx),
    dst,
    src,
    size,
  ])
  |> ignore
  true
}

///|
fn push_memory_init(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
  data_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard memory_index_type(memory_types, memidx) is Some(I32) else {
    // TODO(wasm_frontend): add memory64-capable runtime helper ABI before enabling
    // this reusable call path for memory64 memory.init.
    return false
  }
  guard pop3(stack) is Some((dst, src, size)) else { return false }
  let dst_i64 = if dst.ty == I64 {
    dst
  } else {
    guard emit_op(builder, I64, Uextend, [dst]) is Some(extended) else {
      return false
    }
    extended
  }
  let src_i64 = if src.ty == I64 {
    src
  } else {
    guard emit_op(builder, I64, Uextend, [src]) is Some(extended) else {
      return false
    }
    extended
  }
  let size_i64 = if size.ty == I64 {
    size
  } else {
    guard emit_op(builder, I64, Uextend, [size]) is Some(extended) else {
      return false
    }
    extended
  }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.memory_init)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(memidx),
    builder.iconst_i32(data_idx),
    dst_i64,
    src_i64,
    size_i64,
  ])
  |> ignore
  true
}

///|
fn push_data_drop(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  data_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.data_drop)
  builder.call_symbol(symbol, None, [context, builder.iconst_i32(data_idx)])
  |> ignore
  true
}

///|
fn push_table_grow(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  table_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard table_is_64(table_types, table_idx) is Some(is_table64) else {
    return false
  }
  guard pop_value(stack) is Some(delta) else { return false }
  guard pop_value(stack) is Some(init_value) else { return false }
  let delta_i64 = if delta.ty == I64 {
    delta
  } else {
    guard emit_op(builder, I64, Uextend, [delta]) is Some(extended) else {
      return false
    }
    extended
  }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.table_grow)
  guard builder.call_symbol(symbol, Some(I32), [
      context,
      builder.iconst_i32(table_idx),
      delta_i64,
      init_value,
    ])
    is Some(call_result_i32) else {
    return false
  }
  let result = if is_table64 {
    guard emit_op(builder, I64, Sextend, [call_result_i32]) is Some(extended) else {
      return false
    }
    extended
  } else {
    call_result_i32
  }
  stack.push(result)
  true
}

///|
fn push_table_copy(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  dst_table_idx : Int,
  src_table_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard table_is_64(table_types, dst_table_idx) is Some(_) else { return false }
  guard table_is_64(table_types, src_table_idx) is Some(_) else { return false }
  guard pop3(stack) is Some((dst, src, size)) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.table_copy)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(dst_table_idx),
    builder.iconst_i32(src_table_idx),
    dst,
    src,
    size,
  ])
  |> ignore
  true
}

///|
fn push_table_init(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  table_types : Array[@types.TableType],
  table_idx : Int,
  elem_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard table_is_64(table_types, table_idx) is Some(_) else { return false }
  guard pop3(stack) is Some((dst, src, size)) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.table_init)
  builder.call_symbol(symbol, None, [
    context,
    builder.iconst_i32(table_idx),
    builder.iconst_i32(elem_idx),
    dst,
    src,
    size,
  ])
  |> ignore
  true
}

///|
fn push_elem_drop(
  builder : @milkir.FunctionBuilder,
  runtime_symbols : @wasm_milkir.RuntimeSymbols,
  vmctx : @milkir.Value?,
  elem_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  let symbol = builder
    .get_function()
    .declare_external_symbol(runtime_symbols.elem_drop)
  builder.call_symbol(symbol, None, [context, builder.iconst_i32(elem_idx)])
  |> ignore
  true
}

///|
fn push_ref_null(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  ref_type : @types.ValueType,
) -> Bool {
  let ty = wasm_value_type_to_milkir(ref_type)
  guard emit_op(builder, ty, Iconst(@wasm_milkir.NULL_REF), []) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_ref_is_null(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard pop_value(stack) is Some(ref_value) else { return false }
  guard emit_op(builder, ref_value.ty, Iconst(@wasm_milkir.NULL_REF), [])
    is Some(null_sentinel) else {
    return false
  }
  stack.push(builder.icmp_eq(ref_value, null_sentinel))
  true
}

///|
fn push_ref_func(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  func_idx : Int,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  guard env.runtime_layout() is Some(layout) else { return false }
  let func_table = builder.load_ptr(
    I64,
    context,
    builder.iconst_i64(layout.func_table_offset.to_int64()),
  )
  let raw_func_ptr = builder.load_ptr(
    Ref,
    func_table,
    builder.iconst_i64((func_idx * layout.func_table_entry_stride).to_int64()),
  )
  let tag = builder.iconst(Ref, @wasm_milkir.FUNCREF_TAG)
  guard emit_op(builder, Ref, Bor, [raw_func_ptr, tag]) is Some(result) else {
    return false
  }
  stack.push(result)
  true
}

///|
fn push_ref_as_non_null(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  guard stack.last() is Some(ref_value) else { return false }
  guard emit_op(builder, ref_value.ty, Iconst(@wasm_milkir.NULL_REF), [])
    is Some(null_sentinel) else {
    return false
  }
  let is_null = builder.icmp_eq(ref_value, null_sentinel)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(is_null, trap_block, continue_block)
  builder.switch_to_block(trap_block)
  builder.trap("null reference")
  builder.switch_to_block(continue_block)
  true
}

///|
fn push_ref_eq(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
) -> Bool {
  if !push_int_cmp(builder, stack, Eq) {
    return false
  }
  true
}

///|
fn single_block_result_type(block_type : @types.BlockType) -> @types.ValueType? {
  match block_type {
    Value(ty) => Some(ty)
    _ => None
  }
}

///|
fn push_simple_expr_value(
  builder : @milkir.FunctionBuilder,
  locals : Array[@milkir.Value],
  instr : @types.Instruction,
) -> @milkir.Value? {
  match instr {
    LocalGet(idx) =>
      if idx >= 0 && idx < locals.length() {
        Some(locals[idx])
      } else {
        None
      }
    I32Const(value) => Some(builder.iconst_i32(value))
    I64Const(value) => Some(builder.iconst_i64(value))
    F32Const(value) => Some(builder.fconst_f32(value))
    F64Const(value) => Some(builder.fconst_f64(value))
    RefNull(ref_type) => {
      let ty = wasm_value_type_to_milkir(ref_type)
      emit_op(builder, ty, Iconst(@wasm_milkir.NULL_REF), [])
    }
    _ => None
  }
}

///|
fn push_simple_expr_instr(
  builder : @milkir.FunctionBuilder,
  locals : Array[@milkir.Value],
  expr_stack : Array[@milkir.Value],
  instr : @types.Instruction,
) -> Bool {
  match instr {
    LocalGet(idx) =>
      if idx >= 0 && idx < locals.length() {
        expr_stack.push(locals[idx])
        true
      } else {
        false
      }
    I32Const(value) => {
      expr_stack.push(builder.iconst_i32(value))
      true
    }
    I64Const(value) => {
      expr_stack.push(builder.iconst_i64(value))
      true
    }
    F32Const(value) => {
      expr_stack.push(builder.fconst_f32(value))
      true
    }
    F64Const(value) => {
      expr_stack.push(builder.fconst_f64(value))
      true
    }
    RefNull(ref_type) => {
      guard push_simple_expr_value(builder, locals, RefNull(ref_type))
        is Some(value) else {
        return false
      }
      expr_stack.push(value)
      true
    }
    I32Add => push_i32_binary_opcode(builder, expr_stack, Iadd)
    I64Add => push_binary(expr_stack, fn(lhs, rhs) { builder.iadd(lhs, rhs) })
    I32Sub => push_i32_binary_opcode(builder, expr_stack, Isub)
    I64Sub => push_binary(expr_stack, fn(lhs, rhs) { builder.isub(lhs, rhs) })
    I32Mul => push_i32_binary_opcode(builder, expr_stack, Imul)
    I64Mul => push_binary(expr_stack, fn(lhs, rhs) { builder.imul(lhs, rhs) })
    I64MulWideU => push_binary_opcode(builder, expr_stack, Umulh)
    I64MulWideS => push_binary_opcode(builder, expr_stack, Smulh)
    I32And => push_i32_binary_opcode(builder, expr_stack, Band)
    I64And => push_binary_opcode(builder, expr_stack, Band)
    I32Or => push_i32_binary_opcode(builder, expr_stack, Bor)
    I64Or => push_binary_opcode(builder, expr_stack, Bor)
    I32Xor => push_i32_binary_opcode(builder, expr_stack, Bxor)
    I64Xor => push_binary_opcode(builder, expr_stack, Bxor)
    I32Shl => push_i32_shift_opcode(builder, expr_stack, Ishl)
    I64Shl => push_binary_opcode(builder, expr_stack, Ishl)
    I32ShrS => push_i32_shift_opcode(builder, expr_stack, Sshr)
    I64ShrS => push_binary_opcode(builder, expr_stack, Sshr)
    I32ShrU => push_i32_shift_opcode(builder, expr_stack, Ushr)
    I64ShrU => push_binary_opcode(builder, expr_stack, Ushr)
    I32Rotl => push_i32_shift_opcode(builder, expr_stack, Rotl)
    I64Rotl => push_binary_opcode(builder, expr_stack, Rotl)
    I32Rotr => push_i32_shift_opcode(builder, expr_stack, Rotr)
    I64Rotr => push_binary_opcode(builder, expr_stack, Rotr)
    I32Clz => push_i32_clz(builder, expr_stack)
    I64Clz => push_unary_opcode(builder, expr_stack, Clz)
    I32Ctz => push_i32_ctz(builder, expr_stack)
    I64Ctz => push_unary_opcode(builder, expr_stack, Ctz)
    I32Popcnt => push_i32_popcnt(builder, expr_stack)
    I64Popcnt => push_unary_opcode(builder, expr_stack, Popcnt)
    I32Eqz => {
      guard pop_value(expr_stack) is Some(value) else { return false }
      expr_stack.push(builder.icmp_eq(value, builder.iconst_i32(0)))
      true
    }
    I64Eqz => {
      guard pop_value(expr_stack) is Some(value) else { return false }
      expr_stack.push(builder.icmp_eq(value, builder.iconst_i64(0L)))
      true
    }
    I32Eq | I64Eq => push_int_cmp(builder, expr_stack, Eq)
    I32Ne | I64Ne => push_int_cmp(builder, expr_stack, Ne)
    I32LtS | I64LtS => push_int_cmp(builder, expr_stack, Slt)
    I32LtU | I64LtU => push_int_cmp(builder, expr_stack, Ult)
    I32GtS | I64GtS => push_int_cmp(builder, expr_stack, Sgt)
    I32GtU | I64GtU => push_int_cmp(builder, expr_stack, Ugt)
    I32LeS | I64LeS => push_int_cmp(builder, expr_stack, Sle)
    I32LeU | I64LeU => push_int_cmp(builder, expr_stack, Ule)
    I32GeS | I64GeS => push_int_cmp(builder, expr_stack, Sge)
    I32GeU | I64GeU => push_int_cmp(builder, expr_stack, Uge)
    F32Add | F64Add =>
      push_binary(expr_stack, fn(lhs, rhs) { builder.fadd(lhs, rhs) })
    F32Sub | F64Sub =>
      push_binary(expr_stack, fn(lhs, rhs) { builder.fsub(lhs, rhs) })
    F32Mul | F64Mul =>
      push_binary(expr_stack, fn(lhs, rhs) { builder.fmul(lhs, rhs) })
    F32Div | F64Div => push_binary_opcode(builder, expr_stack, Fdiv)
    F32Min | F64Min => push_binary_opcode(builder, expr_stack, Fmin)
    F32Max | F64Max => push_binary_opcode(builder, expr_stack, Fmax)
    F32Copysign =>
      push_float_copysign(
        builder,
        expr_stack,
        F32,
        I32,
        0x7FFFFFFFL,
        0x80000000U.reinterpret_as_int().to_int64(),
      )
    F64Copysign =>
      push_float_copysign(
        builder,
        expr_stack,
        F64,
        I64,
        0x7FFFFFFFFFFFFFFFL,
        0x8000000000000000UL.reinterpret_as_int64(),
      )
    F32Neg | F64Neg => push_unary_opcode(builder, expr_stack, Fneg)
    F32Abs | F64Abs => push_unary_opcode(builder, expr_stack, Fabs)
    F32Sqrt | F64Sqrt => push_unary_opcode(builder, expr_stack, Fsqrt)
    F32Ceil | F64Ceil => push_unary_opcode(builder, expr_stack, Fceil)
    F32Floor | F64Floor => push_unary_opcode(builder, expr_stack, Ffloor)
    F32Trunc | F64Trunc => push_unary_opcode(builder, expr_stack, Ftrunc)
    F32Nearest | F64Nearest => push_unary_opcode(builder, expr_stack, Fnearest)
    F32Eq | F64Eq => push_float_cmp(builder, expr_stack, Eq)
    F32Ne | F64Ne => push_float_cmp(builder, expr_stack, Ne)
    F32Lt | F64Lt => push_float_cmp(builder, expr_stack, Lt)
    F32Gt | F64Gt => push_float_cmp(builder, expr_stack, Gt)
    F32Le | F64Le => push_float_cmp(builder, expr_stack, Le)
    F32Ge | F64Ge => push_float_cmp(builder, expr_stack, Ge)
    I32WrapI64 => push_unary_opcode_as(builder, expr_stack, I32, Ireduce)
    I64ExtendI32S => push_unary_opcode_as(builder, expr_stack, I64, Sextend)
    I64ExtendI32U => push_unary_opcode_as(builder, expr_stack, I64, Uextend)
    I32Extend8S => push_unary_opcode_as(builder, expr_stack, I32, Sextend8)
    I32Extend16S => push_unary_opcode_as(builder, expr_stack, I32, Sextend16)
    I64Extend8S => push_unary_opcode_as(builder, expr_stack, I64, Sextend8)
    I64Extend16S => push_unary_opcode_as(builder, expr_stack, I64, Sextend16)
    I64Extend32S => push_unary_opcode_as(builder, expr_stack, I64, Sextend32)
    F32DemoteF64 => push_unary_opcode_as(builder, expr_stack, F32, Fdemote)
    F64PromoteF32 => push_unary_opcode_as(builder, expr_stack, F64, Fpromote)
    I32TruncSatF32S | I32TruncSatF64S =>
      push_unary_opcode_as(builder, expr_stack, I32, FcvtToSintSat)
    I32TruncSatF32U | I32TruncSatF64U =>
      push_unary_opcode_as(builder, expr_stack, I32, FcvtToUintSat)
    I64TruncSatF32S | I64TruncSatF64S =>
      push_unary_opcode_as(builder, expr_stack, I64, FcvtToSintSat)
    I64TruncSatF32U | I64TruncSatF64U =>
      push_unary_opcode_as(builder, expr_stack, I64, FcvtToUintSat)
    I32ReinterpretF32 => push_unary_opcode_as(builder, expr_stack, I32, Bitcast)
    I64ReinterpretF64 => push_unary_opcode_as(builder, expr_stack, I64, Bitcast)
    F32ReinterpretI32 => push_unary_opcode_as(builder, expr_stack, F32, Bitcast)
    F64ReinterpretI64 => push_unary_opcode_as(builder, expr_stack, F64, Bitcast)
    RefI31 => push_i31_new(builder, expr_stack)
    AnyConvertExtern | ExternConvertAny =>
      push_unary_opcode(builder, expr_stack, Copy)
    Select | SelectTyped(_) => push_select(builder, expr_stack)
    Drop => {
      guard pop_value(expr_stack) is Some(_) else { return false }
      true
    }
    _ => false
  }
}

///|
fn push_simple_expr_body_value(
  builder : @milkir.FunctionBuilder,
  locals : Array[@milkir.Value],
  body : Array[@types.Instruction],
  expected_ty : @milkir.Type,
) -> @milkir.Value? {
  let expr_stack : Array[@milkir.Value] = []
  for instr in body {
    if !push_simple_expr_instr(builder, locals, expr_stack, instr) {
      return None
    }
  }
  if expr_stack.length() != 1 || expr_stack[0].ty != expected_ty {
    None
  } else {
    Some(expr_stack[0])
  }
}

///|
fn push_simple_if_select(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  locals : Array[@milkir.Value],
  block_type : @types.BlockType,
  then_body : Array[@types.Instruction],
  else_body : Array[@types.Instruction],
) -> Bool {
  guard single_block_result_type(block_type) is Some(result_ty) else {
    return false
  }
  guard pop_value(stack) is Some(cond) else { return false }
  let expected_ty = wasm_value_type_to_milkir(result_ty)
  guard push_simple_expr_body_value(builder, locals, then_body, expected_ty)
    is Some(true_value) else {
    return false
  }
  guard push_simple_expr_body_value(builder, locals, else_body, expected_ty)
    is Some(false_value) else {
    return false
  }
  // TODO(wasm_frontend): lower general structured `if` control flow with block
  // parameters and branch labels. This select form is only for pure expressions.
  stack.push(builder.select(cond, true_value, false_value))
  true
}

///|
fn push_memory_base(
  builder : @milkir.FunctionBuilder,
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value,
  memidx : Int,
) -> @milkir.Value? {
  load_memory_base(builder, env, vmctx, memidx)
}

///|
fn extend_memory_addr(
  builder : @milkir.FunctionBuilder,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
  addr : @milkir.Value,
) -> @milkir.Value? {
  if memory_types[memidx].is_memory64 || addr.ty == I64 {
    Some(addr)
  } else {
    emit_op(builder, I64, Uextend, [addr])
  }
}

///|
fn push_memory_bounds_check(
  builder : @milkir.FunctionBuilder,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
  addr_i64 : @milkir.Value,
  addr_plus_offset : @milkir.Value,
  memory_size : @milkir.Value,
  access_size : Int,
) -> Bool {
  let size_value = builder.iconst_i64(access_size.to_int64())
  let end_addr = builder.iadd(addr_plus_offset, size_value)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  if memory_types[memidx].is_memory64 {
    guard emit_op(builder, I32, Icmp(Uge), [addr_plus_offset, addr_i64])
      is Some(no_overflow1) else {
      return false
    }
    let check2_block = builder.create_block()
    builder.brnz(no_overflow1, check2_block, trap_block)
    builder.switch_to_block(check2_block)
    guard emit_op(builder, I32, Icmp(Uge), [end_addr, addr_plus_offset])
      is Some(no_overflow2) else {
      return false
    }
    let range_block = builder.create_block()
    builder.brnz(no_overflow2, range_block, trap_block)
    builder.switch_to_block(range_block)
  }
  guard emit_op(builder, I32, Icmp(Ule), [end_addr, memory_size])
    is Some(in_bounds) else {
    return false
  }
  builder.brnz(in_bounds, continue_block, trap_block)
  builder.switch_to_block(trap_block)
  builder.trap("memory out of bounds")
  builder.switch_to_block(continue_block)
  true
}

///|
fn memory_effective_addr(
  builder : @milkir.FunctionBuilder,
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value,
  memory_types : Array[@types.MemoryType],
  memidx : Int,
  wasm_addr : @milkir.Value,
  offset : Int64,
  access_size : Int,
) -> @milkir.Value? {
  guard push_memory_base(builder, env, vmctx, memidx) is Some(base) else {
    return None
  }
  guard extend_memory_addr(builder, memory_types, memidx, wasm_addr)
    is Some(addr_i64) else {
    return None
  }
  let offset_value = builder.iconst_i64(offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_value)
  if memidx != 0 || memory_types[memidx].is_memory64 {
    guard load_memory_size_bytes(builder, env, vmctx, memidx)
      is Some(memory_size) else {
      return None
    }
    if !push_memory_bounds_check(
        builder, memory_types, memidx, addr_i64, addr_plus_offset, memory_size, access_size,
      ) {
      return None
    }
  }
  Some(builder.iadd(base, addr_plus_offset))
}

///|
fn push_memory_load(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  mod_ : @types.Module,
  memidx : Int,
  ty : @milkir.Type,
  offset : Int64,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  if memidx < 0 || memidx >= mod_.memories.length() {
    return false
  }
  guard pop_value(stack) is Some(wasm_addr) else { return false }
  guard memory_effective_addr(
      builder,
      env,
      context,
      mod_.memories,
      memidx,
      wasm_addr,
      offset,
      type_byte_size(ty),
    )
    is Some(effective_addr) else {
    return false
  }
  stack.push(builder.load_ptr(ty, effective_addr, builder.iconst_i64(0L)))
  true
}

///|
fn push_memory_load_narrow(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  mod_ : @types.Module,
  memidx : Int,
  result_ty : @milkir.Type,
  bits : Int,
  signed : Bool,
  offset : Int64,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  if memidx < 0 || memidx >= mod_.memories.length() {
    return false
  }
  guard pop_value(stack) is Some(wasm_addr) else { return false }
  guard memory_effective_addr(
      builder,
      env,
      context,
      mod_.memories,
      memidx,
      wasm_addr,
      offset,
      bits / 8,
    )
    is Some(effective_addr) else {
    return false
  }
  stack.push(
    builder.load_ptr_narrow(
      result_ty,
      bits,
      signed,
      effective_addr,
      builder.iconst_i64(0L),
    ),
  )
  true
}

///|
fn push_memory_store(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  mod_ : @types.Module,
  memidx : Int,
  ty : @milkir.Type,
  offset : Int64,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  if memidx < 0 || memidx >= mod_.memories.length() {
    return false
  }
  guard pop_value(stack) is Some(value) else { return false }
  guard pop_value(stack) is Some(wasm_addr) else { return false }
  guard memory_effective_addr(
      builder,
      env,
      context,
      mod_.memories,
      memidx,
      wasm_addr,
      offset,
      type_byte_size(ty),
    )
    is Some(effective_addr) else {
    return false
  }
  builder.store_ptr(ty, effective_addr, value, builder.iconst_i64(0L))
  true
}

///|
fn push_memory_store_narrow(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  env : EmbeddingEnvironment,
  vmctx : @milkir.Value?,
  mod_ : @types.Module,
  memidx : Int,
  bits : Int,
  offset : Int64,
) -> Bool {
  guard vmctx is Some(context) else { return false }
  if memidx < 0 || memidx >= mod_.memories.length() {
    return false
  }
  guard pop_value(stack) is Some(value) else { return false }
  guard pop_value(stack) is Some(wasm_addr) else { return false }
  guard memory_effective_addr(
      builder,
      env,
      context,
      mod_.memories,
      memidx,
      wasm_addr,
      offset,
      bits / 8,
    )
    is Some(effective_addr) else {
    return false
  }
  builder.store_ptr_narrow(bits, effective_addr, value, builder.iconst_i64(0L))
  true
}

///|
fn finish_linear_return(
  builder : @milkir.FunctionBuilder,
  stack : Array[@milkir.Value],
  result_count : Int,
) -> Bool {
  if stack.length() < result_count {
    return false
  }
  let popped : Array[@milkir.Value] = []
  for _ in 0..<result_count {
    guard pop_value(stack) is Some(value) else { return false }
    popped.push(value)
  }
  let results : Array[@milkir.Value] = []
  for i in 0..<popped.length() {
    results.push(popped[popped.length() - 1 - i])
  }
  builder.return_(results)
  true
}

///|
fn append_linear_block_body(
  out : Array[@types.Instruction],
  body : Array[@types.Instruction],
) -> Bool {
  for instr in body {
    match instr {
      Block(_, nested) =>
        if !append_linear_exit_block_body(out, nested) {
          return false
        }
      Loop(_, nested) =>
        if !append_linear_block_body(out, nested) {
          return false
        }
      Br(_)
      | BrIf(_)
      | BrTable(_, _)
      | BrOnNull(_)
      | BrOnNonNull(_)
      | TryTable(_, _, _) =>
        // TODO(wasm_frontend): lower structured labels and branch stack effects
        // directly instead of relying on the full structured translator path.
        return false
      _ => out.push(instr)
    }
  }
  true
}

///|
fn append_linear_exit_block_body(
  out : Array[@types.Instruction],
  body : Array[@types.Instruction],
) -> Bool {
  for i, instr in body {
    match instr {
      Br(depth) =>
        // TODO(wasm_frontend): model full label-stack branch effects. The native
        // frontend can safely flatten only a terminal direct branch to the
        // current block label. Non-terminal branches may leave expression
        // operands that are unreachable in Wasm semantics but still visible to
        // this linear stack model.
        return depth == 0 && i == body.length() - 1
      BrIf(depth) =>
        if depth == 0 && i == body.length() - 1 {
          // At the end of a block, both taken and not-taken paths leave the
          // same label values on the stack. The condition is still consumed.
          out.push(Drop)
          return true
        } else {
          return false
        }
      BrTable(labels, default_label) =>
        if default_label == 0 && labels.all(label => label == 0) {
          // Terminal table branches to the current block all have the same
          // observable effect: consume the selector and leave current label
          // values for the block result.
          out.push(Drop)
          return true
        } else {
          return false
        }
      BrOnNull(depth) | BrOnNonNull(depth) =>
        if depth == 0 && i == body.length() - 1 {
          // At the end of a block, both reference-branch outcomes leave the
          // same reference value as the current block result in the native
          // frontend's uniform reference representation.
          return true
        } else {
          return false
        }
      _ => if !append_linear_block_body(out, [instr]) { return false }
    }
  }
  true
}

///|
fn body_is_nop_only(body : Array[@types.Instruction]) -> Bool {
  body.all(instr => instr is Nop)
}

///|
fn flatten_linear_blocks(
  body : Array[@types.Instruction],
) -> Array[@types.Instruction]? {
  let out : Array[@types.Instruction] = []
  if append_linear_block_body(out, body) {
    Some(out)
  } else {
    None
  }
}

///|
fn try_lower_linear_function(
  env : EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
) -> @milkir.Function? raise LowerError {
  let func_type = get_func_type(mod_, func_local_idx)
  let code = get_code(mod_, func_local_idx)
  guard flatten_linear_blocks(code.body) is Some(body) else { return None }
  let global_types = collect_global_types(mod_)
  let table_types = collect_table_types(mod_)
  let memory_types = collect_memory_types(mod_)
  let runtime_symbols = env.wasm_runtime_symbols()
  let builder = @milkir.FunctionBuilder::new(
    function_name(mod_, func_local_idx),
  )
  let locals : Array[@milkir.Value] = []
  let mut vmctx : @milkir.Value? = None
  if env.hidden_context_param() is Some(hidden_context_type) {
    vmctx = Some(builder.add_param(hidden_context_type))
  }
  for param in func_type.params {
    locals.push(builder.add_param(wasm_value_type_to_milkir(param)))
  }
  for result in func_type.results {
    builder.add_result(wasm_value_type_to_milkir(result))
  }
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  for local_ty in code.locals {
    let milk_ty = wasm_value_type_to_milkir(local_ty)
    guard zero_value(builder, milk_ty) is Some(value) else { return None }
    locals.push(value)
  }
  let stack : Array[@milkir.Value] = []
  let mut terminated = false
  for instr in body {
    if terminated {
      continue
    }
    match instr {
      Nop => ()
      If(block_type, then_body, else_body) =>
        if block_type is Empty &&
          body_is_nop_only(then_body) &&
          body_is_nop_only(else_body) {
          guard pop_value(stack) is Some(_) else { return None }
        } else if !push_simple_if_select(
            builder, stack, locals, block_type, then_body, else_body,
          ) {
          return None
        }
      LocalGet(idx) => {
        if idx < 0 || idx >= locals.length() {
          return None
        }
        stack.push(locals[idx])
      }
      LocalSet(idx) => {
        if idx < 0 || idx >= locals.length() {
          return None
        }
        guard pop_value(stack) is Some(value) else { return None }
        locals[idx] = value
      }
      LocalTee(idx) => {
        if idx < 0 || idx >= locals.length() {
          return None
        }
        guard stack.last() is Some(value) else { return None }
        locals[idx] = value
      }
      GlobalGet(idx) =>
        if !push_global_get(builder, stack, env, vmctx, global_types, idx) {
          return None
        }
      GlobalSet(idx) =>
        if !push_global_set(builder, stack, env, vmctx, global_types, idx) {
          return None
        }
      TableSize(idx) =>
        if !push_table_size(builder, stack, env, vmctx, table_types, idx) {
          return None
        }
      TableGet(idx) =>
        if !push_table_get(builder, stack, env, vmctx, table_types, idx) {
          return None
        }
      TableSet(idx) =>
        if !push_table_set(
            builder, stack, runtime_symbols, vmctx, table_types, idx,
          ) {
          return None
        }
      I32Const(value) => stack.push(builder.iconst_i32(value))
      I64Const(value) => stack.push(builder.iconst_i64(value))
      F32Const(value) => stack.push(builder.fconst_f32(value))
      F64Const(value) => stack.push(builder.fconst_f64(value))
      I32Add => if !push_i32_binary_opcode(builder, stack, Iadd) { return None }
      I64Add =>
        if !push_binary(stack, fn(lhs, rhs) { builder.iadd(lhs, rhs) }) {
          return None
        }
      I32Sub => if !push_i32_binary_opcode(builder, stack, Isub) { return None }
      I64Sub =>
        if !push_binary(stack, fn(lhs, rhs) { builder.isub(lhs, rhs) }) {
          return None
        }
      I32Mul => if !push_i32_binary_opcode(builder, stack, Imul) { return None }
      I64Mul =>
        if !push_binary(stack, fn(lhs, rhs) { builder.imul(lhs, rhs) }) {
          return None
        }
      I64MulWideU =>
        if !push_binary_opcode(builder, stack, Umulh) {
          return None
        }
      I64MulWideS =>
        if !push_binary_opcode(builder, stack, Smulh) {
          return None
        }
      I32DivS | I64DivS =>
        if !push_binary_opcode(builder, stack, Sdiv) {
          return None
        }
      I32DivU | I64DivU =>
        if !push_binary_opcode(builder, stack, Udiv) {
          return None
        }
      I32RemS | I64RemS =>
        if !push_binary_opcode(builder, stack, Srem) {
          return None
        }
      I32RemU | I64RemU =>
        if !push_binary_opcode(builder, stack, Urem) {
          return None
        }
      I32And => if !push_i32_binary_opcode(builder, stack, Band) { return None }
      I64And => if !push_binary_opcode(builder, stack, Band) { return None }
      I32Or => if !push_i32_binary_opcode(builder, stack, Bor) { return None }
      I64Or => if !push_binary_opcode(builder, stack, Bor) { return None }
      I32Xor => if !push_i32_binary_opcode(builder, stack, Bxor) { return None }
      I64Xor => if !push_binary_opcode(builder, stack, Bxor) { return None }
      I32Shl => if !push_i32_shift_opcode(builder, stack, Ishl) { return None }
      I64Shl => if !push_binary_opcode(builder, stack, Ishl) { return None }
      I32ShrS => if !push_i32_shift_opcode(builder, stack, Sshr) { return None }
      I64ShrS => if !push_binary_opcode(builder, stack, Sshr) { return None }
      I32ShrU => if !push_i32_shift_opcode(builder, stack, Ushr) { return None }
      I64ShrU => if !push_binary_opcode(builder, stack, Ushr) { return None }
      I32Rotl => if !push_i32_shift_opcode(builder, stack, Rotl) { return None }
      I64Rotl => if !push_binary_opcode(builder, stack, Rotl) { return None }
      I32Rotr => if !push_i32_shift_opcode(builder, stack, Rotr) { return None }
      I64Rotr => if !push_binary_opcode(builder, stack, Rotr) { return None }
      I32Clz => if !push_i32_clz(builder, stack) { return None }
      I64Clz => if !push_unary_opcode(builder, stack, Clz) { return None }
      I32Ctz => if !push_i32_ctz(builder, stack) { return None }
      I64Ctz => if !push_unary_opcode(builder, stack, Ctz) { return None }
      I32Popcnt => if !push_i32_popcnt(builder, stack) { return None }
      I64Popcnt => if !push_unary_opcode(builder, stack, Popcnt) { return None }
      I32Eqz => {
        guard pop_value(stack) is Some(value) else { return None }
        stack.push(builder.icmp_eq(value, builder.iconst_i32(0)))
      }
      I64Eqz => {
        guard pop_value(stack) is Some(value) else { return None }
        stack.push(builder.icmp_eq(value, builder.iconst_i64(0L)))
      }
      I32Eq | I64Eq => if !push_int_cmp(builder, stack, Eq) { return None }
      I32Ne | I64Ne => if !push_int_cmp(builder, stack, Ne) { return None }
      I32LtS | I64LtS => if !push_int_cmp(builder, stack, Slt) { return None }
      I32LtU | I64LtU => if !push_int_cmp(builder, stack, Ult) { return None }
      I32GtS | I64GtS => if !push_int_cmp(builder, stack, Sgt) { return None }
      I32GtU | I64GtU => if !push_int_cmp(builder, stack, Ugt) { return None }
      I32LeS | I64LeS => if !push_int_cmp(builder, stack, Sle) { return None }
      I32LeU | I64LeU => if !push_int_cmp(builder, stack, Ule) { return None }
      I32GeS | I64GeS => if !push_int_cmp(builder, stack, Sge) { return None }
      I32GeU | I64GeU => if !push_int_cmp(builder, stack, Uge) { return None }
      F32Add | F64Add =>
        if !push_binary(stack, fn(lhs, rhs) { builder.fadd(lhs, rhs) }) {
          return None
        }
      F32Sub | F64Sub =>
        if !push_binary(stack, fn(lhs, rhs) { builder.fsub(lhs, rhs) }) {
          return None
        }
      F32Mul | F64Mul =>
        if !push_binary(stack, fn(lhs, rhs) { builder.fmul(lhs, rhs) }) {
          return None
        }
      F32Div | F64Div =>
        if !push_binary_opcode(builder, stack, Fdiv) {
          return None
        }
      F32Min | F64Min =>
        if !push_binary_opcode(builder, stack, Fmin) {
          return None
        }
      F32Max | F64Max =>
        if !push_binary_opcode(builder, stack, Fmax) {
          return None
        }
      F32Copysign =>
        if !push_float_copysign(
            builder,
            stack,
            F32,
            I32,
            0x7FFFFFFFL,
            0x80000000U.reinterpret_as_int().to_int64(),
          ) {
          return None
        }
      F64Copysign =>
        if !push_float_copysign(
            builder,
            stack,
            F64,
            I64,
            0x7FFFFFFFFFFFFFFFL,
            0x8000000000000000UL.reinterpret_as_int64(),
          ) {
          return None
        }
      F32Neg | F64Neg =>
        if !push_unary_opcode(builder, stack, Fneg) {
          return None
        }
      F32Abs | F64Abs =>
        if !push_unary_opcode(builder, stack, Fabs) {
          return None
        }
      F32Sqrt | F64Sqrt =>
        if !push_unary_opcode(builder, stack, Fsqrt) {
          return None
        }
      F32Ceil | F64Ceil =>
        if !push_unary_opcode(builder, stack, Fceil) {
          return None
        }
      F32Floor | F64Floor =>
        if !push_unary_opcode(builder, stack, Ffloor) {
          return None
        }
      F32Trunc | F64Trunc =>
        if !push_unary_opcode(builder, stack, Ftrunc) {
          return None
        }
      F32Nearest | F64Nearest =>
        if !push_unary_opcode(builder, stack, Fnearest) {
          return None
        }
      F32Eq | F64Eq => if !push_float_cmp(builder, stack, Eq) { return None }
      F32Ne | F64Ne => if !push_float_cmp(builder, stack, Ne) { return None }
      F32Lt | F64Lt => if !push_float_cmp(builder, stack, Lt) { return None }
      F32Gt | F64Gt => if !push_float_cmp(builder, stack, Gt) { return None }
      F32Le | F64Le => if !push_float_cmp(builder, stack, Le) { return None }
      F32Ge | F64Ge => if !push_float_cmp(builder, stack, Ge) { return None }
      I32WrapI64 =>
        if !push_unary_opcode_as(builder, stack, I32, Ireduce) {
          return None
        }
      I64ExtendI32S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend) {
          return None
        }
      I64ExtendI32U =>
        if !push_unary_opcode_as(builder, stack, I64, Uextend) {
          return None
        }
      I32Extend8S =>
        if !push_unary_opcode_as(builder, stack, I32, Sextend8) {
          return None
        }
      I32Extend16S =>
        if !push_unary_opcode_as(builder, stack, I32, Sextend16) {
          return None
        }
      I64Extend8S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend8) {
          return None
        }
      I64Extend16S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend16) {
          return None
        }
      I64Extend32S =>
        if !push_unary_opcode_as(builder, stack, I64, Sextend32) {
          return None
        }
      F32DemoteF64 =>
        if !push_unary_opcode_as(builder, stack, F32, Fdemote) {
          return None
        }
      F64PromoteF32 =>
        if !push_unary_opcode_as(builder, stack, F64, Fpromote) {
          return None
        }
      I32TruncF32S | I32TruncF64S =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToSint) {
          return None
        }
      I32TruncF32U | I32TruncF64U =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToUint) {
          return None
        }
      I64TruncF32S | I64TruncF64S =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToSint) {
          return None
        }
      I64TruncF32U | I64TruncF64U =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToUint) {
          return None
        }
      F32ConvertI32S | F32ConvertI64S =>
        if !push_unary_opcode_as(builder, stack, F32, SintToFcvt) {
          return None
        }
      F32ConvertI32U | F32ConvertI64U =>
        if !push_unary_opcode_as(builder, stack, F32, UintToFcvt) {
          return None
        }
      F64ConvertI32S | F64ConvertI64S =>
        if !push_unary_opcode_as(builder, stack, F64, SintToFcvt) {
          return None
        }
      F64ConvertI32U | F64ConvertI64U =>
        if !push_unary_opcode_as(builder, stack, F64, UintToFcvt) {
          return None
        }
      I32TruncSatF32S | I32TruncSatF64S =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToSintSat) {
          return None
        }
      I32TruncSatF32U | I32TruncSatF64U =>
        if !push_unary_opcode_as(builder, stack, I32, FcvtToUintSat) {
          return None
        }
      I64TruncSatF32S | I64TruncSatF64S =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToSintSat) {
          return None
        }
      I64TruncSatF32U | I64TruncSatF64U =>
        if !push_unary_opcode_as(builder, stack, I64, FcvtToUintSat) {
          return None
        }
      I32ReinterpretF32 =>
        if !push_unary_opcode_as(builder, stack, I32, Bitcast) {
          return None
        }
      I64ReinterpretF64 =>
        if !push_unary_opcode_as(builder, stack, I64, Bitcast) {
          return None
        }
      F32ReinterpretI32 =>
        if !push_unary_opcode_as(builder, stack, F32, Bitcast) {
          return None
        }
      F64ReinterpretI64 =>
        if !push_unary_opcode_as(builder, stack, F64, Bitcast) {
          return None
        }
      RefI31 => if !push_i31_new(builder, stack) { return None }
      I31GetS => if !push_i31_get(builder, stack, true) { return None }
      I31GetU => if !push_i31_get(builder, stack, false) { return None }
      AnyConvertExtern | ExternConvertAny =>
        if !push_unary_opcode(builder, stack, Copy) {
          return None
        }
      Call(func_idx) =>
        if !push_direct_call(builder, stack, env, mod_, vmctx, func_idx) {
          return None
        }
      I32Load(memidx, _, offset) =>
        if !push_memory_load(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I32,
            offset,
          ) {
          return None
        }
      I64Load(memidx, _, offset) =>
        if !push_memory_load(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            offset,
          ) {
          return None
        }
      F32Load(memidx, _, offset) =>
        if !push_memory_load(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            F32,
            offset,
          ) {
          return None
        }
      F64Load(memidx, _, offset) =>
        if !push_memory_load(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            F64,
            offset,
          ) {
          return None
        }
      I32Load8S(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I32,
            8,
            true,
            offset,
          ) {
          return None
        }
      I32Load8U(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I32,
            8,
            false,
            offset,
          ) {
          return None
        }
      I32Load16S(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I32,
            16,
            true,
            offset,
          ) {
          return None
        }
      I32Load16U(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I32,
            16,
            false,
            offset,
          ) {
          return None
        }
      I64Load8S(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            8,
            true,
            offset,
          ) {
          return None
        }
      I64Load8U(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            8,
            false,
            offset,
          ) {
          return None
        }
      I64Load16S(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            16,
            true,
            offset,
          ) {
          return None
        }
      I64Load16U(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            16,
            false,
            offset,
          ) {
          return None
        }
      I64Load32S(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            32,
            true,
            offset,
          ) {
          return None
        }
      I64Load32U(memidx, _, offset) =>
        if !push_memory_load_narrow(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            32,
            false,
            offset,
          ) {
          return None
        }
      I32Store(memidx, _, offset) =>
        if !push_memory_store(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I32,
            offset,
          ) {
          return None
        }
      I64Store(memidx, _, offset) =>
        if !push_memory_store(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            I64,
            offset,
          ) {
          return None
        }
      F32Store(memidx, _, offset) =>
        if !push_memory_store(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            F32,
            offset,
          ) {
          return None
        }
      F64Store(memidx, _, offset) =>
        if !push_memory_store(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            F64,
            offset,
          ) {
          return None
        }
      V128Load(memidx, _, offset) =>
        if !push_memory_load(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            V128,
            offset,
          ) {
          return None
        }
      V128Store(memidx, _, offset) =>
        if !push_memory_store(
            builder,
            stack,
            env,
            vmctx,
            mod_,
            memidx,
            V128,
            offset,
          ) {
          return None
        }
      I32Store8(memidx, _, offset) =>
        if !push_memory_store_narrow(
            builder, stack, env, vmctx, mod_, memidx, 8, offset,
          ) {
          return None
        }
      I32Store16(memidx, _, offset) =>
        if !push_memory_store_narrow(
            builder, stack, env, vmctx, mod_, memidx, 16, offset,
          ) {
          return None
        }
      I64Store8(memidx, _, offset) =>
        if !push_memory_store_narrow(
            builder, stack, env, vmctx, mod_, memidx, 8, offset,
          ) {
          return None
        }
      I64Store16(memidx, _, offset) =>
        if !push_memory_store_narrow(
            builder, stack, env, vmctx, mod_, memidx, 16, offset,
          ) {
          return None
        }
      I64Store32(memidx, _, offset) =>
        if !push_memory_store_narrow(
            builder, stack, env, vmctx, mod_, memidx, 32, offset,
          ) {
          return None
        }
      MemorySize(memidx) =>
        if !push_memory_size(builder, stack, env, vmctx, memory_types, memidx) {
          return None
        }
      MemoryGrow(memidx) =>
        if !push_memory_grow(
            builder, stack, runtime_symbols, vmctx, memory_types, memidx,
          ) {
          return None
        }
      MemoryFill(memidx) =>
        if !push_memory_fill(
            builder, stack, runtime_symbols, vmctx, memory_types, memidx,
          ) {
          return None
        }
      MemoryCopy(dst_memidx, src_memidx) =>
        if !push_memory_copy(
            builder, stack, runtime_symbols, vmctx, memory_types, dst_memidx, src_memidx,
          ) {
          return None
        }
      MemoryInit(memidx, data_idx) =>
        if !push_memory_init(
            builder, stack, runtime_symbols, vmctx, memory_types, memidx, data_idx,
          ) {
          return None
        }
      DataDrop(data_idx) =>
        if !push_data_drop(builder, runtime_symbols, vmctx, data_idx) {
          return None
        }
      TableGrow(table_idx) =>
        if !push_table_grow(
            builder, stack, runtime_symbols, vmctx, table_types, table_idx,
          ) {
          return None
        }
      TableFill(table_idx) =>
        if !push_table_fill(
            builder, stack, runtime_symbols, vmctx, table_types, table_idx,
          ) {
          return None
        }
      TableCopy(dst_table_idx, src_table_idx) =>
        if !push_table_copy(
            builder, stack, runtime_symbols, vmctx, table_types, dst_table_idx, src_table_idx,
          ) {
          return None
        }
      TableInit(table_idx, elem_idx) =>
        if !push_table_init(
            builder, stack, runtime_symbols, vmctx, table_types, table_idx, elem_idx,
          ) {
          return None
        }
      ElemDrop(elem_idx) =>
        if !push_elem_drop(builder, runtime_symbols, vmctx, elem_idx) {
          return None
        }
      RefNull(ref_type) =>
        if !push_ref_null(builder, stack, ref_type) {
          return None
        }
      RefIsNull => if !push_ref_is_null(builder, stack) { return None }
      RefFunc(func_idx) =>
        if !push_ref_func(builder, stack, env, vmctx, func_idx) {
          return None
        }
      RefAsNonNull => if !push_ref_as_non_null(builder, stack) { return None }
      RefEqInstr => if !push_ref_eq(builder, stack) { return None }
      Select | SelectTyped(_) => if !push_select(builder, stack) { return None }
      Drop => {
        guard pop_value(stack) is Some(_) else { return None }
      }
      Return => {
        if !finish_linear_return(builder, stack, func_type.results.length()) {
          return None
        }
        terminated = true
      }
      Unreachable => {
        builder.trap("unreachable")
        terminated = true
      }
      _ =>
        // TODO(wasm_frontend): port the remaining Wasm operators/control-flow
        // into native MilkIR construction.
        return None
    }
  }
  if !terminated &&
    !finish_linear_return(builder, stack, func_type.results.length()) {
    return None
  }
  Some(builder.get_function())
}
