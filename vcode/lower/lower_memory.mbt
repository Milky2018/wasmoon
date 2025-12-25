///|
/// Get access size for a @instr.MemType
fn mem_type_size(ty : @instr.MemType) -> Int {
  match ty {
    I8 => 1
    I16 => 2
    I32 | F32 => 4
    I64 | F64 => 8
  }
}

///|
/// Emit bounds check instruction
/// Cranelift-style lowering: expand to primitive instructions here
///
/// Checks that wasm_addr + offset + access_size <= memory_size
///
/// Generated sequence:
/// 1. zero_ext = Extend(wasm_addr, Unsigned32To64) // zero-extend 32->64
/// 2. end_addr = Add(zero_ext, offset + access_size) // or AddImm
/// 3. memory_size = LoadPtr(vmctx, VMCTX_MEMORY_SIZE_OFFSET)
/// 4. TrapIfUgt(end_addr, memory_size, 1)
fn emit_bounds_check(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  wasm_addr : @abi.VReg,
  offset : Int,
  access_size : Int,
) -> Unit {
  // Step 1: Zero-extend wasm_addr from 32-bit to 64-bit
  let zero_ext = ctx.vcode_func.new_vreg(Int)
  let extend_inst = @instr.VCodeInst::new(Extend(Unsigned32To64))
  extend_inst.add_def({ reg: Virtual(zero_ext) })
  extend_inst.add_use(Virtual(wasm_addr))
  block.add_inst(extend_inst)

  // Step 2: Compute end_addr = zero_ext + (offset + access_size)
  // Handle offset as unsigned 32-bit, then add access_size
  let offset_u64 = offset
    .reinterpret_as_uint()
    .to_uint64()
    .reinterpret_as_int64()
  let end_offset = offset_u64 + access_size.to_int64()
  let end_addr = if end_offset > 0L {
    let result = ctx.vcode_func.new_vreg(Int)
    if end_offset <= 4095L {
      // Use AddImm for small offsets (64-bit pointer arithmetic)
      let add_inst = @instr.VCodeInst::new(AddImm(end_offset.to_int(), true))
      add_inst.add_def({ reg: Virtual(result) })
      add_inst.add_use(Virtual(zero_ext))
      block.add_inst(add_inst)
    } else {
      // Load constant and use Add for large offsets (64-bit pointer arithmetic)
      let const_vreg = ctx.vcode_func.new_vreg(Int)
      let load_const = @instr.VCodeInst::new(LoadConst(end_offset))
      load_const.add_def({ reg: Virtual(const_vreg) })
      block.add_inst(load_const)
      let add_inst = @instr.VCodeInst::new(Add(true))
      add_inst.add_def({ reg: Virtual(result) })
      add_inst.add_use(Virtual(zero_ext))
      add_inst.add_use(Virtual(const_vreg))
      block.add_inst(add_inst)
    }
    result
  } else {
    zero_ext
  }

  // Step 3: Load memory_size from vmctx
  let memory_size = ctx.vcode_func.new_vreg(Int)
  let vmctx_preg : @abi.PReg = { index: @abi.REG_VMCTX, class: @abi.Int }
  let load_size = @instr.VCodeInst::new(
    LoadPtr(@instr.I64, @abi.VMCTX_MEMORY_SIZE_OFFSET),
  )
  load_size.add_def({ reg: Virtual(memory_size) })
  load_size.add_use(Physical(vmctx_preg))
  block.add_inst(load_size)

  // Step 4: Emit TrapIfUgt - trap if end_addr > memory_size
  let trap_inst = @instr.VCodeInst::new(TrapIfUgt(1)) // trap code 1 = out of bounds
  trap_inst.add_use(Virtual(end_addr))
  trap_inst.add_use(Virtual(memory_size))
  block.add_inst(trap_inst)
}

