///|
/// Emit StoreToStack for overflow arguments according to the configured call convention.
/// This also updates `max_outgoing_args_size` so the prologue reserves enough
/// space and SP doesn't move at call sites.
fn emit_embedding_overflow_arg_stores(
  ctx : LoweringContext,
  block : @block.Block,
  int_args : Array[(@abi.VReg, @abi.RegClass)],
  float_args : Array[(@abi.VReg, @abi.RegClass)],
) -> Int {
  let call_conv = ctx.require_call_conv_layout()
  let max_int_reg_args = call_conv.user_arg_gprs.length()
  let max_float_reg_args = call_conv.arg_fprs.length()
  let int_overflow = if int_args.length() > max_int_reg_args {
    int_args.length() - max_int_reg_args
  } else {
    0
  }
  let float_overflow_classes : Array[@abi.RegClass] = []
  for i in max_float_reg_args..<float_args.length() {
    let (_, class) = float_args[i]
    float_overflow_classes.push(class)
  }
  let (int_offsets, float_offsets, total_bytes) = call_conv.layout_overflow_stack(
    int_overflow, float_overflow_classes,
  )
  if total_bytes > 0 {
    ctx.machv_func.update_max_outgoing_args_size(total_bytes)
  }
  for i in 0..<int_overflow {
    let (vreg, _) = int_args[max_int_reg_args + i]
    let store = @instr.Inst(StoreToStack(int_offsets[i]))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  for i in 0..<float_offsets.length() {
    let (vreg, _) = float_args[max_float_reg_args + i]
    let store = @instr.Inst(StoreToStack(float_offsets[i]))
    store.add_use(Virtual(vreg))
    block.add_inst(store)
  }
  total_bytes
}

///|
/// Emit StoreToStack for overflow integer arguments in C ABI calls.
///
/// SysV AMD64 stack arguments are 8-byte slots laid out left-to-right after the
/// register arguments.
fn emit_c_overflow_arg_stores(
  ctx : LoweringContext,
  block : @block.Block,
  args : Array[@abi.VReg],
  max_reg_args : Int,
) -> Unit {
  let overflow = if args.length() > max_reg_args {
    args.length() - max_reg_args
  } else {
    0
  }
  if overflow == 0 {
    return
  }
  let total_bytes = overflow * 8
  ctx.machv_func.update_max_outgoing_args_size(total_bytes)
  for i in 0..<overflow {
    let arg = args[max_reg_args + i]
    let store = @instr.Inst(StoreToStack(i * 8))
    store.add_use(Virtual(arg))
    block.add_inst(store)
  }
}

///|
/// Add clobber definitions for all caller-saved registers to a call instruction.
/// This tells the register allocator that these registers are destroyed by the call,
/// so any values that need to survive across the call must be spilled or allocated
/// to callee-saved registers.
pub fn add_call_clobbers(
  ctx : LoweringContext,
  call_inst : @instr.Inst,
) -> Unit {
  let isa = ctx.isa
  // Add clobbers for all caller-saved GPRs (X0-X17)
  for preg in isa.call_clobbered_gprs() {
    call_inst.add_def({ reg: Physical(preg) })
  }
  // Add clobbers for caller-saved FPRs.
  //
  // Cranelift-style conservative clobbers (V0-V31) apply to foreign calls.
  // For internal same-ABI calls, we treat V8-V15 as callee-saved.
  let fpr_clobbers = match call_inst.opcode {
    CallPtr(_, _, Foreign) | CallDirect(_, _, _, Foreign) =>
      isa.call_clobbered_fprs()
    _ => isa.call_clobbered_fprs_same_abi()
  }
  for preg in fpr_clobbers {
    call_inst.add_def({ reg: Physical(preg) })
  }
}

///|
/// Add clobbers for a C call unconditionally (used for pseudo-ops that may call
/// a C helper on a slow path).
pub fn add_c_call_clobbers(ctx : LoweringContext, inst : @instr.Inst) -> Unit {
  let isa = ctx.isa
  for preg in isa.call_clobbered_gprs() {
    inst.add_def({ reg: Physical(preg) })
  }
  for preg in isa.call_clobbered_fprs() {
    inst.add_def({ reg: Physical(preg) })
  }
}

///|
/// Lower a C libcall as direct-call fixup (AArch64 only).
/// This emits a symbolic `CallExternal` that the embedding runtime resolves.
pub fn lower_c_libcall_direct(
  ctx : LoweringContext,
  block : @block.Block,
  symbol : @instr.ExternalName,
  args : Array[@abi.VReg],
  result : @abi.VReg?,
) -> Unit {
  fn c_arg_gpr_indices() -> Array[Int] {
    match ctx.isa {
      AArch64 => [0, 1, 2, 3, 4, 5, 6, 7]
      AMD64 => [7, 6, 2, 1, 8, 9]
    }
  }

  let arg_regs = c_arg_gpr_indices()
  guard args.length() <= arg_regs.length() else {
    abort("lower_c_libcall_direct: too many arguments")
  }
  let num_args = args.length()
  let result_classes : Array[@abi.RegClass] = []
  if result is Some(dst) {
    result_classes.push(dst.class)
  }
  let call_inst = @instr.Inst(
    CallExternal(symbol, num_args, result_classes, Foreign),
  )
  for i, arg in args {
    call_inst.add_use_fixed(Virtual(arg), { index: arg_regs[i], class: Int })
  }
  if result is Some(dst) {
    call_inst.add_def_fixed({ reg: Virtual(dst) }, { index: 0, class: Int })
  }
  add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
  invalidate_context_pointer_cache(ctx)
}

///|
/// Lower call_ptr instruction (call through a function pointer)
/// Used in trampolines to call an embedding-defined target function.
///
/// Operand layout:
///   operand 0 = function pointer
///   operand 1 = embedding context
///   operands 2..n = user arguments
///
/// Standard ABI refactoring:
/// - Stack args are handled in lower phase via StoreToStack instructions
/// - Register args use FixedReg constraints to tell regalloc which physical registers to use
/// - Call target is constrained to SCRATCH_REG_2 (IP1)
fn lower_call_ptr(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  num_args : Int,
  _num_results : Int,
) -> Unit {
  // Collect function pointer
  let func_ptr = ctx.get_vreg_for_use(inst.operands[0], block)

  // Collect embedding context argument
  let callee_context = ctx.get_vreg_for_use(inst.operands[1], block)

  // Classify user arguments by type (starting from operand index 2)
  // int_args and float_args contain (vreg, class) tuples
  let int_args : Array[(@abi.VReg, @abi.RegClass)] = []
  let float_args : Array[(@abi.VReg, @abi.RegClass)] = []
  for i in 2..<inst.operands.length() {
    let vreg = ctx.get_vreg_for_use(inst.operands[i], block)
    match vreg.class {
      Int => int_args.push((vreg, Int))
      Float32 => float_args.push((vreg, Float32))
      Float64 => float_args.push((vreg, Float64))
      Vector => float_args.push((vreg, Vector)) // SIMD uses Vn registers
    }
  }
  emit_embedding_overflow_arg_stores(ctx, block, int_args, float_args) |> ignore
  let call_conv = ctx.require_call_conv_layout()

  // Collect result vregs (skip when results are unused)
  let result_vregs = collect_call_result_vregs(ctx, inst)

  // Step 3: Create an internal call with fixed-register constraints.
  let call_inst = @instr.Inst(
    CallPtr(num_args, @instr.result_classes_for_vregs(result_vregs), Internal),
  )

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr), {
    index: scratch2_index(ctx),
    class: Int,
  })

  // Callee context is constrained to the configured context argument register.
  call_inst.add_use_fixed(Virtual(callee_context), call_conv.context_arg)

  // Register int args (ISA-specific).
  let user_arg_gprs = call_conv.user_arg_gprs
  let max_int_reg_args = user_arg_gprs.length()
  let int_reg_count = if int_args.length() < max_int_reg_args {
    int_args.length()
  } else {
    max_int_reg_args
  }
  for i in 0..<int_reg_count {
    let (vreg, _) = int_args[i]
    call_inst.add_use_fixed(Virtual(vreg), {
      index: user_arg_gprs[i].index,
      class: Int,
    })
  }

  // Register float args (ISA-specific).
  let arg_fprs = call_conv.arg_fprs
  let max_float_reg_args = arg_fprs.length()
  let float_reg_count = if float_args.length() < max_float_reg_args {
    float_args.length()
  } else {
    max_float_reg_args
  }
  for i in 0..<float_reg_count {
    let (vreg, class) = float_args[i]
    call_inst.add_use_fixed(Virtual(vreg), { index: arg_fprs[i].index, class })
  }

  // Step 4: Define results with constraints
  let ret_gprs = call_conv.ret_gprs
  let ret_fprs = call_conv.ret_fprs
  let mut int_result_idx = 0
  let mut float_result_idx = 0
  for dst in result_vregs {
    match dst.class {
      Int => {
        call_inst.add_def_fixed({ reg: Virtual(dst) }, {
          index: ret_gprs[int_result_idx].index,
          class: Int,
        })
        int_result_idx = int_result_idx + 1
      }
      Float32 | Float64 | Vector => {
        call_inst.add_def_fixed({ reg: Virtual(dst) }, {
          index: ret_fprs[float_result_idx].index,
          class: dst.class,
        })
        float_result_idx = float_result_idx + 1
      }
    }
  }

  // Add clobbers for all caller-saved registers
  add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
  invalidate_context_pointer_cache(ctx)
  // No AdjustSP needed - outgoing args space is pre-allocated in prologue
}

