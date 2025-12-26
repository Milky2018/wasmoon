// FuncEnvironment - handles Wasm semantic operations by desugaring to IR primitives
//
// This module implements Cranelift-style desugaring where high-level Wasm operations
// (global.get, table.get, etc.) are translated to lower-level IR primitives
// (LoadPtr, StorePtr, CallPtr) during IR translation, not during lowering.
//
// Benefits:
// - Simpler lowering phase (no special cases for these operations)
// - Centralized VMContext layout knowledge
// - Easier to change ABI (modify here, not scattered across lowering/emit)

///|
/// VMContext structure offsets (matching jit_ffi.h and vcode/abi)
/// These define the layout of the VMContext structure passed to JIT functions
pub const VMCTX_MEMORY_BASE_OFFSET : Int = 0

///|
pub const VMCTX_MEMORY_SIZE_OFFSET : Int = 8

///|
pub const VMCTX_FUNC_TABLE_OFFSET : Int = 16

///|
pub const VMCTX_TABLE0_BASE_OFFSET : Int = 24

///|
pub const VMCTX_TABLE0_ELEMENTS_OFFSET : Int = 32

///|
pub const VMCTX_GLOBALS_OFFSET : Int = 40

///|
pub const VMCTX_TABLES_OFFSET : Int = 48

///|
pub const VMCTX_TABLE_COUNT_OFFSET : Int = 56

///|
pub const VMCTX_TABLE_SIZES_OFFSET : Int = 64

///|
/// Global variable stride (each global occupies 16 bytes for alignment)
pub const GLOBAL_STRIDE : Int = 16

///|
/// Table entry stride (each entry is 16 bytes: func_ptr + type_idx)
pub const TABLE_ENTRY_STRIDE : Int = 16

///|
/// FuncEnvironment holds VMContext layout info used during IR translation to
/// desugar Wasm operations.
pub(all) struct FuncEnvironment {
  // Global variable types (for determining load/store width)
  global_types : Array[@types.GlobalType]
}

///|
pub fn FuncEnvironment::new(
  global_types : Array[@types.GlobalType],
) -> FuncEnvironment {
  {
    global_types,
  }
}

// ============ Global Variable Operations ============

///|
/// Translate global.get to IR primitives:
/// 1. Load globals_ptr from vmctx
/// 2. Load value from globals_ptr + (global_idx * 16)
pub fn FuncEnvironment::translate_global_get(
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  global_idx : Int,
) -> Value {
  let global_type = self.global_types[global_idx]
  let ty = Type::from_wasm(global_type.value_type)

  // Load globals_ptr from vmctx
  let globals_offset = builder.iconst(
    Type::I64,
    VMCTX_GLOBALS_OFFSET.to_int64(),
  )
  let globals_ptr = builder.load_ptr(Type::I64, vmctx, globals_offset)

  // Load value from globals_ptr + field_offset
  let field_offset = builder.iconst(
    Type::I64,
    (global_idx * GLOBAL_STRIDE).to_int64(),
  )
  builder.load_ptr(ty, globals_ptr, field_offset)
}

///|
/// Translate global.set to IR primitives:
/// 1. Load globals_ptr from vmctx
/// 2. Store value to globals_ptr + (global_idx * 16)
pub fn FuncEnvironment::translate_global_set(
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  global_idx : Int,
  value : Value,
) -> Unit {
  let global_type = self.global_types[global_idx]
  let ty = Type::from_wasm(global_type.value_type)

  // Load globals_ptr from vmctx
  let globals_offset = builder.iconst(
    Type::I64,
    VMCTX_GLOBALS_OFFSET.to_int64(),
  )
  let globals_ptr = builder.load_ptr(Type::I64, vmctx, globals_offset)

  // Store value to globals_ptr + field_offset
  let field_offset = builder.iconst(
    Type::I64,
    (global_idx * GLOBAL_STRIDE).to_int64(),
  )
  builder.store_ptr(ty, globals_ptr, value, field_offset)
}

// ============ Table Operations ============

///|
/// Translate table.size to IR primitives:
/// For table 0: Load from vmctx.table0_elements
/// For table N: Load from vmctx.table_sizes[N]
pub fn FuncEnvironment::translate_table_size(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  table_idx : Int,
) -> Value {
  if table_idx == 0 {
    // Fast path for table 0
    let offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE0_ELEMENTS_OFFSET.to_int64(),
    )
    let size_i64 = builder.load_ptr(Type::I64, vmctx, offset)
    builder.ireduce(Type::I32, size_i64)
  } else {
    // General path: load from table_sizes array
    let sizes_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE_SIZES_OFFSET.to_int64(),
    )
    let sizes_ptr = builder.load_ptr(Type::I64, vmctx, sizes_offset)
    let elem_offset = builder.iconst(Type::I64, (table_idx * 8).to_int64())
    let size_i64 = builder.load_ptr(Type::I64, sizes_ptr, elem_offset)
    builder.ireduce(Type::I32, size_i64)
  }
}

