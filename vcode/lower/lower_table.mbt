///|
/// Lower table.get instruction
/// Loads a function reference from the indirect table
///
/// Cranelift-style lowering: expand to primitive instructions here
/// instead of deferring to emit phase with hardcoded registers.
///
/// Generated sequence:
/// 1. elem_idx_64 = Extend(elem_idx, Unsigned32To64) // zero-extend 32->64
/// 2. table_size = LoadPtr(I64, VMCTX_TABLE0_ELEMENTS_OFFSET) from vmctx
/// 3. TrapIfUge(elem_idx_64, table_size, 1) // trap if out of bounds
/// 4. table_base = LoadPtr(I64, VMCTX_TABLE0_BASE_OFFSET) from vmctx (X19)
/// 5. addr = AddShifted(table_base, elem_idx_64, Lsl, 4)  // addr = table_base + elem_idx * 16
/// 6. result = LoadPtr(I64, 0) from addr
fn lower_table_get(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Get the element index operand
  guard inst.operands.length() > 0 else { return }
  let elem_idx = ctx.get_vreg_for_use(inst.operands[0], block)

  // Step 1: Zero-extend elem_idx from 32-bit to 64-bit
  let elem_idx_64 = ctx.new_vreg(@abi.Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(elem_idx_64) })
  extend_inst.add_use(Virtual(elem_idx))
  block.add_inst(extend_inst)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Load table_size and table_base depending on table_idx
  let table_size = ctx.new_vreg(@abi.Int)
  let table_base = ctx.new_vreg(@abi.Int)
  if table_idx == 0 {
    // Fast path for table 0
    // Step 2: Load table_size from vmctx
    let load_size = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_ELEMENTS_OFFSET),
    )
    load_size.add_use(Physical(vmctx_preg))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Step 4: Load table0_base from vmctx
    let load_table = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_BASE_OFFSET),
    )
    load_table.add_use(Physical(vmctx_preg))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  } else {
    // Multi-table path
    // Load table_sizes array pointer
    let table_sizes_ptr = ctx.new_vreg(@abi.Int)
    let load_sizes_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE_SIZES_OFFSET),
    )
    load_sizes_ptr.add_use(Physical(vmctx_preg))
    load_sizes_ptr.add_def({ reg: Virtual(table_sizes_ptr) })
    block.add_inst(load_sizes_ptr)

    // Load table_size from table_sizes[table_idx]
    let load_size = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_size.add_use(Virtual(table_sizes_ptr))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Load tables array pointer
    let tables_ptr = ctx.new_vreg(@abi.Int)
    let load_tables_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLES_OFFSET),
    )
    load_tables_ptr.add_use(Physical(vmctx_preg))
    load_tables_ptr.add_def({ reg: Virtual(tables_ptr) })
    block.add_inst(load_tables_ptr)

    // Load table_base from tables[table_idx]
    let load_table = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_table.add_use(Virtual(tables_ptr))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  }

  // Step 3: Bounds check - trap if elem_idx >= table_size
  let trap_inst = @instr.VCodeInst::new(TrapIfUge(1)) // trap code 1 = out of bounds
  trap_inst.add_use(Virtual(elem_idx_64))
  trap_inst.add_use(Virtual(table_size))
  block.add_inst(trap_inst)

  // Step 5: Calculate address: addr = table_base + (elem_idx << 4)
  // Each table element is 16 bytes (func_ptr + type_idx)
  let addr = ctx.new_vreg(@abi.Int)
  let calc_addr = @instr.VCodeInst::new(AddShifted(@instr.Lsl, 4))
  calc_addr.add_use(Virtual(table_base))
  calc_addr.add_use(Virtual(elem_idx_64))
  calc_addr.add_def({ reg: Virtual(addr) })
  block.add_inst(calc_addr)

  // Step 6: Load result from addr
  let load_result = @instr.VCodeInst::new(LoadPtr(@instr.I64, 0))
  load_result.add_use(Virtual(addr))
  load_result.add_def({ reg: Virtual(result_vreg) })
  block.add_inst(load_result)
}