// ============ C Libcall Lowering (Standard) ============

///|
/// Lower a generic external-symbol call using the platform C ABI.
///
/// Frontends that need embedding-specific runtime helpers should express them
/// as MilkIR `Call(ExternalSymbol)` nodes before generic MilkIR-to-MachV lowering. The
/// symbol resolver is owned by the embedding runtime, not by `milkir_machv`.
fn lower_external_call(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  symbol : @milkir.ExternalSymbol,
) -> Unit {
  let args : Array[@abi.VReg] = []
  for i, operand in inst.operands {
    if i == 0 &&
      ctx.embedding_abi().reserve_context_role &&
      ctx.ir_func.params.length() > 0 &&
      operand.id == ctx.ir_func.params[0].0.id {
      let context_vreg = ctx.machv_func.new_vreg(Int)
      let context_mov = @instr.Inst(Move)
      context_mov.add_def({ reg: Virtual(context_vreg) })
      context_mov.add_use(Physical(context_preg(ctx)))
      block.add_inst(context_mov)
      args.push(context_vreg)
    } else {
      args.push(ctx.get_vreg_for_use(operand, block))
    }
  }
  let result_vregs = collect_call_result_vregs(ctx, inst)
  if result_vregs.length() > 1 {
    abort("external C ABI call supports at most one direct result")
  }
  let result = if result_vregs.length() == 1 {
    Some(result_vregs[0])
  } else {
    None
  }
  lower_c_libcall_direct(ctx, block, ExternalName(symbol.name), args, result)
}

