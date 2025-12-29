// FuncEnvironment - handles Wasm semantic operations by desugaring to IR primitives
//
// This module implements Standard desugaring where high-level Wasm operations
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

// Multi-memory support offsets

///|
pub const VMCTX_MEMORIES_OFFSET : Int = 80

///|
pub const VMCTX_MEMORY_SIZES_OFFSET : Int = 88

///|
pub const VMCTX_MEMORY_MAX_SIZES_OFFSET : Int = 96

///|
pub const VMCTX_MEMORY_COUNT_OFFSET : Int = 104

///|
/// WASM page size in bytes (64KB)
pub const WASM_PAGE_SIZE : Int = 65536

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
  { global_types, }
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
  is_table64? : Bool = false,
) -> Value {
  if table_idx == 0 {
    // Fast path for table 0
    let offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE0_ELEMENTS_OFFSET.to_int64(),
    )
    let size_i64 = builder.load_ptr(Type::I64, vmctx, offset)
    // For table64, return i64; for table32, reduce to i32
    if is_table64 {
      size_i64
    } else {
      builder.ireduce(Type::I32, size_i64)
    }
  } else {
    // General path: load from table_sizes array
    let sizes_offset = builder.iconst(
      Type::I64,
      VMCTX_TABLE_SIZES_OFFSET.to_int64(),
    )
    let sizes_ptr = builder.load_ptr(Type::I64, vmctx, sizes_offset)
    let elem_offset = builder.iconst(Type::I64, (table_idx * 8).to_int64())
    let size_i64 = builder.load_ptr(Type::I64, sizes_ptr, elem_offset)
    if is_table64 {
      size_i64
    } else {
      builder.ireduce(Type::I32, size_i64)
    }
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
  is_table64? : Bool = false,
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
  // For table64, elem_idx is already i64; for table32, extend to i64
  let elem_idx_i64 = if is_table64 {
    elem_idx
  } else {
    builder.uextend(Type::I64, elem_idx)
  }
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
  is_table64? : Bool = false,
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
  // For table64, elem_idx is already i64; for table32, extend to i64
  let elem_idx_i64 = if is_table64 {
    elem_idx
  } else {
    builder.uextend(Type::I64, elem_idx)
  }
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

// ============ Memory Operations ============

///|
/// Helper to load memory base and size for a given memidx
/// For memidx 0: use fast path (direct vmctx fields)
/// For memidx > 0: load from memories/memory_sizes arrays
fn load_memory_base_and_size(
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
) -> (Value, Value) {
  if memidx == 0 {
    // Fast path for memory 0
    let base_offset = builder.iconst(
      Type::I64,
      VMCTX_MEMORY_BASE_OFFSET.to_int64(),
    )
    let base = builder.load_ptr(Type::I64, vmctx, base_offset)
    let size_offset = builder.iconst(
      Type::I64,
      VMCTX_MEMORY_SIZE_OFFSET.to_int64(),
    )
    let size = builder.load_ptr(Type::I64, vmctx, size_offset)
    (base, size)
  } else {
    // General path: load from memories/memory_sizes arrays
    let memories_offset = builder.iconst(
      Type::I64,
      VMCTX_MEMORIES_OFFSET.to_int64(),
    )
    let memories_ptr = builder.load_ptr(Type::I64, vmctx, memories_offset)
    let idx_offset = builder.iconst(Type::I64, (memidx * 8).to_int64())
    let base = builder.load_ptr(Type::I64, memories_ptr, idx_offset)
    let sizes_offset = builder.iconst(
      Type::I64,
      VMCTX_MEMORY_SIZES_OFFSET.to_int64(),
    )
    let sizes_ptr = builder.load_ptr(Type::I64, vmctx, sizes_offset)
    let size = builder.load_ptr(Type::I64, sizes_ptr, idx_offset)
    (base, size)
  }
}

///|
/// Get the byte size for a type
fn type_byte_size(ty : Type) -> Int {
  match ty {
    I32 => 4
    I64 => 8
    F32 => 4
    F64 => 8
    V128 => 16 // SIMD vector
    FuncRef | ExternRef => 8 // Reference types are pointer-sized
  }
}

///|
/// Emit bounds check and return effective address for memory access
/// This is a public helper for SIMD and other complex load operations
pub fn FuncEnvironment::emit_bounds_check(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  wasm_addr : Value,
  offset : Int64,
  access_size : Int,
) -> Value {
  let (memory_base, memory_size) = load_memory_base_and_size(
    builder, vmctx, memidx,
  )

  // Extend wasm_addr (i32) to i64
  let addr_i64 = builder.uextend(Type::I64, wasm_addr)

  // Calculate end address for bounds check: addr + offset + access_size
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  let size_val = builder.iconst(Type::I64, access_size.to_int64())
  let end_addr = builder.iadd(addr_plus_offset, size_val)

  // Bounds check: trap if end_addr > memory_size
  let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("memory out of bounds")

  // Continue block
  builder.switch_to_block(continue_block)

  // Return effective address: memory_base + addr + offset
  builder.iadd(memory_base, addr_plus_offset)
}

///|
/// Translate memory load to IR primitives:
/// 1. Load memory_base and memory_size from vmctx
/// 2. Bounds check: trap if addr + offset + size > memory_size
/// 3. Calculate effective address: memory_base + addr + offset
/// 4. LoadPtr
pub fn FuncEnvironment::translate_memory_load(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  ty : Type,
  wasm_addr : Value,
  offset : Int64,
) -> Value {
  let (memory_base, memory_size) = load_memory_base_and_size(
    builder, vmctx, memidx,
  )
  let access_size = type_byte_size(ty)

  // Extend wasm_addr (i32) to i64
  let addr_i64 = builder.uextend(Type::I64, wasm_addr)

  // Calculate end address for bounds check: addr + offset + access_size
  // offset is Int64 (supports memory64 64-bit offsets)
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  let size_val = builder.iconst(Type::I64, access_size.to_int64())
  let end_addr = builder.iadd(addr_plus_offset, size_val)

  // Bounds check: trap if end_addr > memory_size
  let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("memory out of bounds")

  // Continue block: perform the load
  builder.switch_to_block(continue_block)

  // Calculate effective address: memory_base + addr + offset
  let effective_addr = builder.iadd(memory_base, addr_plus_offset)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.load_ptr(ty, effective_addr, zero_offset)
}

///|
/// Translate memory store to IR primitives:
/// 1. Load memory_base and memory_size from vmctx
/// 2. Bounds check: trap if addr + offset + size > memory_size
/// 3. Calculate effective address: memory_base + addr + offset
/// 4. StorePtr
pub fn FuncEnvironment::translate_memory_store(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  ty : Type,
  wasm_addr : Value,
  value : Value,
  offset : Int64,
) -> Unit {
  let (memory_base, memory_size) = load_memory_base_and_size(
    builder, vmctx, memidx,
  )
  let access_size = type_byte_size(ty)

  // Extend wasm_addr (i32) to i64
  let addr_i64 = builder.uextend(Type::I64, wasm_addr)

  // Calculate end address for bounds check: addr + offset + access_size
  // offset is Int64 (supports memory64 64-bit offsets)
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  let size_val = builder.iconst(Type::I64, access_size.to_int64())
  let end_addr = builder.iadd(addr_plus_offset, size_val)

  // Bounds check: trap if end_addr > memory_size
  let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("memory out of bounds")

  // Continue block: perform the store
  builder.switch_to_block(continue_block)

  // Calculate effective address: memory_base + addr + offset
  let effective_addr = builder.iadd(memory_base, addr_plus_offset)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.store_ptr(ty, effective_addr, value, zero_offset)
}

///|
/// Translate narrow memory load (i32.load8_s, i32.load16_u, etc.) to IR primitives
pub fn FuncEnvironment::translate_memory_load_narrow(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  result_ty : Type,
  narrow_bits : Int,
  signed : Bool,
  wasm_addr : Value,
  offset : Int64,
) -> Value {
  let (memory_base, memory_size) = load_memory_base_and_size(
    builder, vmctx, memidx,
  )
  let access_size = narrow_bits / 8

  // Extend wasm_addr (i32) to i64
  let addr_i64 = builder.uextend(Type::I64, wasm_addr)

  // Calculate end address for bounds check
  // offset is Int64 (supports memory64 64-bit offsets)
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  let size_val = builder.iconst(Type::I64, access_size.to_int64())
  let end_addr = builder.iadd(addr_plus_offset, size_val)

  // Bounds check
  let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("memory out of bounds")

  // Continue block: perform the load
  builder.switch_to_block(continue_block)

  // Calculate effective address
  let effective_addr = builder.iadd(memory_base, addr_plus_offset)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.load_ptr_narrow(
    result_ty, narrow_bits, signed, effective_addr, zero_offset,
  )
}

///|
/// Translate narrow memory store (i32.store8, i32.store16, etc.) to IR primitives
pub fn FuncEnvironment::translate_memory_store_narrow(
  _self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  narrow_bits : Int,
  wasm_addr : Value,
  value : Value,
  offset : Int64,
) -> Unit {
  let (memory_base, memory_size) = load_memory_base_and_size(
    builder, vmctx, memidx,
  )
  let access_size = narrow_bits / 8

  // Extend wasm_addr (i32) to i64
  let addr_i64 = builder.uextend(Type::I64, wasm_addr)

  // Calculate end address for bounds check
  // offset is Int64 (supports memory64 64-bit offsets)
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  let size_val = builder.iconst(Type::I64, access_size.to_int64())
  let end_addr = builder.iadd(addr_plus_offset, size_val)

  // Bounds check
  let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
  let trap_block = builder.create_block()
  let continue_block = builder.create_block()
  builder.brnz(in_bounds, continue_block, trap_block)

  // Trap block
  builder.switch_to_block(trap_block)
  builder.trap("memory out of bounds")

  // Continue block: perform the store
  builder.switch_to_block(continue_block)

  // Calculate effective address
  let effective_addr = builder.iadd(memory_base, addr_plus_offset)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.store_ptr_narrow(narrow_bits, effective_addr, value, zero_offset)
}

///|
/// Translate memory.size to IR primitives:
/// Uses existing MemorySize IR opcode (lowering handles reading from vmctx)
pub fn FuncEnvironment::translate_memory_size(
  _self : FuncEnvironment,
  builder : IRBuilder,
  memidx : Int,
) -> Value {
  builder.memory_size(memidx)
}

///|
/// Translate memory.grow to IR primitives:
/// Uses existing MemoryGrow IR opcode (lowering handles C call)
pub fn FuncEnvironment::translate_memory_grow(
  _self : FuncEnvironment,
  builder : IRBuilder,
  memidx : Int,
  delta : Value,
  max_pages : Int?,
) -> Value {
  match max_pages {
    Some(max) => builder.memory_grow(memidx, delta, max_pages=max)
    None => builder.memory_grow(memidx, delta)
  }
}

///|
/// Translate memory.fill to IR primitives:
/// Uses existing MemoryFill IR opcode (lowering handles C call)
pub fn FuncEnvironment::translate_memory_fill(
  _self : FuncEnvironment,
  builder : IRBuilder,
  memidx : Int,
  dst : Value,
  val : Value,
  size : Value,
) -> Unit {
  builder.memory_fill(memidx, dst, val, size)
}

///|
/// Translate memory.copy to IR primitives:
/// Uses existing MemoryCopy IR opcode (lowering handles C call)
pub fn FuncEnvironment::translate_memory_copy(
  _self : FuncEnvironment,
  builder : IRBuilder,
  dst_memidx : Int,
  src_memidx : Int,
  dst : Value,
  src : Value,
  size : Value,
) -> Unit {
  builder.memory_copy(dst_memidx, src_memidx, dst, src, size)
}