///|
/// Translate table.get to IR primitives:
/// 1. Load table_size, check bounds
/// 2. Load table_base
/// 3. Calculate address: table_base + elem_idx * 16
/// 4. Load value
pub fn FuncEnvironment::translate_table_get(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  table_idx : Int,
  elem_idx : Value,
) -> Value {
  // Get table size for bounds check
  let (table_size, table_base) = if table_idx == 0 {
    // Fast path for table 0
    let size_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE0_ELEMENTS_OFFSET.to_int64(),
    )
    let size = builder.load_ptr(Type::I64, vmctx, size_offset)
    let base_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE0_BASE_OFFSET.to_int64(),
    )
    let base = builder.load_ptr(Type::I64, vmctx, base_offset)
    (size, base)
  } else {
    // General path: load from tables array
    let sizes_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE_SIZES_OFFSET.to_int64(),
    )
    let sizes_ptr = builder.load_ptr(Type::I64, vmctx, sizes_offset)
    let idx_offset = builder.iconst(Type::I64, (table_idx * 8).to_int64())
    let size = builder.load_ptr(Type::I64, sizes_ptr, idx_offset)
    let tables_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLES_OFFSET.to_int64(),
    )
    let tables_ptr = builder.load_ptr(Type::I64, vmctx, tables_offset)
    let base = builder.load_ptr(Type::I64, tables_ptr, idx_offset)
    (size, base)
  }

  // Bounds check: trap if elem_idx >= table_size
  let elem_idx_i64 = builder.uextend(Type::I64, elem_idx)
  let in_bounds = builder.icmp(IntCC::Ult, elem_idx_i64, table_size)

  // Create trap and continue blocks
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("table out of bounds")

  // Continue block: load the value
  builder.switch_to_block(continue_block)

  // Calculate address: table_base + elem_idx * 16
  let stride = builder.iconst(Type::I64, TABLE_ENTRY_STRIDE.to_int64())
  let byte_offset = builder.imul(elem_idx_i64, stride)
  let addr = builder.iadd(table_base, byte_offset)

  // Load the funcref value (first 8 bytes of entry)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.load_ptr(Type::I64, addr, zero_offset)
}

///|
/// Translate table.set to IR primitives:
/// 1. Load table_size, check bounds
/// 2. Load table_base
/// 3. Calculate address: table_base + elem_idx * 16
/// 4. Store value
pub fn FuncEnvironment::translate_table_set(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  table_idx : Int,
  elem_idx : Value,
  value : Value,
) -> Unit {
  // Get table size for bounds check
  let (table_size, table_base) = if table_idx == 0 {
    let size_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE0_ELEMENTS_OFFSET.to_int64(),
    )
    let size = builder.load_ptr(Type::I64, vmctx, size_offset)
    let base_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE0_BASE_OFFSET.to_int64(),
    )
    let base = builder.load_ptr(Type::I64, vmctx, base_offset)
    (size, base)
  } else {
    let sizes_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE_SIZES_OFFSET.to_int64(),
    )
    let sizes_ptr = builder.load_ptr(Type::I64, vmctx, sizes_offset)
    let idx_offset = builder.iconst(Type::I64, (table_idx * 8).to_int64())
    let size = builder.load_ptr(Type::I64, sizes_ptr, idx_offset)
    let tables_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLES_OFFSET.to_int64(),
    )
    let tables_ptr = builder.load_ptr(Type::I64, vmctx, tables_offset)
    let base = builder.load_ptr(Type::I64, tables_ptr, idx_offset)
    (size, base)
  }

  // Bounds check
  let elem_idx_i64 = builder.uextend(Type::I64, elem_idx)
  let in_bounds = builder.icmp(IntCC::Ult, elem_idx_i64, table_size)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("table out of bounds")

  // Continue block: store the value
  builder.switch_to_block(continue_block)

  // Calculate address: table_base + elem_idx * 16
  let stride = builder.iconst(Type::I64, TABLE_ENTRY_STRIDE.to_int64())
  let byte_offset = builder.imul(elem_idx_i64, stride)
  let addr = builder.iadd(table_base, byte_offset)

  // Store the funcref value (first 8 bytes of entry)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.store_ptr(Type::I64, addr, value, zero_offset)
}