///|
/// Lower a simple C libcall with integer arguments.
/// This is for calling C runtime functions like GC helpers.
/// Uses ISA C calling convention (register args + stack overflow args).
///
/// Unlike lower_call_ptr which handles the embedding call convention,
/// this is for simple C functions where args follow the platform C ABI.
pub fn lower_c_libcall(
  ctx : LoweringContext,
  block : @block.Block,
  func_ptr : @abi.VReg,
  args : Array[@abi.VReg],
  result : @abi.VReg?,
) -> Unit {
  fn c_arg_gpr_indices() -> Array[Int] {
    match ctx.isa {
      // AAPCS64: X0-X7
      AArch64 => [0, 1, 2, 3, 4, 5, 6, 7]
      // SysV AMD64: RDI,RSI,RDX,RCX,R8,R9 (in our 0..15 numbering)
      AMD64 => [7, 6, 2, 1, 8, 9]
    }
  }

  let arg_regs = c_arg_gpr_indices()

  // Create a foreign call with platform-ABI constraints.
  let num_args = args.length()
  let result_classes : Array[@abi.RegClass] = []
  if result is Some(dst) {
    result_classes.push(dst.class)
  }
  let call_inst = @instr.Inst(CallPtr(num_args, result_classes, Foreign))

  // Call target is constrained to SCRATCH_REG_2 (IP1).
  call_inst.add_use_fixed(Virtual(func_ptr), {
    index: scratch2_index(ctx),
    class: Int,
  })

  // Args constrained to C ABI arg regs (ISA-dependent).
  let reg_arg_count = if args.length() < arg_regs.length() {
    args.length()
  } else {
    arg_regs.length()
  }
  for i in 0..<reg_arg_count {
    let arg = args[i]
    call_inst.add_use_fixed(Virtual(arg), { index: arg_regs[i], class: Int })
  }
  emit_c_overflow_arg_stores(ctx, block, args, arg_regs.length())

  // Result constrained to the C ABI integer return register.
  if result is Some(dst) {
    call_inst.add_def_fixed({ reg: Virtual(dst) }, { index: 0, class: Int })
  }

  // Add clobbers for all caller-saved registers
  add_call_clobbers(ctx, call_inst)
  block.add_inst(call_inst)
  invalidate_context_pointer_cache(ctx)
}

///|
/// Helper to materialize an immediate value into a vreg
pub fn materialize_imm(
  ctx : LoweringContext,
  block : @block.Block,
  value : Int64,
) -> @abi.VReg {
  let vreg = ctx.machv_func.new_vreg(Int)
  let mov = @instr.Inst(LoadConst(value))
  mov.add_def({ reg: Virtual(vreg) })
  block.add_inst(mov)
  vreg
}