///|
/// Emit instruction to load memory_base from vmctx on-demand (Cranelift-style)
/// Returns a virtual register containing memory_base
/// This is called before memory operations to get the current memory base address
fn emit_load_memory_base(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let memory_base_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(
    Load(I64, @abi.VMCTX_MEMORY_BASE_OFFSET),
  )
  load_inst.add_def({ reg: Virtual(memory_base_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  memory_base_vreg
}

///|
/// Emit instruction to load func_table from vmctx on-demand (Cranelift-style)
/// Returns a virtual register containing func_table pointer
/// This is called before function calls to get the function table base address
fn emit_load_func_table(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let func_table_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(Load(I64, @abi.VMCTX_FUNC_TABLE_OFFSET))
  load_inst.add_def({ reg: Virtual(func_table_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  func_table_vreg
}

///|
/// Emit instruction to load table0_base from vmctx on-demand (Cranelift-style)
/// Returns a virtual register containing table0_base pointer
/// This is called before indirect calls to get the indirect table base address
fn emit_load_table0_base(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
) -> @abi.VReg {
  let table0_base_vreg = ctx.vcode_func.new_vreg(Int)
  let load_inst = @instr.VCodeInst::new(
    Load(I64, @abi.VMCTX_TABLE0_BASE_OFFSET),
  )
  load_inst.add_def({ reg: Virtual(table0_base_vreg) })
  load_inst.add_use(Physical({ index: @abi.REG_VMCTX, class: Int })) // X19 = vmctx
  block.add_inst(load_inst)
  table0_base_vreg
}

///|
/// Lower GetFuncRef - get tagged function pointer for storing in tables
/// Returns func_ptr | FUNCREF_TAG (bit 61) for ref.test detection
fn lower_get_func_ref(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  func_idx : Int,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Step 1: Load func_table pointer from vmctx
  let func_table_vreg = emit_load_func_table(ctx, block)

  // Step 2: Load func_ptr from func_table[func_idx * 8]
  let raw_func_ptr = ctx.vcode_func.new_vreg(Int)
  let load_ptr = @instr.VCodeInst::new(Load(I64, func_idx * 8))
  load_ptr.add_def({ reg: Virtual(raw_func_ptr) })
  load_ptr.add_use(Virtual(func_table_vreg))
  block.add_inst(load_ptr)

  // Step 3: OR with FUNCREF_TAG (0x2000000000000000)
  let tag_vreg = ctx.vcode_func.new_vreg(Int)
  let load_tag = @instr.VCodeInst::new(LoadConst(0x2000000000000000L))
  load_tag.add_def({ reg: Virtual(tag_vreg) })
  block.add_inst(load_tag)
  let or_inst = @instr.VCodeInst::new(Or)
  or_inst.add_def({ reg: Virtual(result_vreg) })
  or_inst.add_use(Virtual(raw_func_ptr))
  or_inst.add_use(Virtual(tag_vreg))
  block.add_inst(or_inst)
}

///|
/// Lower load instruction
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_load(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine access size for bounds check
    let mem_ty = ir_type_to_mem_type(ty)
    let access_size = mem_type_size(mem_ty)
    // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
    emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
    // Load memory_base from vmctx on-demand
    let memory_base = emit_load_memory_base(ctx, block)
    // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
    let effective_addr = ctx.vcode_func.new_vreg(Int)
    let add_inst = @instr.VCodeInst::new(Add(true))
    add_inst.add_def({ reg: Virtual(effective_addr) })
    add_inst.add_use(Virtual(memory_base))
    add_inst.add_use(Virtual(wasm_addr))
    block.add_inst(add_inst)
    // Now load from effective_addr + offset
    // Check alignment requirement based on memory type
    let alignment = match mem_ty {
      I8 => 1
      I16 => 2
      I32 | F32 => 4
      I64 | F64 => 8
    }
    // If offset is not aligned or too large, add it to the address first
    if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
      // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
      let addr_with_offset = ctx.vcode_func.new_vreg(Int)
      let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
      offset_add.add_def({ reg: Virtual(addr_with_offset) })
      offset_add.add_use(Virtual(effective_addr))
      block.add_inst(offset_add)
      // Now load with offset=0
      let vcode_inst = @instr.VCodeInst::new(Load(mem_ty, 0))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(addr_with_offset))
      block.add_inst(vcode_inst)
    } else {
      // Offset can be encoded directly in the load instruction
      let vcode_inst = @instr.VCodeInst::new(Load(mem_ty, offset))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(effective_addr))
      block.add_inst(vcode_inst)
    }
  }
}

///|
/// Lower store instruction
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_store(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  ty : @ir.Type,
  offset : Int,
) -> Unit {
  // Store has no result, just uses: addr, value
  let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)
  // Determine access size for bounds check
  let mem_ty = ir_type_to_mem_type(ty)
  let access_size = mem_type_size(mem_ty)
  // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
  emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
  // Load memory_base from vmctx on-demand
  let memory_base = emit_load_memory_base(ctx, block)
  // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
  let effective_addr = ctx.vcode_func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(effective_addr) })
  add_inst.add_use(Virtual(memory_base))
  add_inst.add_use(Virtual(wasm_addr))
  block.add_inst(add_inst)
  // Now store to effective_addr + offset
  // Check alignment requirement based on memory type
  let alignment = match mem_ty {
    I8 => 1
    I16 => 2
    I32 | F32 => 4
    I64 | F64 => 8
  }
  // If offset is not aligned or too large, add it to the address first
  if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
    // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
    let addr_with_offset = ctx.vcode_func.new_vreg(Int)
    let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
    offset_add.add_def({ reg: Virtual(addr_with_offset) })
    offset_add.add_use(Virtual(effective_addr))
    block.add_inst(offset_add)
    // Now store with offset=0
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, 0))
    vcode_inst.add_use(Virtual(addr_with_offset))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  } else {
    // Offset can be encoded directly in the store instruction
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, offset))
    vcode_inst.add_use(Virtual(effective_addr))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower narrow load instruction (8/16/32-bit with sign/zero extension)
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_load_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  offset : Int,
  opcode_fn : (Int) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine access size based on opcode type
    let sample_opcode = opcode_fn(0)
    let access_size = match sample_opcode {
      Load8S(_) | Load8U(_) => 1
      Load16S(_) | Load16U(_) => 2
      Load32S(_) | Load32U(_) => 4
      _ => 1
    }
    // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
    emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
    // Load memory_base from vmctx on-demand
    let memory_base = emit_load_memory_base(ctx, block)
    // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
    let effective_addr = ctx.vcode_func.new_vreg(Int)
    let add_inst = @instr.VCodeInst::new(Add(true))
    add_inst.add_def({ reg: Virtual(effective_addr) })
    add_inst.add_use(Virtual(memory_base))
    add_inst.add_use(Virtual(wasm_addr))
    block.add_inst(add_inst)
    // Check alignment requirement based on opcode type
    // Load8: any offset ok (1-byte aligned)
    // Load16: offset must be 2-aligned for immediate encoding
    // Load32: offset must be 4-aligned for immediate encoding
    let alignment = access_size
    // If offset is not aligned or too large, add it to the address first
    if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
      // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
      let addr_with_offset = ctx.vcode_func.new_vreg(Int)
      let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
      offset_add.add_def({ reg: Virtual(addr_with_offset) })
      offset_add.add_use(Virtual(effective_addr))
      block.add_inst(offset_add)
      // Now load with offset=0
      let vcode_inst = @instr.VCodeInst::new(opcode_fn(0))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(addr_with_offset))
      block.add_inst(vcode_inst)
    } else {
      // Offset can be encoded directly in the load instruction
      let vcode_inst = @instr.VCodeInst::new(opcode_fn(offset))
      vcode_inst.add_def({ reg: Virtual(dst) })
      vcode_inst.add_use(Virtual(effective_addr))
      block.add_inst(vcode_inst)
    }
  }
}

