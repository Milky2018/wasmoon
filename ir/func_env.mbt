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
pub const VMCTX_MEMORY0_OFFSET : Int = 0

///|
pub const VMCTX_FUNC_TABLE_OFFSET : Int = 8

///|
pub const VMCTX_TABLE0_BASE_OFFSET : Int = 16

///|
pub const VMCTX_TABLE0_ELEMENTS_OFFSET : Int = 24

///|
pub const VMCTX_GLOBALS_OFFSET : Int = 32

///|
pub const VMCTX_TABLES_OFFSET : Int = 40

///|
pub const VMCTX_TABLE_COUNT_OFFSET : Int = 48

///|
pub const VMCTX_TABLE_SIZES_OFFSET : Int = 56

///|
pub const VMCTX_TABLE_MAX_SIZES_OFFSET : Int = 64

// Multi-memory support offsets

///|
pub const VMCTX_MEMORIES_OFFSET : Int = 72

///|
pub const VMCTX_MEMORY_COUNT_OFFSET : Int = 80

// Offsets within `wasmoon_memory_t` (see jit_ffi.h)

///|
pub const MEMORY_BASE_OFFSET : Int = 0

///|
pub const MEMORY_CURRENT_LENGTH_OFFSET : Int = 8

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
struct FuncEnvironment {
  // Global variable types (for determining load/store width)
  global_types : Array[@types.GlobalType]
  // Minimum guaranteed memory size in bytes for each memory index
  // Used to eliminate bounds checks for constant addresses within this range
  memory_mins : Array[Int64]
  // Whether each memory uses 64-bit addressing (memory64 proposal)
  memory_is_64 : Array[Bool]
  // Logical page size log2 for each memory (custom-page-sizes proposal)
  memory_page_size_log2 : Array[Int]
  // Shared trap block for memory out-of-bounds errors
  // All bounds checks in the same function share this block to reduce CFG size
  mut memory_trap_block : Block?
  // Shared trap block for atomic unaligned accesses
  mut atomic_unaligned_trap_block : Block?
}