///|
/// Lower table.set instruction
/// Stores a function reference to the indirect table
///
/// Cranelift-style lowering: expand to primitive instructions here
/// instead of deferring to emit phase with hardcoded registers.
///
/// Generated sequence:
/// 1. elem_idx_64 = Extend(elem_idx, Unsigned32To64) // zero-extend 32->64
/// 2. table_size = LoadPtr(I64, VMCTX_TABLE0_ELEMENTS_OFFSET) from vmctx
/// 3. TrapIfUge(elem_idx_64, table_size, 1) // trap if out of bounds
/// 4. table_base = LoadPtr(I64, VMCTX_TABLE0_BASE_OFFSET) from vmctx (X19)
/// 5. addr = AddShifted(table_base, elem_idx_64, Lsl, 4)  // addr = table_base + elem_idx * 16
/// 6. StorePtr(I64, 0) value to addr
fn lower_table_set(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the operands: elem_idx and value
  guard inst.operands.length() >= 2 else { return }
  let elem_idx = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)

  // Step 1: Zero-extend elem_idx from 32-bit to 64-bit
  let elem_idx_64 = ctx.new_vreg(@abi.Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(elem_idx_64) })
  extend_inst.add_use(Virtual(elem_idx))
  block.add_inst(extend_inst)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }

  // Load table_size and table_base depending on table_idx
  let table_size = ctx.new_vreg(@abi.Int)
  let table_base = ctx.new_vreg(@abi.Int)
  if table_idx == 0 {
    // Fast path for table 0
    // Step 2: Load table_size from vmctx
    let load_size = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_ELEMENTS_OFFSET),
    )
    load_size.add_use(Physical(vmctx_preg))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Step 4: Load table0_base from vmctx
    let load_table = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_BASE_OFFSET),
    )
    load_table.add_use(Physical(vmctx_preg))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  } else {
    // Multi-table path
    // Load table_sizes array pointer
    let table_sizes_ptr = ctx.new_vreg(@abi.Int)
    let load_sizes_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE_SIZES_OFFSET),
    )
    load_sizes_ptr.add_use(Physical(vmctx_preg))
    load_sizes_ptr.add_def({ reg: Virtual(table_sizes_ptr) })
    block.add_inst(load_sizes_ptr)

    // Load table_size from table_sizes[table_idx]
    let load_size = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_size.add_use(Virtual(table_sizes_ptr))
    load_size.add_def({ reg: Virtual(table_size) })
    block.add_inst(load_size)

    // Load tables array pointer
    let tables_ptr = ctx.new_vreg(@abi.Int)
    let load_tables_ptr = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLES_OFFSET),
    )
    load_tables_ptr.add_use(Physical(vmctx_preg))
    load_tables_ptr.add_def({ reg: Virtual(tables_ptr) })
    block.add_inst(load_tables_ptr)

    // Load table_base from tables[table_idx]
    let load_table = @instr.VCodeInst::new(LoadPtr(@instr.I64, table_idx * 8))
    load_table.add_use(Virtual(tables_ptr))
    load_table.add_def({ reg: Virtual(table_base) })
    block.add_inst(load_table)
  }

  // Step 3: Bounds check - trap if elem_idx >= table_size
  let trap_inst = @instr.VCodeInst::new(TrapIfUge(1)) // trap code 1 = out of bounds
  trap_inst.add_use(Virtual(elem_idx_64))
  trap_inst.add_use(Virtual(table_size))
  block.add_inst(trap_inst)

  // Step 5: Calculate address: addr = table_base + (elem_idx << 4)
  // Each table element is 16 bytes (func_ptr + type_idx)
  let addr = ctx.new_vreg(@abi.Int)
  let calc_addr = @instr.VCodeInst::new(AddShifted(@instr.Lsl, 4))
  calc_addr.add_use(Virtual(table_base))
  calc_addr.add_use(Virtual(elem_idx_64))
  calc_addr.add_def({ reg: Virtual(addr) })
  block.add_inst(calc_addr)

  // Step 6: Store value to addr
  let store_value = @instr.VCodeInst::new(StorePtr(@instr.I64, 0))
  store_value.add_use(Virtual(addr))
  store_value.add_use(Virtual(value))
  block.add_inst(store_value)
}

///|
/// Lower table.size instruction
/// Returns the current number of elements in the table
///
/// Generated sequence (for table 0):
/// 1. result = LoadPtr(I64, VMCTX_TABLE0_ELEMENTS_OFFSET) from vmctx
/// Generated sequence (for table N > 0):
/// 1. table_sizes_ptr = LoadPtr(I64, VMCTX_TABLE_SIZES_OFFSET) from vmctx
/// 2. result = LoadPtr(I64, table_idx * 8) from table_sizes_ptr
/// Note: Result is returned as 64-bit but high 32 bits are always 0
fn lower_table_size(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }
  if table_idx == 0 {
    // Fast path for table 0: load table0_elements from vmctx directly into result
    let load_size = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE0_ELEMENTS_OFFSET),
    )
    load_size.add_use(Physical(vmctx_preg))
    load_size.add_def({ reg: Virtual(result_vreg) })
    block.add_inst(load_size)
  } else {
    // Multi-table path: load from table_sizes array
    // 1. Load table_sizes array pointer: [vmctx + VMCTX_TABLE_SIZES_OFFSET]
    let table_sizes_ptr = ctx.new_vreg(@abi.Int)
    let load_sizes = @instr.VCodeInst::new(
      LoadPtr(@instr.I64, @abi.VMCTX_TABLE_SIZES_OFFSET),
    )
    load_sizes.add_use(Physical(vmctx_preg))
    load_sizes.add_def({ reg: Virtual(table_sizes_ptr) })
    block.add_inst(load_sizes)

    // 2. Load size for this table: [table_sizes + table_idx * 8]
    // Each size is 8 bytes (size_t)
    let size_offset = table_idx * 8
    let load_size = @instr.VCodeInst::new(LoadPtr(@instr.I64, size_offset))
    load_size.add_use(Virtual(table_sizes_ptr))
    load_size.add_def({ reg: Virtual(result_vreg) })
    block.add_inst(load_size)
  }
}

///|
/// Lower table.grow instruction
/// Grows the table by delta elements, initializing new elements with init_value
/// Returns the previous size (as i32), or -1 if grow failed
///
/// This is a runtime call that goes through the C FFI
fn lower_table_grow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  table_idx : Int,
) -> Unit {
  // Get operands: delta, init_value
  guard inst.operands.length() >= 2 else { return }
  let delta = ctx.get_vreg_for_use(inst.operands[0], block)
  let init_value = ctx.get_vreg_for_use(inst.operands[1], block)

  // Get or create the result vreg
  // Note: We must emit the call even if result is unused because table_grow has side effects
  let result_vreg = match inst.result {
    Some(result) => ctx.get_vreg(result)
    None => ctx.vcode_func.new_vreg(@abi.Int) // Create a temp vreg for the unused result
  }

  // Create the TableGrow VCode instruction
  // Uses: [delta, init_value], Defs: [result]
  let grow_inst = @instr.VCodeInst::new(TableGrow(table_idx))
  grow_inst.add_def({ reg: Virtual(result_vreg) })
  grow_inst.add_use(Virtual(delta))
  grow_inst.add_use(Virtual(init_value))
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(grow_inst)
  block.add_inst(grow_inst)
}