///|
/// Lower narrow store instruction (8/16/32-bit)
/// For WASM, addr is an offset within linear memory, so we need to add memory_base
/// Memory_base is loaded on-demand from vmctx (Cranelift-style)
fn lower_store_narrow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  offset : Int,
  mem_ty : @instr.MemType,
) -> Unit {
  // Store has no result, just uses: addr, value
  let wasm_addr = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)
  // Determine access size for bounds check
  let access_size = mem_type_size(mem_ty)
  // Emit bounds check: trap if wasm_addr + offset + access_size > memory_size
  emit_bounds_check(ctx, block, wasm_addr, offset, access_size)
  // Load memory_base from vmctx on-demand
  let memory_base = emit_load_memory_base(ctx, block)
  // Compute effective address: memory_base + wasm_addr (64-bit pointer arithmetic)
  let effective_addr = ctx.vcode_func.new_vreg(Int)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: Virtual(effective_addr) })
  add_inst.add_use(Virtual(memory_base))
  add_inst.add_use(Virtual(wasm_addr))
  block.add_inst(add_inst)
  // Check alignment requirement based on memory type
  let alignment = access_size
  // If offset is not aligned or too large, add it to the address first
  if offset != 0 && (offset % alignment != 0 || offset > 4095 * alignment) {
    // Add offset to effective_addr using immediate add (64-bit pointer arithmetic)
    let addr_with_offset = ctx.vcode_func.new_vreg(Int)
    let offset_add = @instr.VCodeInst::new(AddImm(offset, true))
    offset_add.add_def({ reg: Virtual(addr_with_offset) })
    offset_add.add_use(Virtual(effective_addr))
    block.add_inst(offset_add)
    // Now store with offset=0
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, 0))
    vcode_inst.add_use(Virtual(addr_with_offset))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  } else {
    // Offset can be encoded directly in the store instruction
    let vcode_inst = @instr.VCodeInst::new(Store(mem_ty, offset))
    vcode_inst.add_use(Virtual(effective_addr))
    vcode_inst.add_use(Virtual(value))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower memory.grow instruction
/// memory.grow takes a delta (number of pages to grow) and returns the previous size or -1
fn lower_memory_grow(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  max_pages : Int?,
) -> Unit {
  // Get the delta operand
  let delta_vreg = ctx.get_vreg_for_use(inst.operands[0], block)

  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Create the MemoryGrow VCode instruction
  // Uses: [delta], Defs: [result]
  // Convert Int? to Int (0 = no limit)
  let max_pages_value = max_pages.unwrap_or(0)
  let grow_inst = @instr.VCodeInst::new(MemoryGrow(max_pages_value))
  grow_inst.add_def({ reg: Virtual(result_vreg) })
  grow_inst.add_use(Virtual(delta_vreg))
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(grow_inst)
  // Also clobber X19 since emit uses it as temp to save result across internal calls
  grow_inst.add_def({ reg: Physical({ index: 19, class: Int }) })
  block.add_inst(grow_inst)
}

///|
/// Lower memory.size instruction
/// memory.size returns the current memory size in pages
fn lower_memory_size(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  // Get the result vreg
  guard inst.result is Some(result) else { return }
  let result_vreg = ctx.get_vreg(result)

  // Create the MemorySize VCode instruction
  // Uses: [], Defs: [result]
  let size_inst = @instr.VCodeInst::new(MemorySize)
  size_inst.add_def({ reg: Virtual(result_vreg) })
  // Add clobbers for caller-saved registers (it's a call)
  add_call_clobbers(size_inst)
  block.add_inst(size_inst)
}

///|
/// Lower memory.fill instruction
/// memory.fill fills a memory region with a byte value
fn lower_memory_fill(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  // Get the operands: dst, val, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let val = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Create the MemoryFill VCode instruction
  // Uses: [dst, val, size], Defs: []
  let fill_inst = @instr.VCodeInst::new(MemoryFill)
  fill_inst.add_use(Virtual(dst))
  fill_inst.add_use(Virtual(val))
  fill_inst.add_use(Virtual(size))
  // Only clobber registers actually used by codegen: x0-x2 (args), x16 (func ptr)
  // Don't clobber all caller-saved regs to avoid breaking value reuse
  fill_inst.add_def({ reg: Physical({ index: 0, class: Int }) }) // x0
  fill_inst.add_def({ reg: Physical({ index: 1, class: Int }) }) // x1
  fill_inst.add_def({ reg: Physical({ index: 2, class: Int }) }) // x2
  fill_inst.add_def({ reg: Physical({ index: 16, class: Int }) }) // x16
  block.add_inst(fill_inst)
}

///|
/// Lower memory.copy instruction
/// memory.copy copies a memory region (handles overlapping regions correctly)
fn lower_memory_copy(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  // Get the operands: dst, src, size
  guard inst.operands.length() >= 3 else { return }
  let dst = ctx.get_vreg_for_use(inst.operands[0], block)
  let src = ctx.get_vreg_for_use(inst.operands[1], block)
  let size = ctx.get_vreg_for_use(inst.operands[2], block)

  // Create the MemoryCopy VCode instruction
  // Uses: [dst, src, size], Defs: []
  let copy_inst = @instr.VCodeInst::new(MemoryCopy)
  copy_inst.add_use(Virtual(dst))
  copy_inst.add_use(Virtual(src))
  copy_inst.add_use(Virtual(size))
  // Only clobber registers actually used by codegen: x0-x2 (args), x16 (func ptr)
  // Don't clobber all caller-saved regs to avoid breaking value reuse
  copy_inst.add_def({ reg: Physical({ index: 0, class: Int }) }) // x0
  copy_inst.add_def({ reg: Physical({ index: 1, class: Int }) }) // x1
  copy_inst.add_def({ reg: Physical({ index: 2, class: Int }) }) // x2
  copy_inst.add_def({ reg: Physical({ index: 16, class: Int }) }) // x16
  block.add_inst(copy_inst)
}