///|
pub fn FuncEnvironment::new(
  global_types : Array[@types.GlobalType],
  memory_mins? : Array[Int64] = [],
  memory_is_64? : Array[Bool] = [],
  memory_page_size_log2? : Array[Int] = [],
) -> FuncEnvironment {
  {
    global_types,
    memory_mins,
    memory_is_64,
    memory_page_size_log2,
    memory_trap_block: None,
    atomic_unaligned_trap_block: None,
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
/// Helper to load memory size in bytes for a given memidx.
/// For memidx 0: use fast path (direct vmctx field)
/// For memidx > 0: load from memories array
fn load_memory_size(builder : IRBuilder, vmctx : Value, memidx : Int) -> Value {
  let mem_ptr = if memidx == 0 {
    let mem0_off = builder.iconst(Type::I64, VMCTX_MEMORY0_OFFSET.to_int64())
    builder.load_ptr(Type::I64, vmctx, mem0_off)
  } else {
    let memories_off = builder.iconst(
      Type::I64,
      VMCTX_MEMORIES_OFFSET.to_int64(),
    )
    let memories_ptr = builder.load_ptr(Type::I64, vmctx, memories_off)
    let idx_off = builder.iconst(Type::I64, (memidx * 8).to_int64())
    builder.load_ptr(Type::I64, memories_ptr, idx_off)
  }
  let size_off = builder.iconst(
    Type::I64,
    MEMORY_CURRENT_LENGTH_OFFSET.to_int64(),
  )
  builder.load_ptr(Type::I64, mem_ptr, size_off)
}

///|
/// Whether JIT should rely on guard pages (no explicit bounds checks) for memory access.
/// Currently only enabled for memory 0 and memory32.
fn FuncEnvironment::use_guard_pages(
  self : FuncEnvironment,
  memidx : Int,
) -> Bool {
  if memidx != 0 {
    return false
  }
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  if is_memory64 {
    return false
  }
  // Guarded allocations currently assume 64KiB wasm pages.
  let l2 = if memidx < self.memory_page_size_log2.length() {
    self.memory_page_size_log2[memidx]
  } else {
    16
  }
  l2 == 16
}

///|
/// Get or create a shared trap block for memory out-of-bounds errors.
/// All bounds checks in the same function share this block to reduce CFG size.
fn FuncEnvironment::get_or_create_memory_trap_block(
  self : FuncEnvironment,
  builder : IRBuilder,
) -> Block {
  match self.memory_trap_block {
    Some(block) => block
    None => {
      let trap_block = builder.create_block()
      let current = builder.current_block // save current position
      builder.switch_to_block(trap_block)
      builder.trap("memory out of bounds")
      match current {
        Some(block) => builder.switch_to_block(block) // restore position
        None => ()
      }
      self.memory_trap_block = Some(trap_block)
      trap_block
    }
  }
}

///|
/// Get or create a shared trap block for unaligned atomic accesses.
fn FuncEnvironment::get_or_create_atomic_unaligned_trap_block(
  self : FuncEnvironment,
  builder : IRBuilder,
) -> Block {
  match self.atomic_unaligned_trap_block {
    Some(block) => block
    None => {
      let trap_block = builder.create_block()
      let current = builder.current_block
      builder.switch_to_block(trap_block)
      builder.trap("unaligned atomic")
      match current {
        Some(block) => builder.switch_to_block(block)
        None => ()
      }
      self.atomic_unaligned_trap_block = Some(trap_block)
      trap_block
    }
  }
}

///|
/// Emit an atomic alignment check. Atomics trap on misalignment.
///
/// The check is performed on the linear memory effective address (addr + offset).
pub fn FuncEnvironment::emit_atomic_alignment_check(
  self : FuncEnvironment,
  builder : IRBuilder,
  memidx : Int,
  wasm_addr : Value,
  offset : Int64,
  access_size : Int,
) -> Unit {
  if access_size <= 1 {
    return
  }
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  let addr_i64 = if is_memory64 {
    wasm_addr
  } else {
    builder.uextend(Type::I64, wasm_addr)
  }
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  let mask = builder.iconst(Type::I64, (access_size - 1).to_int64())
  let masked = builder.band(addr_plus_offset, mask)
  let zero = builder.iconst(Type::I64, 0L)
  let is_aligned = builder.icmp(IntCC::Eq, masked, zero)
  let trap_block = self.get_or_create_atomic_unaligned_trap_block(builder)
  let continue_block = builder.create_block()
  builder.brnz(is_aligned, continue_block, trap_block)
  builder.switch_to_block(continue_block)
}

// Note: Linear memory base is accessed via a dedicated `LoadMemBase` opcode so
// the optimizer can safely reduce redundant base reloads within a block while
// respecting invalidation around calls/grow.

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
/// Check if bounds check can be eliminated for a constant address access
/// Returns true if the access is guaranteed to be within the minimum memory size
fn FuncEnvironment::can_eliminate_bounds_check(
  self : FuncEnvironment,
  builder : IRBuilder,
  memidx : Int,
  wasm_addr : Value,
  offset : Int64,
  access_size : Int,
) -> Bool {
  // Get minimum memory size for this memory index
  let memory_min = if memidx < self.memory_mins.length() {
    self.memory_mins[memidx]
  } else {
    0L // No minimum known, cannot eliminate
  }
  if memory_min == 0L {
    return false
  }
  // Check if wasm_addr is a constant
  match builder.get_const_value(wasm_addr) {
    None => false
    Some(const_addr) => {
      // Ensure const_addr is non-negative (valid wasm address)
      if const_addr < 0L {
        return false
      }
      // Check if const_addr + offset + access_size <= memory_min
      // Use checked arithmetic to avoid overflow
      let end_addr = const_addr + offset + access_size.to_int64()
      // Also check for overflow (end_addr < const_addr would indicate overflow)
      end_addr >= const_addr && end_addr <= memory_min
    }
  }
}

///|
/// Emit bounds check and return effective address for memory access
/// This is a public helper for SIMD and other complex load operations
pub fn FuncEnvironment::emit_bounds_check(
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  wasm_addr : Value,
  offset : Int64,
  access_size : Int,
) -> Value {
  if self.use_guard_pages(memidx) {
    // Guard pages (memory32, memidx=0): rely on SIGSEGV for OOB trapping.
    let memory_base = builder.load_mem_base(vmctx, memidx)
    let addr_i64 = builder.uextend(Type::I64, wasm_addr)
    let offset_val = builder.iconst(Type::I64, offset)
    let addr_plus_offset = builder.iadd(addr_i64, offset_val)
    return builder.iadd(memory_base, addr_plus_offset)
  }

  // Check if bounds check can be eliminated for constant addresses
  let skip_bounds_check = self.can_eliminate_bounds_check(
    builder, memidx, wasm_addr, offset, access_size,
  )
  let memory_base = builder.load_mem_base(vmctx, memidx)
  let memory_size = load_memory_size(builder, vmctx, memidx)

  // For memory64, address is already i64; for memory32, extend i32 to i64
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  let addr_i64 = if is_memory64 {
    wasm_addr // Already i64
  } else {
    builder.uextend(Type::I64, wasm_addr)
  }

  // Calculate addr + offset for effective address
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  if not(skip_bounds_check) {
    // Need runtime bounds check
    let size_val = builder.iconst(Type::I64, access_size.to_int64())
    let end_addr = builder.iadd(addr_plus_offset, size_val)

    // For memory64, we need overflow-safe bounds checking
    let trap_block = self.get_or_create_memory_trap_block(builder)
    let continue_block = builder.create_block()
    if is_memory64 {
      // Check for overflow in addr + offset
      let no_overflow1 = builder.icmp(IntCC::Uge, addr_plus_offset, addr_i64)
      let check1_block = builder.create_block()
      builder.brnz(no_overflow1, check1_block, trap_block)
      builder.switch_to_block(check1_block)

      // Check for overflow in (addr + offset) + size
      let no_overflow2 = builder.icmp(IntCC::Uge, end_addr, addr_plus_offset)
      let check2_block = builder.create_block()
      builder.brnz(no_overflow2, check2_block, trap_block)
      builder.switch_to_block(check2_block)

      // Check end_addr <= memory_size
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    } else {
      // For memory32, no overflow possible
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    }

    // Continue block
    builder.switch_to_block(continue_block)
  }

  // Return effective address: memory_base + addr + offset
  builder.iadd(memory_base, addr_plus_offset)
}

///|
/// Translate memory load to IR primitives:
/// 1. Load memory_base and memory_size from vmctx
/// 2. Bounds check: trap if addr + offset + size > memory_size (shared trap block)
///    - Skip bounds check for constant addresses within minimum memory size
/// 3. Calculate effective address: memory_base + addr + offset
/// 4. LoadPtr
pub fn FuncEnvironment::translate_memory_load(
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  ty : Type,
  wasm_addr : Value,
  offset : Int64,
) -> Value {
  let access_size = type_byte_size(ty)
  if self.use_guard_pages(memidx) {
    // Guard pages (memory32, memidx=0): rely on SIGSEGV for OOB trapping.
    let memory_base = builder.load_mem_base(vmctx, memidx)
    let addr_i64 = builder.uextend(Type::I64, wasm_addr)
    let offset_val = builder.iconst(Type::I64, offset)
    let addr_plus_offset = builder.iadd(addr_i64, offset_val)
    let effective_addr = builder.iadd(memory_base, addr_plus_offset)
    let zero_offset = builder.iconst(Type::I64, 0L)
    return builder.load_ptr(ty, effective_addr, zero_offset)
  }

  // Check if bounds check can be eliminated for constant addresses
  let skip_bounds_check = self.can_eliminate_bounds_check(
    builder, memidx, wasm_addr, offset, access_size,
  )
  let memory_base = builder.load_mem_base(vmctx, memidx)
  let memory_size = load_memory_size(builder, vmctx, memidx)

  // For memory64, address is already i64; for memory32, extend i32 to i64
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  let addr_i64 = if is_memory64 {
    wasm_addr // Already i64
  } else {
    builder.uextend(Type::I64, wasm_addr)
  }

  // Calculate addr + offset for effective address
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  if not(skip_bounds_check) {
    // Need runtime bounds check
    let size_val = builder.iconst(Type::I64, access_size.to_int64())
    let end_addr = builder.iadd(addr_plus_offset, size_val)

    // For memory64, we need overflow-safe bounds checking.
    // u64 addition can wrap, so we must detect overflow:
    // - overflow1: addr + offset overflowed if addr_plus_offset < addr
    // - overflow2: (addr + offset) + size overflowed if end_addr < addr_plus_offset
    // - in_range: end_addr <= memory_size
    // Trap if overflow1 || overflow2 || !in_range
    let trap_block = self.get_or_create_memory_trap_block(builder)
    let continue_block = builder.create_block()
    if is_memory64 {
      // Check for overflow in addr + offset
      let no_overflow1 = builder.icmp(IntCC::Uge, addr_plus_offset, addr_i64)
      let check1_block = builder.create_block()
      builder.brnz(no_overflow1, check1_block, trap_block)
      builder.switch_to_block(check1_block)

      // Check for overflow in (addr + offset) + size
      let no_overflow2 = builder.icmp(IntCC::Uge, end_addr, addr_plus_offset)
      let check2_block = builder.create_block()
      builder.brnz(no_overflow2, check2_block, trap_block)
      builder.switch_to_block(check2_block)

      // Check end_addr <= memory_size
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    } else {
      // For memory32, addr is u32 extended to u64, offset is u32, size is small
      // No overflow possible, simple check suffices
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    }

    // Continue block: perform the load
    builder.switch_to_block(continue_block)
  }

  // Calculate effective address: memory_base + addr + offset
  let effective_addr = builder.iadd(memory_base, addr_plus_offset)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.load_ptr(ty, effective_addr, zero_offset)
}

///|
/// Translate memory store to IR primitives:
/// 1. Load memory_base and memory_size from vmctx
/// 2. Bounds check: trap if addr + offset + size > memory_size (shared trap block)
///    - Skip bounds check for constant addresses within minimum memory size
/// 3. Calculate effective address: memory_base + addr + offset
/// 4. StorePtr
pub fn FuncEnvironment::translate_memory_store(
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  ty : Type,
  wasm_addr : Value,
  value : Value,
  offset : Int64,
) -> Unit {
  let access_size = type_byte_size(ty)
  if self.use_guard_pages(memidx) {
    // Guard pages (memory32, memidx=0): rely on SIGSEGV for OOB trapping.
    let memory_base = builder.load_mem_base(vmctx, memidx)
    let addr_i64 = builder.uextend(Type::I64, wasm_addr)
    let offset_val = builder.iconst(Type::I64, offset)
    let addr_plus_offset = builder.iadd(addr_i64, offset_val)
    let effective_addr = builder.iadd(memory_base, addr_plus_offset)
    let zero_offset = builder.iconst(Type::I64, 0L)
    return builder.store_ptr(ty, effective_addr, value, zero_offset)
  }

  // Check if bounds check can be eliminated for constant addresses
  let skip_bounds_check = self.can_eliminate_bounds_check(
    builder, memidx, wasm_addr, offset, access_size,
  )
  let memory_base = builder.load_mem_base(vmctx, memidx)
  let memory_size = load_memory_size(builder, vmctx, memidx)

  // For memory64, address is already i64; for memory32, extend i32 to i64
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  let addr_i64 = if is_memory64 {
    wasm_addr // Already i64
  } else {
    builder.uextend(Type::I64, wasm_addr)
  }

  // Calculate addr + offset for effective address
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  if not(skip_bounds_check) {
    // Need runtime bounds check
    let size_val = builder.iconst(Type::I64, access_size.to_int64())
    let end_addr = builder.iadd(addr_plus_offset, size_val)

    // For memory64, we need overflow-safe bounds checking
    let trap_block = self.get_or_create_memory_trap_block(builder)
    let continue_block = builder.create_block()
    if is_memory64 {
      // Check for overflow in addr + offset
      let no_overflow1 = builder.icmp(IntCC::Uge, addr_plus_offset, addr_i64)
      let check1_block = builder.create_block()
      builder.brnz(no_overflow1, check1_block, trap_block)
      builder.switch_to_block(check1_block)

      // Check for overflow in (addr + offset) + size
      let no_overflow2 = builder.icmp(IntCC::Uge, end_addr, addr_plus_offset)
      let check2_block = builder.create_block()
      builder.brnz(no_overflow2, check2_block, trap_block)
      builder.switch_to_block(check2_block)

      // Check end_addr <= memory_size
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    } else {
      // For memory32, no overflow possible
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    }

    // Continue block: perform the store
    builder.switch_to_block(continue_block)
  }

  // Calculate effective address: memory_base + addr + offset
  let effective_addr = builder.iadd(memory_base, addr_plus_offset)
  let zero_offset = builder.iconst(Type::I64, 0L)
  builder.store_ptr(ty, effective_addr, value, zero_offset)
}

///|
/// Translate narrow memory load (i32.load8_s, i32.load16_u, etc.) to IR primitives
pub fn FuncEnvironment::translate_memory_load_narrow(
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  result_ty : Type,
  narrow_bits : Int,
  signed : Bool,
  wasm_addr : Value,
  offset : Int64,
) -> Value {
  let access_size = narrow_bits / 8
  if self.use_guard_pages(memidx) {
    // Guard pages (memory32, memidx=0): rely on SIGSEGV for OOB trapping.
    let memory_base = builder.load_mem_base(vmctx, memidx)
    let addr_i64 = builder.uextend(Type::I64, wasm_addr)
    let offset_val = builder.iconst(Type::I64, offset)
    let addr_plus_offset = builder.iadd(addr_i64, offset_val)
    let effective_addr = builder.iadd(memory_base, addr_plus_offset)
    let zero_offset = builder.iconst(Type::I64, 0L)
    return builder.load_ptr_narrow(
      result_ty, narrow_bits, signed, effective_addr, zero_offset,
    )
  }

  // Check if bounds check can be eliminated for constant addresses
  let skip_bounds_check = self.can_eliminate_bounds_check(
    builder, memidx, wasm_addr, offset, access_size,
  )
  let memory_base = builder.load_mem_base(vmctx, memidx)
  let memory_size = load_memory_size(builder, vmctx, memidx)

  // For memory64, address is already i64; for memory32, extend i32 to i64
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  let addr_i64 = if is_memory64 {
    wasm_addr // Already i64
  } else {
    builder.uextend(Type::I64, wasm_addr)
  }

  // Calculate addr + offset for effective address
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  if not(skip_bounds_check) {
    // Need runtime bounds check
    let size_val = builder.iconst(Type::I64, access_size.to_int64())
    let end_addr = builder.iadd(addr_plus_offset, size_val)

    // For memory64, we need overflow-safe bounds checking
    let trap_block = self.get_or_create_memory_trap_block(builder)
    let continue_block = builder.create_block()
    if is_memory64 {
      // Check for overflow in addr + offset
      let no_overflow1 = builder.icmp(IntCC::Uge, addr_plus_offset, addr_i64)
      let check1_block = builder.create_block()
      builder.brnz(no_overflow1, check1_block, trap_block)
      builder.switch_to_block(check1_block)

      // Check for overflow in (addr + offset) + size
      let no_overflow2 = builder.icmp(IntCC::Uge, end_addr, addr_plus_offset)
      let check2_block = builder.create_block()
      builder.brnz(no_overflow2, check2_block, trap_block)
      builder.switch_to_block(check2_block)

      // Check end_addr <= memory_size
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    } else {
      // For memory32, no overflow possible
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    }

    // Continue block: perform the load
    builder.switch_to_block(continue_block)
  }

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
  self : FuncEnvironment,
  builder : IRBuilder,
  vmctx : Value,
  memidx : Int,
  narrow_bits : Int,
  wasm_addr : Value,
  value : Value,
  offset : Int64,
) -> Unit {
  let access_size = narrow_bits / 8
  if self.use_guard_pages(memidx) {
    // Guard pages (memory32, memidx=0): rely on SIGSEGV for OOB trapping.
    let memory_base = builder.load_mem_base(vmctx, memidx)
    let addr_i64 = builder.uextend(Type::I64, wasm_addr)
    let offset_val = builder.iconst(Type::I64, offset)
    let addr_plus_offset = builder.iadd(addr_i64, offset_val)
    let effective_addr = builder.iadd(memory_base, addr_plus_offset)
    let zero_offset = builder.iconst(Type::I64, 0L)
    return builder.store_ptr_narrow(
      narrow_bits, effective_addr, value, zero_offset,
    )
  }

  // Check if bounds check can be eliminated for constant addresses
  let skip_bounds_check = self.can_eliminate_bounds_check(
    builder, memidx, wasm_addr, offset, access_size,
  )
  let memory_base = builder.load_mem_base(vmctx, memidx)
  let memory_size = load_memory_size(builder, vmctx, memidx)

  // For memory64, address is already i64; for memory32, extend i32 to i64
  let is_memory64 = memidx < self.memory_is_64.length() &&
    self.memory_is_64[memidx]
  let addr_i64 = if is_memory64 {
    wasm_addr // Already i64
  } else {
    builder.uextend(Type::I64, wasm_addr)
  }

  // Calculate addr + offset for effective address
  let offset_val = builder.iconst(Type::I64, offset)
  let addr_plus_offset = builder.iadd(addr_i64, offset_val)
  if not(skip_bounds_check) {
    // Need runtime bounds check
    let size_val = builder.iconst(Type::I64, access_size.to_int64())
    let end_addr = builder.iadd(addr_plus_offset, size_val)

    // For memory64, we need overflow-safe bounds checking
    let trap_block = self.get_or_create_memory_trap_block(builder)
    let continue_block = builder.create_block()
    if is_memory64 {
      // Check for overflow in addr + offset
      let no_overflow1 = builder.icmp(IntCC::Uge, addr_plus_offset, addr_i64)
      let check1_block = builder.create_block()
      builder.brnz(no_overflow1, check1_block, trap_block)
      builder.switch_to_block(check1_block)

      // Check for overflow in (addr + offset) + size
      let no_overflow2 = builder.icmp(IntCC::Uge, end_addr, addr_plus_offset)
      let check2_block = builder.create_block()
      builder.brnz(no_overflow2, check2_block, trap_block)
      builder.switch_to_block(check2_block)

      // Check end_addr <= memory_size
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    } else {
      // For memory32, no overflow possible
      let in_bounds = builder.icmp(IntCC::Ule, end_addr, memory_size)
      builder.brnz(in_bounds, continue_block, trap_block)
    }

    // Continue block: perform the store
    builder.switch_to_block(continue_block)
  }

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
