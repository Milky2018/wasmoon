// Hostcall import trampoline generation.
//
// These trampolines implement Wasm calling convention so JIT-compiled wasm can
// call imported host functions. The trampoline packs args/results into a stack
// `values_vec` buffer and calls an embedding-provided hostcall bridge symbol.

///|
fn value_type_to_reg_class(ty : @types.ValueType) -> @abi.RegClass {
  match ty {
    F32 => Float32
    F64 => Float64
    V128 => Vector
    _ => Int
  }
}

///|
fn value_type_to_mem_type(ty : @types.ValueType) -> @instr.MemType {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    _ => I64
  }
}

///|
fn value_type_to_ir_type(ty : @types.ValueType) -> @milkir.Type {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    _ => I64
  }
}

///|
fn slot_count_for_type(ty : @types.ValueType) -> Int {
  match ty {
    V128 => 2
    _ => 1
  }
}

///|
fn bytes_for_type(ty : @types.ValueType) -> Int {
  slot_count_for_type(ty) * 8
}

///|
fn add_call_clobbers(call_inst : @instr.VCodeInst) -> Unit {
  let isa = @isa.ISA::current()
  for preg in isa.call_clobbered_gprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
  for preg in isa.call_clobbered_fprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
}

///|
/// Generate a Wasm-ABI trampoline for calling a host function via a hostcall bridge.
///
/// `host_func_addr` is the runtime Store function address and is passed to the dispatcher.
pub fn emit_hostcall_import_trampoline(
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  host_func_addr : Int,
  hostcall_symbol : @instr.ExternalName,
) -> MachineCode {
  let isa = @isa.ISA::current()
  let func = @machv_regalloc.VCodeFunction::new("host_import_trampoline")

  // Params: always include vmctx as the first parameter (ISA-specific ABI reg).
  let _vmctx_param = func.add_param(Int)

  // Pre-compute stack overflow layout for incoming params.
  let max_int_reg = isa.wasm_user_arg_gprs().length()
  let max_float_reg = isa.wasm_arg_fprs().length()
  let mut total_int = 0
  let mut total_float = 0
  for ty in param_types {
    let cls = value_type_to_reg_class(ty)
    if cls is Int {
      total_int = total_int + 1
    } else {
      total_float = total_float + 1
    }
  }
  let int_overflow = if total_int > max_int_reg {
    total_int - max_int_reg
  } else {
    0
  }
  let float_overflow_classes : Array[@abi.RegClass] = []
  let mut float_seen = 0
  for ty in param_types {
    let cls = value_type_to_reg_class(ty)
    if cls is Int {
      continue
    }
    if float_seen >= max_float_reg {
      float_overflow_classes.push(cls)
    }
    float_seen = float_seen + 1
  }
  let (int_offsets, float_offsets, _) = @abi.wasm_layout_overflow_stack(
    int_overflow, float_overflow_classes,
  )

  // Track which params are passed in registers so prologue can move them.
  let param_vregs : Array[@abi.VReg?] = Array::make(param_types.length(), None)
  let mut int_seen = 0
  float_seen = 0
  for i, ty in param_types {
    let cls = value_type_to_reg_class(ty)
    if cls is Int {
      if int_seen < max_int_reg {
        param_vregs[i] = Some(func.add_param(cls))
      }
      int_seen = int_seen + 1
    } else {
      if float_seen < max_float_reg {
        param_vregs[i] = Some(func.add_param(cls))
      }
      float_seen = float_seen + 1
    }
  }

  // Results.
  for ty in result_types {
    func.add_result(value_type_to_reg_class(ty))
    func.add_result_type(value_type_to_ir_type(ty))
  }

  // Reserve outgoing args area for our values_vec buffer.
  let mut arg_slots = 0
  for ty in param_types {
    arg_slots = arg_slots + slot_count_for_type(ty)
  }
  let mut result_slots = 0
  for ty in result_types {
    result_slots = result_slots + slot_count_for_type(ty)
  }
  let values_vec_bytes = (arg_slots + result_slots) * 8
  func.update_max_outgoing_args_size(values_vec_bytes)

  // Single-block trampoline.
  let block = func.new_block()

  // Base pointer to values_vec: current SP after prologue.
  let sp_vreg = func.new_vreg(Int)
  let load_sp = @instr.VCodeInst::new(LoadSP)
  load_sp.add_def({ reg: Virtual(sp_vreg) })
  block.add_inst(load_sp)

  // Pack arguments into values_vec (in outgoing args area).
  let mut slot_off = 0
  int_seen = 0
  float_seen = 0
  for i, ty in param_types {
    let cls = value_type_to_reg_class(ty)

    // Resolve the source vreg (register param or stack param).
    let src_vreg : @abi.VReg = match param_vregs[i] {
      Some(v) => v
      None => {
        let tmp = func.new_vreg(cls)
        let stack_off = if cls is Int {
          int_offsets[int_seen - max_int_reg]
        } else {
          float_offsets[float_seen - max_float_reg]
        }
        let load = @instr.VCodeInst::new(LoadStackParam(stack_off, cls))
        load.add_def({ reg: Virtual(tmp) })
        block.add_inst(load)
        tmp
      }
    }
    match cls {
      Vector => {
        // Store as two i64 slots to avoid alignment requirements for Q stores.
        let lo = func.new_vreg(Int)
        let hi = func.new_vreg(Int)
        let ex0 = @instr.VCodeInst::new(SIMDExtractU(D64, 0))
        ex0.add_def({ reg: Virtual(lo) })
        ex0.add_use(Virtual(src_vreg))
        block.add_inst(ex0)
        let ex1 = @instr.VCodeInst::new(SIMDExtractU(D64, 1))
        ex1.add_def({ reg: Virtual(hi) })
        ex1.add_use(Virtual(src_vreg))
        block.add_inst(ex1)
        let st0 = @instr.VCodeInst::new(StoreToStack(slot_off))
        st0.add_use(Virtual(lo))
        block.add_inst(st0)
        let st1 = @instr.VCodeInst::new(StoreToStack(slot_off + 8))
        st1.add_use(Virtual(hi))
        block.add_inst(st1)
      }
      _ => {
        let st = @instr.VCodeInst::new(StoreToStack(slot_off))
        st.add_use(Virtual(src_vreg))
        block.add_inst(st)
      }
    }
    slot_off = slot_off + bytes_for_type(ty)

    // Update class counters (used to compute stack offsets).
    if cls is Int {
      int_seen = int_seen + 1
    } else {
      float_seen = float_seen + 1
    }
  }

  // Prepare C call: hostcall_bridge(ctx, host_func_addr, values_ptr, arg_slots, result_slots)
  let func_ptr_vreg = func.new_vreg(Int)
  let load_fp = @instr.VCodeInst::new(LoadExternalFuncAddr(hostcall_symbol))
  load_fp.add_def({ reg: Virtual(func_ptr_vreg) })
  block.add_inst(load_fp)

  // ctx argument comes from pinned VMCTX register (X21).
  let ctx_arg = func.new_vreg(Int)
  let mv_ctx = @instr.VCodeInst::new(Move)
  mv_ctx.add_def({ reg: Virtual(ctx_arg) })
  mv_ctx.add_use(Physical({ index: @isaregs.vmctx_index(), class: Int }))
  block.add_inst(mv_ctx)
  let host_addr_vreg = func.new_vreg(Int)
  let c_host = @instr.VCodeInst::new(LoadConst(host_func_addr.to_int64()))
  c_host.add_def({ reg: Virtual(host_addr_vreg) })
  block.add_inst(c_host)
  let arg_slots_vreg = func.new_vreg(Int)
  let c_arg_slots = @instr.VCodeInst::new(LoadConst(arg_slots.to_int64()))
  c_arg_slots.add_def({ reg: Virtual(arg_slots_vreg) })
  block.add_inst(c_arg_slots)
  let result_slots_vreg = func.new_vreg(Int)
  let c_res_slots = @instr.VCodeInst::new(LoadConst(result_slots.to_int64()))
  c_res_slots.add_def({ reg: Virtual(result_slots_vreg) })
  block.add_inst(c_res_slots)
  let call = @instr.VCodeInst::new(CallPtr(5, 0, C))
  fn c_arg_gpr_indices() -> Array[Int] {
    match @isa.ISA::current() {
      // AAPCS64: X0-X7
      AArch64 => [0, 1, 2, 3, 4, 5, 6, 7]
      // SysV AMD64: RDI,RSI,RDX,RCX,R8,R9 (in our 0..15 numbering)
      AMD64 => [7, 6, 2, 1, 8, 9]
    }
  }

  let arg_regs = c_arg_gpr_indices()
  // Call target in IP1.
  call.add_use_fixed(Virtual(func_ptr_vreg), {
    index: @isaregs.scratch2_index(),
    class: Int,
  })
  call.add_use_fixed(Virtual(ctx_arg), { index: arg_regs[0], class: Int })
  call.add_use_fixed(Virtual(host_addr_vreg), { index: arg_regs[1], class: Int })
  call.add_use_fixed(Virtual(sp_vreg), { index: arg_regs[2], class: Int })
  call.add_use_fixed(Virtual(arg_slots_vreg), { index: arg_regs[3], class: Int })
  call.add_use_fixed(Virtual(result_slots_vreg), {
    index: arg_regs[4],
    class: Int,
  })
  add_call_clobbers(call)
  block.add_inst(call)

  // Load results from values_vec and return.
  let mut res_off = slot_off
  let ret_regs : Array[@abi.Reg] = []
  for ty in result_types {
    match ty {
      V128 => {
        let lo = func.new_vreg(Int)
        let hi = func.new_vreg(Int)
        let ld0 = @instr.VCodeInst::new(LoadPtr(I64, res_off))
        ld0.add_def({ reg: Virtual(lo) })
        ld0.add_use(Virtual(sp_vreg))
        block.add_inst(ld0)
        let ld1 = @instr.VCodeInst::new(LoadPtr(I64, res_off + 8))
        ld1.add_def({ reg: Virtual(hi) })
        ld1.add_use(Virtual(sp_vreg))
        block.add_inst(ld1)
        let vec = func.new_vreg(Vector)
        let splat = @instr.VCodeInst::new(SIMDSplat(D64))
        splat.add_def({ reg: Virtual(vec) })
        splat.add_use(Virtual(lo))
        block.add_inst(splat)
        let ins = @instr.VCodeInst::new(SIMDInsert(D64, 1))
        ins.add_def({ reg: Virtual(vec) })
        ins.add_use(Virtual(vec))
        ins.add_use(Virtual(hi))
        block.add_inst(ins)
        ret_regs.push(Virtual(vec))
      }
      _ => {
        let memty = value_type_to_mem_type(ty)
        let dst = func.new_vreg(value_type_to_reg_class(ty))
        let ld = @instr.VCodeInst::new(LoadPtr(memty, res_off))
        ld.add_def({ reg: Virtual(dst) })
        ld.add_use(Virtual(sp_vreg))
        block.add_inst(ld)
        ret_regs.push(Virtual(dst))
      }
    }
    res_off = res_off + bytes_for_type(ty)
  }
  block.set_terminator(Return(ret_regs))

  // Allocate registers and emit machine code.
  let allocated = @machv_regalloc.allocate_registers_backtracking(func)
  emit_function(allocated)
}
