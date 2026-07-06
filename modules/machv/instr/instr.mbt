///|
/// Call type - classifies instructions that behave like calls
/// CallType enum for different call variants
pub(all) enum CallType {
  None // Not a call instruction
  Regular // Regular call that returns to caller
  TailCall // Tail call that doesn't return to caller
}

///|
/// Call-site clobber class for register allocation and optimization barriers.
pub(all) enum CallClobberClass {
  Internal // Same-embedding ABI call.
  Foreign // Foreign/helper ABI call with conservative clobbers.
} derive(Eq, Debug)

///|
/// Symbolic name for a runtime or external helper address.
///
/// MachV treats this as an opaque relocation key. Product-specific packages,
/// such as `wasmoon_jit`, own the mapping from names to native addresses.
pub(all) struct ExternalName {
  name : String
} derive(Eq, Debug, Hash)

///|
/// Symbolic name for code owned by the embedding.
///
/// MachV treats this as an opaque relocation key. Frontends may use the
/// scope and ordinal to map their own function identifiers to this generic
/// code target without exposing those identifiers in MachV opcodes.
pub(all) struct CodeSymbol {
  scope : String
  ordinal : Int
} derive(Eq, Debug, Hash)

///|
/// Target for a relocatable code address or direct call.
pub(all) enum RelocTarget {
  Code(CodeSymbol)
  External(ExternalName)
} derive(Eq, Debug)

///|
pub impl Show for CallClobberClass with fn output(self, logger) {
  match self {
    Internal => logger.write_string("Internal")
    Foreign => logger.write_string("Foreign")
  }
}

///|
pub fn ExternalName::new(name : String) -> ExternalName {
  { name, }
}

///|
pub fn CodeSymbol::new(scope : String, ordinal : Int) -> CodeSymbol {
  { scope, ordinal }
}

///|
pub impl Show for ExternalName with fn output(self, logger) {
  logger.write_string(self.name)
}

///|
pub impl Show for CodeSymbol with fn output(self, logger) {
  if self.scope == "" {
    logger.write_string("code.\{self.ordinal}")
  } else {
    logger.write_string("\{self.scope}.\{self.ordinal}")
  }
}

///|
pub impl Show for RelocTarget with fn output(self, logger) {
  match self {
    Code(symbol) => logger.write_string(symbol.to_string())
    External(symbol) => logger.write_string(symbol.name)
  }
}

///|
pub fn RelocTarget::key(self : RelocTarget) -> String {
  match self {
    Code(symbol) => "code:\{symbol.scope}:\{symbol.ordinal}"
    External(symbol) => "external:\{symbol.name}"
  }
}

///|
/// VCode instruction - a machine-level instruction with virtual registers
/// Operand constraints for fixed register allocation
pub struct VCodeInst {
  opcode : VCodeOpcode
  defs : Array[@abi.Writable] // Registers defined (written)
  uses : Array[@abi.Reg] // Registers used (read)
  use_constraints : Array[@abi.OperandConstraint] // Constraints for uses
  def_constraints : Array[@abi.OperandConstraint] // Constraints for defs
}

///|
pub fn VCodeInst::new(opcode : VCodeOpcode) -> VCodeInst {
  { opcode, defs: [], uses: [], use_constraints: [], def_constraints: [] }
}

///|
pub fn VCodeInst::add_def(self : VCodeInst, reg : @abi.Writable) -> Unit {
  self.defs.push(reg)
  self.def_constraints.push(Any)
}

///|
pub fn VCodeInst::add_use(self : VCodeInst, reg : @abi.Reg) -> Unit {
  self.uses.push(reg)
  self.use_constraints.push(Any)
}

///|
/// Add a use operand with a fixed register constraint
pub fn VCodeInst::add_use_fixed(
  self : VCodeInst,
  reg : @abi.Reg,
  preg : @abi.PReg,
) -> Unit {
  self.uses.push(reg)
  self.use_constraints.push(FixedReg(preg))
}

///|
/// Add a def operand with a fixed register constraint
pub fn VCodeInst::add_def_fixed(
  self : VCodeInst,
  reg : @abi.Writable,
  preg : @abi.PReg,
) -> Unit {
  self.defs.push(reg)
  self.def_constraints.push(FixedReg(preg))
}

///|
fn VCodeInst::to_string(self : VCodeInst) -> String {
  let mut result = ""
  // Print definitions (skip clobbers for call instructions)
  let defs_to_print = match self.opcode {
    ReturnCallIndirect(_, num_results) | CallPtr(_, num_results, _) =>
      // Only print result registers, not clobbers
      self.defs.iter().take(num_results).collect()
    CallExternalIfI32NeImm(_, _) =>
      // Only clobbers are attached (no results); keep output compact.
      []
    _ => self.defs
  }
  if defs_to_print.length() > 0 {
    for i, def in defs_to_print {
      if i > 0 {
        result = result + ", "
      }
      result = result + def.to_string()
    }
    result = result + " = "
  }
  // Print opcode
  result = result + self.opcode.to_string()
  // Print uses (simplified for call instructions)
  if self.opcode is ReturnCallIndirect(_, _) || self.opcode is CallPtr(_, _, _) {
    // For call instructions, only print the function pointer (first use)
    if self.uses.length() > 0 {
      result = result + " " + self.uses[0].to_string()
    }
  } else if self.uses.length() > 0 {
    result = result + " "
    for i, use_ in self.uses {
      if i > 0 {
        result = result + ", "
      }
      result = result + use_.to_string()
    }
  }
  result
}

///|
pub impl Show for VCodeInst with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// VCode opcode - machine-level operation (target-independent subset)
pub(all) enum VCodeOpcode {
  // Integer arithmetic (Bool = true for 64-bit, false for 32-bit)
  Add(Bool) // ADD with size: true = 64-bit, false = 32-bit
  AddImm(Int, Bool) // ADD Xd, Xn, #imm with size: true = 64-bit, false = 32-bit
  Sub(Bool) // SUB with size: true = 64-bit, false = 32-bit
  SubImm(Int, Bool) // SUB Xd, Xn, #imm with size: true = 64-bit, false = 32-bit
  Mul(Bool) // MUL with size: true = 64-bit, false = 32-bit
  SDiv(Bool) // SDIV with size: true = 64-bit, false = 32-bit
  UDiv(Bool) // UDIV with size: true = 64-bit, false = 32-bit
  // x86_64: explicit remainder opcodes (lowered only on x86_64).
  // This matches Cranelift's checked remainder sequences to avoid x86 IDIV
  // overflow traps for `INT_MIN % -1`.
  SRem(Bool) // SREM with size: true = 64-bit, false = 32-bit
  URem(Bool) // UREM with size: true = 64-bit, false = 32-bit
  // Bitwise operations (Bool = true for 64-bit, false for 32-bit)
  And(Bool)
  AndImm(Int64, Bool) // AND (immediate logical), value is the immediate pattern
  Or(Bool)
  OrImm(Int64, Bool) // ORR (immediate logical), value is the immediate pattern
  Xor(Bool)
  XorImm(Int64, Bool) // EOR (immediate logical), value is the immediate pattern
  Shl(Bool) // LSL with size
  ShlImm(Int, Bool) // LSL with immediate shift amount (masked per Wasm semantics)
  AShr(Bool) // Arithmetic shift right with size
  AShrImm(Int, Bool) // ASR with immediate shift amount (masked per Wasm semantics)
  LShr(Bool) // Logical shift right with size
  LShrImm(Int, Bool) // LSR with immediate shift amount (masked per Wasm semantics)
  Rotr(Bool) // Rotate right with size
  RotrImm(Int, Bool) // ROR with immediate shift amount (masked per Wasm semantics)
  // AArch64 EXTR immediate forms:
  //   extr rd, rn, rm, #shift  (64-bit)
  //   extr wD, wN, wM, #shift  (32-bit)
  // Encodes: (rn << (bits - shift)) | (rm >> shift)
  // Used by Cranelift-style lowering for:
  //   (x << a) | (y >> b)  where a + b == bitwidth.
  ExtrImm(Int, Bool) // EXTR immediate shift amount, Bool=true(64)/false(32)
  Not(Bool) // Bitwise NOT with size: true = 64-bit, false = 32-bit
  AndNot(Bool) // x & ~y
  OrNot(Bool) // x | ~y
  XorNot(Bool) // x ^ ~y
  // Floating-point operations (Bool = true for f32, false for f64)
  FAdd(Bool)
  FSub(Bool)
  FMul(Bool)
  FDiv(Bool)
  FMin(Bool)
  FMax(Bool)
  FSqrt(Bool)
  FAbs(Bool)
  FNeg(Bool)
  FCeil(Bool)
  FFloor(Bool)
  FTrunc(Bool)
  FNearest(Bool)
  // Memory operations
  Load(MemType, Int) // type, offset
  Store(MemType, Int) // type, offset
  // Narrow load operations (8/16-bit with sign/zero extension)
  Load8S(Int) // Load 8-bit signed, sign-extend to 32/64-bit (offset)
  Load8U(Int) // Load 8-bit unsigned, zero-extend to 32/64-bit (offset)
  Load16S(Int) // Load 16-bit signed, sign-extend to 32/64-bit (offset)
  Load16U(Int) // Load 16-bit unsigned, zero-extend to 32/64-bit (offset)
  Load32S(Int) // Load 32-bit signed, sign-extend to 64-bit (offset)
  Load32U(Int) // Load 32-bit unsigned, zero-extend to 64-bit (offset)
  // Moves
  Move
  LoadConst(Int64) // Load immediate
  LoadConstF32(Int) // Load f32 immediate (stored as bits)
  LoadConstF64(Int64) // Load f64 immediate (stored as bits)
  // Comparisons (result is 0 or 1)
  // Cmp(kind, is_64bit): CMP Xn/Wn, Xm/Wm; CSET Wd, cond
  Cmp(CmpKind, Bool)
  // IntCmp(is_64bit): CMP Xn/Wn, Xm/Wm
  // Uses: [lhs, rhs], Defs: [] (only sets flags)
  // Used before TrapIf when no boolean compare result is needed.
  IntCmp(Bool)
  FCmp(FCmpKind)
  // Conversions
  Extend(ExtendKind)
  Truncate
  IntToFloat(IntToFloatKind)
  FPromote // f32 -> f64
  FDemote // f64 -> f32
  Bitcast // Reinterpret bits between int/float of same size
  // Conditional select
  // Select: Xd = cond ? Xn : Xm
  // Uses: [cond, true_val, false_val], Defs: [result]
  Select
  // SelectCmp: Fused compare and select
  // SelectCmp(kind, is_64): CMP lhs, rhs; CSEL Xd, true_val, false_val, cond
  // Uses: [cmp_lhs, cmp_rhs, true_val, false_val], Defs: [result]
  // Saves one instruction compared to separate CMP + CSET + Select
  SelectCmp(CmpKind, Bool)
  // Bit counting operations (Bool = true for 64-bit, false for 32-bit)
  Clz(Bool) // Count leading zeros with size
  Popcnt(Bool) // Population count with size
  Rbit(Bool) // Reverse bits in register with size
  // Special
  Nop
  // Trap if first operand is unsigned greater than second operand
  // TrapIfUgt(trap_code): CMP rn, rm; B.LS skip; BRK #trap_code
  // Uses: [lhs, rhs], traps if lhs > rhs (unsigned)
  TrapIfUgt(Int)
  // Trap if first operand is unsigned greater than or equal to second operand
  // TrapIfUge(trap_code): CMP rn, rm; B.LO skip; BRK #trap_code
  // Uses: [lhs, rhs], traps if lhs >= rhs (unsigned)
  TrapIfUge(Int)

  // Floating-point compare (sets NZCV flags, no result value)
  // FpuCmp(is_f32): FCMP Sn, Sm or FCMP Dn, Dm
  // Uses: [lhs, rhs], Defs: [] (only sets flags)
  // Used for NaN check (compare with self) and bound checks
  FpuCmp(Bool)

  // Conditional trap based on condition flags
  // TrapIf(cond, trap_code): B.cond skip; BRK #trap_code
  // Uses: [], Defs: [] (uses flags from previous compare)
  // trap_code: 1=out_of_bounds, 2=type_mismatch, 3=bad_conversion, 4=integer_overflow
  TrapIf(Cond, Int)

  // Trap if operand is zero (for division by zero)
  // TrapIfZero(is_64, trap_code): CBNZ rn, skip; BRK #trap_code
  // Uses: [rn], Defs: [] (traps if rn is zero)
  TrapIfZero(Bool, Int)

  // Trap if signed division would overflow (INT_MIN / -1)
  // TrapIfDivOverflow(is_64, trap_code): checks if lhs == INT_MIN && rhs == -1
  // Uses: [lhs, rhs], Defs: [] (traps if overflow would occur)
  TrapIfDivOverflow(Bool, Int)

  // Raw float-to-int conversion (FCVTZS/FCVTZU without NaN/overflow checks)
  // FcvtToInt(is_f32, is_i64, is_signed): FCVTZS/FCVTZU Wd/Xd, Sn/Dn
  // Uses: [src_fp], Defs: [dst_int]
  // The trapping FloatToInt opcodes are expanded in lower phase to:
  //   FpuCmp + TrapIf(Vs) + LoadConstF32/F64 + FpuCmp + TrapIf + ... + FcvtToInt
  FcvtToInt(Bool, Bool, Bool)

  // Floating-point conditional select (for saturating conversions)
  // FpuSel(is_f32, cond): FCSEL Sd, Sn, Sm, cond or FCSEL Dd, Dn, Dm, cond
  // Uses: [true_val, false_val], Defs: [result]
  // Selects true_val if condition is true, false_val otherwise
  // Used for NaN handling: select 0.0 if NaN, original value otherwise
  FpuSel(Bool, Cond)

  // Floating-point maximum (NaN-propagating)
  // FpuMaxnm(is_f32): FMAXNM Sd, Sn, Sm or FMAXNM Dd, Dn, Dm
  // Uses: [lhs, rhs], Defs: [result]
  // Returns the larger value; if one is NaN, returns the other
  FpuMaxnm(Bool)

  // Floating-point minimum (NaN-propagating)
  // FpuMinnm(is_f32): FMINNM Sd, Sn, Sm or FMINNM Dd, Dn, Dm
  // Uses: [lhs, rhs], Defs: [result]
  // Returns the smaller value; if one is NaN, returns the other
  FpuMinnm(Bool)

  // AArch64-specific: shifted operand instructions
  // These combine an arithmetic/logical op with a shift in one instruction
  AddShifted(ShiftType, Int) // ADD Xd, Xn, Xm, shift #amount
  AddExtend(IndexExtend, Int) // ADD Xd, Xn, Wm, {uxtw|sxtw} #amount
  SubExtend(IndexExtend, Int) // SUB Xd, Xn, Wm, {uxtw|sxtw} #amount
  SubShifted(ShiftType, Int) // SUB Xd, Xn, Xm, shift #amount
  AndShifted(ShiftType, Int) // AND Xd, Xn, Xm, shift #amount
  OrShifted(ShiftType, Int) // ORR Xd, Xn, Xm, shift #amount
  XorShifted(ShiftType, Int) // EOR Xd, Xn, Xm, shift #amount
  // 32-bit shifted operand forms (Cranelift-aligned for i32 lowering)
  AddShifted32(ShiftType, Int) // ADD Wd, Wn, Wm, shift #amount
  SubShifted32(ShiftType, Int) // SUB Wd, Wn, Wm, shift #amount
  AndShifted32(ShiftType, Int) // AND Wd, Wn, Wm, shift #amount
  OrShifted32(ShiftType, Int) // ORR Wd, Wn, Wm, shift #amount
  XorShifted32(ShiftType, Int) // EOR Wd, Wn, Wm, shift #amount
  // AArch64-specific: multiply-accumulate instructions
  Madd // Xd = Xa + Xn * Xm (3 uses: acc, src1, src2)
  Msub // Xd = Xa - Xn * Xm (3 uses: acc, src1, src2)
  Mneg // Xd = -(Xn * Xm) (2 uses: src1, src2)
  // 32-bit multiply-accumulate forms (Cranelift fits_in_64 i32 coverage)
  Madd32 // Wd = Wa + Wn * Wm (3 uses: acc, src1, src2)
  Msub32 // Wd = Wa - Wn * Wm (3 uses: acc, src1, src2)
  Mneg32 // Wd = -(Wn * Wm) (2 uses: src1, src2)
  // AArch64-specific: multiply high instructions
  Umulh // Xd = (Xn * Xm) >> 64 (unsigned multiply high, 64-bit only)
  Smulh // Xd = (Xn * Xm) >> 64 (signed multiply high, 64-bit only)
  Umull // Xd = Wn * Wm (unsigned 32x32->64 multiply)
  Smull // Xd = Wn * Wm (signed 32x32->64 multiply)
  // Function calls
  // ReturnCallIndirect: tail call through a function pointer
  // Uses: [func_ptr, arg0, arg1, ...]
  // Parameters:
  // - stack_arg_bytes: bytes of overflow stack args for this tail call
  // - num_results: reserved metadata (currently informational)
  // This is a terminator - it does not return to the caller
  ReturnCallIndirect(Int, Int)
  // CallExternalIfI32NeImm: fast-path conditional helper call.
  //
  // Uses: [actual_i32_vreg]
  // Parameters: expected_i32 (immediate), helper (external symbol)
  //
  // Semantics:
  // - If actual_i32 == expected_i32: do nothing.
  // - Otherwise: call helper(actual_i32, expected_i32).
  //
  // TODO(ISS-071): Lower this generic pseudo-op into explicit MachV CFG once
  // block-local cold-path helper calls can be represented without emitter-local
  // labels.
  CallExternalIfI32NeImm(Int, ExternalName)
  // Stack operations for spilling
  // StackLoad(offset): Load from [SP + offset] into the def register
  // StackStore(offset): Store the use register to [SP + offset]
  StackLoad(Int)
  StackStore(Int)
  // Stack parameter load (for params that overflow registers)
  // LoadStackParam(offset, class):
  //   offset: byte offset from entry SP (start of overflow area)
  // Stack layout: [int_overflow..., float_overflow...] with V128 aligned to 16.
  LoadStackParam(Int, @abi.RegClass)
  // NOTE: memory.grow/size/fill/copy and table.grow are lowered to foreign calls.
  // NOTE: TableGet, TableSet are desugared at IR level via FuncEnvironment to LoadPtr/StorePtr
  // NOTE: GlobalGet, GlobalSet are desugared at IR level via FuncEnvironment to LoadPtr/StorePtr

  // Raw pointer operations (for trampolines, no bounds checking)
  // LoadPtr(type, offset): Load from [base + offset]
  // Uses: [base], Defs: [result]
  LoadPtr(MemType, Int)
  // LoadPtrRegOffset(type, extend, shift, offset):
  // Load from [base + index{, extend}{, scale} + offset]
  // Uses: [base, index], Defs: [result]
  // - extend: None uses X index; Uxtw/Sxtw use W index extended to X
  // - shift: 0 (no scale) or log2(access_size) (scaled register offset)
  // - offset: signed displacement in bytes
  LoadPtrRegOffset(MemType, IndexExtend, Int, Int)
  // LoadPtrNarrowRegOffset(bits, signed, extend, shift, offset): narrow load from
  // [base + index{, extend}{, scale} + offset] where bits is 8/16/32.
  // Uses: [base, index], Defs: [result]
  LoadPtrNarrowRegOffset(Int, Bool, IndexExtend, Int, Int)
  // StorePtr(type, offset): Store to [base + offset]
  // Uses: [base, value], Defs: []
  StorePtr(MemType, Int)
  // StorePtrRegOffset(type, extend, shift, offset):
  // Store to [base + index{, extend}{, scale} + offset]
  // Uses: [base, index, value], Defs: []
  StorePtrRegOffset(MemType, IndexExtend, Int, Int)
  // StorePtrNarrowRegOffset(bits, extend, shift, offset): narrow store to
  // [base + index{, extend}{, scale} + offset] where bits is 8/16/32.
  // Uses: [base, index, value], Defs: []
  StorePtrNarrowRegOffset(Int, IndexExtend, Int, Int)
  // LoadPtrNarrow(bits, signed, offset): Load narrow value from [base + offset]
  // Uses: [base], Defs: [result]
  LoadPtrNarrow(Int, Bool, Int) // (bits, signed, offset)
  // StorePtrNarrow(bits, offset): Store narrow value to [base + offset]
  // Uses: [base, value], Defs: []
  StorePtrNarrow(Int, Int) // (bits, offset)

  // Load external function pointer
  // LoadExternalFuncAddr(symbol): Load function pointer for an external helper.
  // Uses: [], Defs: [result (function pointer)]
  LoadExternalFuncAddr(ExternalName)

  // Load code address (resolved by embedding relocation/fixup metadata)
  // LoadCodeAddr(symbol): Load function/code pointer for symbol
  // Uses: [], Defs: [result (function pointer)]
  LoadCodeAddr(CodeSymbol)

  // CallPtr: call through a function pointer
  // Uses are already constrained by the lowering-selected ABI.
  // Defs: [result0, result1, ...] (multiple results supported)
  // Parameters: num_args, num_results, clobber class
  CallPtr(Int, Int, CallClobberClass)

  // CallDirect: direct call to a known code symbol
  // Uses are already constrained by the lowering-selected ABI.
  // Defs: [result0, result1, ...]
  // Parameters: target, num_args, num_results, clobber class
  CallDirect(CodeSymbol, Int, Int, CallClobberClass)

  // CallExternal: direct call to an external helper symbol.
  // Uses are already constrained by the lowering-selected ABI.
  // Defs: [result0, result1, ...]
  // Parameters: symbol, num_args, num_results, clobber class
  CallExternal(ExternalName, Int, Int, CallClobberClass)

  // Stack pointer adjustment for outgoing call arguments (Standard)
  // AdjustSP(delta): Adjust SP by delta bytes
  //   delta > 0: deallocate (add to SP)
  //   delta < 0: allocate (sub from SP)
  // Used in call lowering to allocate space for overflow args
  AdjustSP(Int)

  // Store to outgoing call argument area (Standard)
  // StoreToStack(offset): Store use[0] to [SP + offset]
  // Used in call lowering to store overflow args before the call
  // Uses: [value], Defs: []
  StoreToStack(Int)

  // Load outgoing-args base pointer into a register
  // LoadSP: Defs: [result], Uses: []
  // Used for passing stack addresses to C helpers that consume StoreToStack data
  LoadSP

  // GC inline allocation helpers (fast path + C slow-path fallback)
  //
  // GCAllocStructInline(type_idx, num_fields):
  //   Uses: [vmctx], Defs: [result_ref]
  //   - Fast path: inline bump allocation + header/field stores.
  //   - Fields source is fixed to caller stack pointer (SP outgoing args area).
  //   - Slow path: calls gc_alloc_struct_slow(vmctx, type_idx, SP, num_fields).
  //   - Always registers allocated object via gc_register_struct_inline.
  GCAllocStructInline(Int, Int, ExternalName, ExternalName)

  // GCAllocStructSlowPrecise(type_idx, num_fields):
  //   Uses: [vmctx], Defs: [result_ref]
  //   - Calls gc_alloc_struct_slow(vmctx, type_idx, SP, num_fields, safepoint_id).
  //   - Emits safepoint metadata (root indices [0..num_fields-1]).
  GCAllocStructSlowPrecise(Int, Int, ExternalName)

  // GCAllocArrayFixedInline(type_idx, len):
  //   Uses: [vmctx], Defs: [result_ref]
  //   - Fast path: inline bump allocation + header/len/element stores.
  //   - Values source is fixed to caller stack pointer (SP outgoing args area).
  //   - Slow path: calls gc_alloc_array_from_values_slow(vmctx, type_idx, SP, len).
  //   - Always registers allocated object via gc_register_array_inline.
  GCAllocArrayFixedInline(Int, Int, ExternalName, ExternalName)

  // GCAllocArraySlowPrecise(type_idx):
  //   Uses: [vmctx, len, init_value], Defs: [result_ref]
  //   - Calls gc_alloc_array_slow(vmctx, type_idx, len, init_value, safepoint_id).
  //   - Emits safepoint metadata (root index [0] for init_value).
  GCAllocArraySlowPrecise(Int, ExternalName)

  // ============ SIMD Instructions (AArch64 NEON) ============

  // V128 constant load - load 128-bit immediate
  // LoadConstV128(bytes): MOVI or load from constant pool
  // Uses: [], Defs: [result]
  LoadConstV128(Bytes)

  // Splat - replicate scalar to all vector lanes
  // SIMDSplat(lane_size): DUP Vd.T, Wn/Xn
  // Uses: [scalar], Defs: [vector]
  SIMDSplat(LaneSize)

  // Splat from floating-point register
  // SIMDSplatF(is_f32): DUP Vd.4S, Vn.S[0] or DUP Vd.2D, Vn.D[0]
  // Uses: [fp_scalar], Defs: [vector]
  SIMDSplatF(Bool)

  // Extract lane to GPR (unsigned)
  // SIMDExtractU(lane_size, lane): UMOV Wd/Xd, Vn.T[lane]
  // Uses: [vector], Defs: [scalar]
  SIMDExtractU(LaneSize, Int)

  // Extract lane to GPR (signed)
  // SIMDExtractS(lane_size, lane): SMOV Wd/Xd, Vn.T[lane]
  // Uses: [vector], Defs: [scalar]
  SIMDExtractS(LaneSize, Int)

  // Extract lane to FPR
  // SIMDExtractF(is_f32, lane): DUP Sd/Dd, Vn.S[lane]/Vn.D[lane]
  // Uses: [vector], Defs: [fp_scalar]
  SIMDExtractF(Bool, Int)

  // Replace lane from GPR
  // SIMDInsert(lane_size, lane): INS Vd.T[lane], Wn/Xn
  // Uses: [vector, scalar], Defs: [vector]
  SIMDInsert(LaneSize, Int)

  // Replace lane from FPR
  // SIMDInsertF(is_f32, lane): INS Vd.S[lane], Vn.S[0] or Vd.D[lane], Vn.D[0]
  // Uses: [vector, fp_scalar], Defs: [vector]
  SIMDInsertF(Bool, Int)

  // Shuffle - select lanes from two vectors using immediate indices
  // Uses two TBL1 calls to avoid consecutive register requirement
  // Uses: [v1, v2], Defs: [result, temp1, temp2] (2 temp FPRs for TBL1 intermediates)
  SIMDShuffle(FixedArray[Int])

  // Swizzle - permute lanes based on indices vector
  // SIMDSwizzle: TBL Vd.16B, {Vn.16B}, Vm.16B
  // Uses: [values, indices], Defs: [result]
  SIMDSwizzle

  // Bitwise NOT
  // SIMDNot: NOT Vd.16B, Vn.16B (same as MVN)
  // Uses: [vector], Defs: [result]
  SIMDNot

  // Bitwise AND
  // SIMDAnd: AND Vd.16B, Vn.16B, Vm.16B
  // Uses: [v1, v2], Defs: [result]
  SIMDAnd

  // Bitwise AND-NOT (a & ~b)
  // SIMDBic: BIC Vd.16B, Vn.16B, Vm.16B
  // Uses: [v1, v2], Defs: [result]
  SIMDBic

  // Bitwise OR
  // SIMDOr: ORR Vd.16B, Vn.16B, Vm.16B
  // Uses: [v1, v2], Defs: [result]
  SIMDOr

  // Bitwise XOR
  // SIMDXor: EOR Vd.16B, Vn.16B, Vm.16B
  // Uses: [v1, v2], Defs: [result]
  SIMDXor

  // Bitselect - select bits from two vectors based on mask
  // SIMDBsl: BSL Vd.16B, Vn.16B, Vm.16B (Vd = (Vn & Vd) | (Vm & ~Vd))
  // Uses: [v1, v2, mask], Defs: [result]
  SIMDBsl

  // Any true - check if any lane is non-zero
  // SIMDAnyTrue: UMAXV Bd, Vn.16B; UMOV Wd, Vd.B[0]; CMP Wd, #0; CSET Wd, ne
  // Uses: [vector], Defs: [result (i32)]
  SIMDAnyTrue

  // All true - check if all lanes are non-zero
  // SIMDAllTrue(lane_size): UMINV + check
  // Uses: [vector], Defs: [result (i32)]
  SIMDAllTrue(LaneSize)

  // Bitmask - extract sign bits to GPR
  // SIMDBitmask(lane_size): extract MSB of each lane
  // Uses: [vector], Defs: [result (i32)]
  // For B8: Defs: [result, temp_weights, temp_shift, temp_work] (3 temp FPRs)
  SIMDBitmask(LaneSize)

  // Integer add
  // SIMDAdd(lane_size): ADD Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDAdd(LaneSize)

  // Integer subtract
  // SIMDSub(lane_size): SUB Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDSub(LaneSize)

  // Integer multiply (no 64-bit variant in NEON)
  // SIMDMul(lane_size): MUL Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDMul(LaneSize)

  // Saturating add (signed)
  // SIMDSqadd(lane_size): SQADD Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDSqadd(LaneSize)

  // Saturating add (unsigned)
  // SIMDUqadd(lane_size): UQADD Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDUqadd(LaneSize)

  // Saturating subtract (signed)
  // SIMDSqsub(lane_size): SQSUB Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDSqsub(LaneSize)

  // Saturating subtract (unsigned)
  // SIMDUqsub(lane_size): UQSUB Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDUqsub(LaneSize)

  // Minimum (signed)
  // SIMDSmin(lane_size): SMIN Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDSmin(LaneSize)

  // Minimum (unsigned)
  // SIMDUmin(lane_size): UMIN Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDUmin(LaneSize)

  // Maximum (signed)
  // SIMDSmax(lane_size): SMAX Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDSmax(LaneSize)

  // Maximum (unsigned)
  // SIMDUmax(lane_size): UMAX Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDUmax(LaneSize)

  // Unsigned rounding halving add (average)
  // SIMDUrhadd(lane_size): URHADD Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDUrhadd(LaneSize)

  // Absolute value
  // SIMDAbs(lane_size): ABS Vd.T, Vn.T
  // Uses: [vector], Defs: [result]
  SIMDAbs(LaneSize)

  // Negate
  // SIMDNeg(lane_size): NEG Vd.T, Vn.T
  // Uses: [vector], Defs: [result]
  SIMDNeg(LaneSize)

  // Population count per byte
  // SIMDCnt: CNT Vd.16B, Vn.16B
  // Uses: [vector], Defs: [result]
  SIMDCnt

  // Broadcast shift amount to vector (mask and DUP)
  // SIMDBroadcastShift(lane_size, negate): mask scalar, optionally negate, DUP to all lanes
  // Uses: [shift_scalar], Defs: [temp_gpr, shift_vec]
  // temp_gpr: GPR for masked (and optionally negated) shift value
  // shift_vec: FPR with shift amount broadcast to all lanes
  // negate=true for right shifts (shift amount needs to be negated for SSHL/USHL)
  SIMDBroadcastShift(LaneSize, Bool)

  // Vector shift (input already broadcast)
  // SIMDShiftByVec(lane_size, use_ushl): SSHL or USHL
  // Uses: [input_vec, shift_vec], Defs: [result]
  // use_ushl=false for SSHL (left shift, signed right shift)
  // use_ushl=true for USHL (unsigned right shift)
  SIMDShiftByVec(LaneSize, Bool)

  // Integer comparison
  // SIMDCmp(lane_size, cmp_kind): CMEQ/CMGT/CMGE/CMHI/CMHS Vd.T, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDCmp(LaneSize, SIMDCmpKind)

  // Narrow (pack two vectors to narrower lanes)
  // SIMDNarrow(dst_lane_size, signed): XTN/SQXTN/SQXTUN/UQXTN Vd.T, Vn.T2
  // Uses: [v1, v2], Defs: [result]
  SIMDNarrow(LaneSize, Bool)

  // Extend low half (widen to larger lanes)
  // SIMDExtendLow(dst_lane_size, signed): SXTL/UXTL Vd.T2, Vn.T
  // Uses: [vector], Defs: [result]
  SIMDExtendLow(LaneSize, Bool)

  // Extend high half (widen to larger lanes)
  // SIMDExtendHigh(dst_lane_size, signed): SXTL2/UXTL2 Vd.T2, Vn.T
  // Uses: [vector], Defs: [result]
  SIMDExtendHigh(LaneSize, Bool)

  // Extended multiply low
  // SIMDExtMulLow(dst_lane_size, signed): SMULL/UMULL Vd.T2, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDExtMulLow(LaneSize, Bool)

  // Extended multiply high
  // SIMDExtMulHigh(dst_lane_size, signed): SMULL2/UMULL2 Vd.T2, Vn.T, Vm.T
  // Uses: [v1, v2], Defs: [result]
  SIMDExtMulHigh(LaneSize, Bool)

  // Extended add pairwise
  // SIMDExtAddPairwise(dst_lane_size, signed): SADDLP/UADDLP Vd.T2, Vn.T
  // Uses: [vector], Defs: [result]
  SIMDExtAddPairwise(LaneSize, Bool)

  // Dot product (i32x4.dot_i16x8_s)
  // SIMDDot: sequence of SMULL + SADDLP or SMLAL
  // Uses: [v1, v2], Defs: [result]
  SIMDDot

  // Q15 saturating rounding multiply high
  // SIMDQ15MulrSat: SQRDMULH Vd.8H, Vn.8H, Vm.8H
  // Uses: [v1, v2], Defs: [result]
  SIMDQ15MulrSat

  // Floating-point add
  // SIMDFAdd(is_f32): FADD Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFAdd(Bool)

  // Floating-point subtract
  // SIMDFSub(is_f32): FSUB Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFSub(Bool)

  // Floating-point multiply
  // SIMDFMul(is_f32): FMUL Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFMul(Bool)

  // Floating-point divide
  // SIMDFDiv(is_f32): FDIV Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFDiv(Bool)

  // Floating-point min (propagating NaN)
  // SIMDFMin(is_f32): FMIN Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFMin(Bool)

  // Floating-point max (propagating NaN)
  // SIMDFMax(is_f32): FMAX Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFMax(Bool)

  // Floating-point pmin (pseudo-min, returns b if a is NaN)
  // SIMDFPMin(is_f32): FCMGT + BSL sequence
  // Uses: [v1, v2], Defs: [result]
  SIMDFPMin(Bool)

  // Floating-point pmax (pseudo-max, returns b if a is NaN)
  // SIMDFPMax(is_f32): FCMGT + BSL sequence
  // Uses: [v1, v2], Defs: [result]
  SIMDFPMax(Bool)

  // Floating-point absolute value
  // SIMDFAbs(is_f32): FABS Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFAbs(Bool)

  // Floating-point negate
  // SIMDFNeg(is_f32): FNEG Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFNeg(Bool)

  // Floating-point square root
  // SIMDFSqrt(is_f32): FSQRT Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFSqrt(Bool)

  // Floating-point ceiling
  // SIMDFCeil(is_f32): FRINTP Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFCeil(Bool)

  // Floating-point floor
  // SIMDFFloor(is_f32): FRINTM Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFFloor(Bool)

  // Floating-point truncate
  // SIMDFTrunc(is_f32): FRINTZ Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFTrunc(Bool)

  // Floating-point nearest
  // SIMDFNearest(is_f32): FRINTN Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFNearest(Bool)

  // Floating-point comparison
  // SIMDFCmp(is_f32, cmp_kind): FCMEQ/FCMGT/FCMGE Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [v1, v2], Defs: [result]
  SIMDFCmp(Bool, SIMDFCmpKind)

  // Conversions
  // SIMDFCvtToIntS(is_f32): FCVTZS Vd.4S/2D, Vn.4S/2D (f32->i32 or f64->i64)
  // Uses: [vector], Defs: [result]
  SIMDFCvtToIntS(Bool)

  // SIMDFCvtToIntU(is_f32): FCVTZU Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDFCvtToIntU(Bool)

  // SIMDIntToFloatS(is_f32): SCVTF Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDIntToFloatS(Bool)

  // SIMDIntToFloatU(is_f32): UCVTF Vd.4S/2D, Vn.4S/2D
  // Uses: [vector], Defs: [result]
  SIMDIntToFloatU(Bool)

  // Truncate sat f64 to i32 with zero extend (special: produces i32x4 from f64x2)
  // SIMDTruncSatF64ToI32SZero: FCVTZS + XTN
  // Uses: [vector], Defs: [result]
  SIMDTruncSatF64ToI32SZero

  // SIMDTruncSatF64ToI32UZero: FCVTZU + XTN
  // Uses: [vector], Defs: [result]
  SIMDTruncSatF64ToI32UZero

  // Convert low i32 lanes to f64 (i32x4 -> f64x2, using low 2 lanes)
  // SIMDConvertLowI32ToF64S: SXTL + SCVTF
  // Uses: [vector], Defs: [result]
  SIMDConvertLowI32ToF64S

  // SIMDConvertLowI32ToF64U: UXTL + UCVTF
  // Uses: [vector], Defs: [result]
  SIMDConvertLowI32ToF64U

  // Demote f64 to f32 with zero (f64x2 -> f32x4, zeros in high lanes)
  // SIMDDemoteF64ToF32Zero: FCVTN
  // Uses: [vector], Defs: [result]
  SIMDDemoteF64ToF32Zero

  // Promote low f32 to f64 (f32x4 -> f64x2, using low 2 lanes)
  // SIMDPromoteLowF32ToF64: FCVTL
  // Uses: [vector], Defs: [result]
  SIMDPromoteLowF32ToF64

  // V128 load (128-bit)
  // SIMDLoad(offset): LDR Qd, [Xn, #offset]
  // Uses: [base], Defs: [result]
  SIMDLoad(Int)

  // V128 store (128-bit)
  // SIMDStore(offset): STR Qn, [Xd, #offset]
  // Uses: [base, value], Defs: []
  SIMDStore(Int)

  // Load and splat
  // SIMDLoadSplat(lane_size, offset): LD1R Vd.T, [Xn]
  // Uses: [base], Defs: [result]
  SIMDLoadSplat(LaneSize, Int)

  // Load and extend (8x8, 16x4, 32x2)
  // SIMDLoadExtend(src_bits, signed, offset): load + SXTL/UXTL
  // Uses: [base], Defs: [result]
  SIMDLoadExtend(Int, Bool, Int)

  // Load 32/64 bits and zero extend to v128
  // SIMDLoadZero(is_64, offset): LDR S/D, then insert into zero vector
  // Uses: [base], Defs: [result]
  SIMDLoadZero(Bool, Int)

  // Load lane (load single element into existing vector)
  // SIMDLoadLane(lane_size, lane, offset): LD1 Vd.T[lane], [Xn]
  // Uses: [base, vector], Defs: [result]
  SIMDLoadLane(LaneSize, Int, Int)

  // Store lane (store single element from vector)
  // SIMDStoreLane(lane_size, lane, offset): ST1 Vn.T[lane], [Xd]
  // Uses: [base, vector], Defs: []
  SIMDStoreLane(LaneSize, Int, Int)

  // ============ Relaxed SIMD Instructions ============

  // Floating-point fused multiply-add: d = a + (b * c)
  // SIMDFMla(is_f32): FMLA Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [accumulator, v1, v2], Defs: [result]
  SIMDFMla(Bool)

  // Floating-point fused multiply-subtract: d = a - (b * c)
  // SIMDFMls(is_f32): FMLS Vd.4S/2D, Vn.4S/2D, Vm.4S/2D
  // Uses: [accumulator, v1, v2], Defs: [result]
  SIMDFMls(Bool)

  // Relaxed dot product i8x16 -> i16x8 (signed/unsigned hybrid)
  // SIMDRelaxedDot8to16: sequence to compute dot product
  // Uses: [v1, v2], Defs: [result, tmp]
  SIMDRelaxedDot8to16

  // Relaxed dot product i8x16 -> i32x4 with accumulator
  // SIMDRelaxedDot8to32Add: sequence to compute dot product with add
  // Uses: [v1, v2, accumulator], Defs: [result, tmp]
  SIMDRelaxedDot8to32Add
}

///|
fn VCodeOpcode::to_string(self : VCodeOpcode) -> String {
  match self {
    Add(is_64) => if is_64 { "add" } else { "add32" }
    AddImm(imm, is_64) => if is_64 { "add #\{imm}" } else { "add32 #\{imm}" }
    Sub(is_64) => if is_64 { "sub" } else { "sub32" }
    SubImm(imm, is_64) => if is_64 { "sub #\{imm}" } else { "sub32 #\{imm}" }
    Mul(is_64) => if is_64 { "mul" } else { "mul32" }
    SDiv(is_64) => if is_64 { "sdiv" } else { "sdiv32" }
    UDiv(is_64) => if is_64 { "udiv" } else { "udiv32" }
    SRem(is_64) => if is_64 { "srem" } else { "srem32" }
    URem(is_64) => if is_64 { "urem" } else { "urem32" }
    And(is_64) => if is_64 { "and" } else { "and32" }
    AndImm(imm, is_64) => if is_64 { "and #\{imm}" } else { "and32 #\{imm}" }
    Or(is_64) => if is_64 { "or" } else { "or32" }
    OrImm(imm, is_64) => if is_64 { "or #\{imm}" } else { "or32 #\{imm}" }
    Xor(is_64) => if is_64 { "xor" } else { "xor32" }
    XorImm(imm, is_64) => if is_64 { "xor #\{imm}" } else { "xor32 #\{imm}" }
    Shl(is_64) => if is_64 { "shl" } else { "shl32" }
    ShlImm(imm, is_64) => if is_64 { "shl #\{imm}" } else { "shl32 #\{imm}" }
    AShr(is_64) => if is_64 { "ashr" } else { "ashr32" }
    AShrImm(imm, is_64) => if is_64 { "ashr #\{imm}" } else { "ashr32 #\{imm}" }
    LShr(is_64) => if is_64 { "lshr" } else { "lshr32" }
    LShrImm(imm, is_64) => if is_64 { "lshr #\{imm}" } else { "lshr32 #\{imm}" }
    Rotr(is_64) => if is_64 { "rotr" } else { "rotr32" }
    RotrImm(imm, is_64) => if is_64 { "rotr #\{imm}" } else { "rotr32 #\{imm}" }
    ExtrImm(imm, is_64) => if is_64 { "extr #\{imm}" } else { "extr32 #\{imm}" }
    Not(is_64) => if is_64 { "not" } else { "not32" }
    AndNot(is_64) => if is_64 { "andnot" } else { "andnot32" }
    OrNot(is_64) => if is_64 { "ornot" } else { "ornot32" }
    XorNot(is_64) => if is_64 { "xornot" } else { "xornot32" }
    FAdd(is_f32) => if is_f32 { "fadd.s" } else { "fadd.d" }
    FSub(is_f32) => if is_f32 { "fsub.s" } else { "fsub.d" }
    FMul(is_f32) => if is_f32 { "fmul.s" } else { "fmul.d" }
    FDiv(is_f32) => if is_f32 { "fdiv.s" } else { "fdiv.d" }
    FMin(is_f32) => if is_f32 { "fmin.s" } else { "fmin.d" }
    FMax(is_f32) => if is_f32 { "fmax.s" } else { "fmax.d" }
    FSqrt(is_f32) => if is_f32 { "fsqrt.s" } else { "fsqrt.d" }
    FAbs(is_f32) => if is_f32 { "fabs.s" } else { "fabs.d" }
    FNeg(is_f32) => if is_f32 { "fneg.s" } else { "fneg.d" }
    FCeil(is_f32) => if is_f32 { "fceil.s" } else { "fceil.d" }
    FFloor(is_f32) => if is_f32 { "ffloor.s" } else { "ffloor.d" }
    FTrunc(is_f32) => if is_f32 { "ftrunc.s" } else { "ftrunc.d" }
    FNearest(is_f32) => if is_f32 { "fnearest.s" } else { "fnearest.d" }
    Load(ty, offset) => "load.\{ty} +\{offset}"
    Store(ty, offset) => "store.\{ty} +\{offset}"
    Load8S(offset) => "load8s +\{offset}"
    Load8U(offset) => "load8u +\{offset}"
    Load16S(offset) => "load16s +\{offset}"
    Load16U(offset) => "load16u +\{offset}"
    Load32S(offset) => "load32s +\{offset}"
    Load32U(offset) => "load32u +\{offset}"
    Move => "mov"
    LoadConst(v) => "ldi \{v}"
    LoadConstF32(v) => {
      // Convert i32 bits to f32 value for display
      let f = Float::reinterpret_from_uint(v.reinterpret_as_uint())
      "ldf \{f}"
    }
    LoadConstF64(v) => {
      // Convert i64 bits to f64 value for display
      let f = v.reinterpret_as_double()
      "ldf \{f}"
    }
    Cmp(kind, is_64) => if is_64 { "cmp.\{kind}" } else { "cmp32.\{kind}" }
    IntCmp(is_64) => if is_64 { "icmp" } else { "icmp32" }
    FCmp(kind) => "fcmp.\{kind}"
    Extend(kind) => "extend.\{kind}"
    Truncate => "trunc"
    IntToFloat(kind) => "i2f.\{kind}"
    FPromote => "fpromote"
    FDemote => "fdemote"
    Bitcast => "bitcast"
    Select => "select"
    SelectCmp(kind, is_64) =>
      if is_64 {
        "select_cmp.\{kind}"
      } else {
        "select_cmp32.\{kind}"
      }
    Clz(is_64) => if is_64 { "clz" } else { "clz32" }
    Popcnt(is_64) => if is_64 { "popcnt" } else { "popcnt32" }
    Rbit(is_64) => if is_64 { "rbit" } else { "rbit32" }
    Nop => "nop"
    TrapIfUgt(trap_code) => "trap_if_ugt #\{trap_code}"
    TrapIfUge(trap_code) => "trap_if_uge #\{trap_code}"
    FpuCmp(is_f32) => if is_f32 { "fcmp.s" } else { "fcmp.d" }
    TrapIf(cond, trap_code) => "trap_if.\{cond} #\{trap_code}"
    TrapIfZero(is_64, trap_code) =>
      if is_64 {
        "trap_if_zero #\{trap_code}"
      } else {
        "trap_if_zero32 #\{trap_code}"
      }
    TrapIfDivOverflow(is_64, trap_code) =>
      if is_64 {
        "trap_if_div_overflow #\{trap_code}"
      } else {
        "trap_if_div_overflow32 #\{trap_code}"
      }
    FcvtToInt(is_f32, is_i64, is_signed) => {
      let src = if is_f32 { "f32" } else { "f64" }
      let dst = if is_i64 { "i64" } else { "i32" }
      let sign = if is_signed { "s" } else { "u" }
      "fcvt.\{src}_\{dst}_\{sign}"
    }
    FpuSel(is_f32, cond) =>
      if is_f32 {
        "fcsel.s.\{cond}"
      } else {
        "fcsel.d.\{cond}"
      }
    FpuMaxnm(is_f32) => if is_f32 { "fmaxnm.s" } else { "fmaxnm.d" }
    FpuMinnm(is_f32) => if is_f32 { "fminnm.s" } else { "fminnm.d" }
    // AArch64-specific
    AddShifted(shift, amount) => "add.\{shift} #\{amount}"
    AddExtend(ext, amount) => "add.\{ext} #\{amount}"
    SubExtend(ext, amount) => "sub.\{ext} #\{amount}"
    SubShifted(shift, amount) => "sub.\{shift} #\{amount}"
    AndShifted(shift, amount) => "and.\{shift} #\{amount}"
    OrShifted(shift, amount) => "or.\{shift} #\{amount}"
    XorShifted(shift, amount) => "xor.\{shift} #\{amount}"
    AddShifted32(shift, amount) => "add32.\{shift} #\{amount}"
    SubShifted32(shift, amount) => "sub32.\{shift} #\{amount}"
    AndShifted32(shift, amount) => "and32.\{shift} #\{amount}"
    OrShifted32(shift, amount) => "or32.\{shift} #\{amount}"
    XorShifted32(shift, amount) => "xor32.\{shift} #\{amount}"
    Madd => "madd"
    Msub => "msub"
    Mneg => "mneg"
    Madd32 => "madd32"
    Msub32 => "msub32"
    Mneg32 => "mneg32"
    Umulh => "umulh"
    Smulh => "smulh"
    Umull => "umull"
    Smull => "smull"
    ReturnCallIndirect(stack_arg_bytes, num_results) =>
      "return_call_indirect(stack=\{stack_arg_bytes}) -> \{num_results} results"
    CallExternalIfI32NeImm(expected_value, helper) =>
      "call_external_if_i32_ne_imm \{expected_value} via \{helper}"
    StackLoad(offset) => "stack_load [sp+\{offset}]"
    StackStore(offset) => "stack_store [sp+\{offset}]"
    LoadStackParam(offset, class) => "load_stack_param +\{offset} (\{class})"
    // NOTE: memory.grow/size/fill/copy and table.grow are lowered to foreign calls.
    // NOTE: TableGet, TableSet, GlobalGet, GlobalSet removed - desugared at IR level
    LoadPtr(ty, offset) => "load_ptr.\{ty} +\{offset}"
    LoadPtrRegOffset(ty, ext, shift, offset) => {
      let offset_str = if offset == 0 { "" } else { " +\{offset}" }
      "load_ptr_regoff.\{ty} (\{ext},\{shift})\{offset_str}"
    }
    LoadPtrNarrowRegOffset(bits, signed, ext, shift, offset) => {
      let sign_str = if signed { "s" } else { "u" }
      let offset_str = if offset == 0 { "" } else { " +\{offset}" }
      "load_ptr\{bits}_\{sign_str}_regoff (\{ext},\{shift})\{offset_str}"
    }
    StorePtr(ty, offset) => "store_ptr.\{ty} +\{offset}"
    StorePtrRegOffset(ty, ext, shift, offset) => {
      let offset_str = if offset == 0 { "" } else { " +\{offset}" }
      "store_ptr_regoff.\{ty} (\{ext},\{shift})\{offset_str}"
    }
    StorePtrNarrowRegOffset(bits, ext, shift, offset) => {
      let offset_str = if offset == 0 { "" } else { " +\{offset}" }
      "store_ptr\{bits}_regoff (\{ext},\{shift})\{offset_str}"
    }
    LoadPtrNarrow(bits, signed, offset) => {
      let sign_str = if signed { "s" } else { "u" }
      "load_ptr\{bits}_\{sign_str} +\{offset}"
    }
    StorePtrNarrow(bits, offset) => "store_ptr\{bits} +\{offset}"
    LoadExternalFuncAddr(symbol) => "load_external_func_addr.\{symbol}"
    LoadCodeAddr(symbol) => "load_code_addr.\{symbol}"
    CallPtr(num_args, num_results, call_conv) =>
      "call_ptr[\{call_conv}](\{num_args}) -> \{num_results} results"
    CallDirect(target, num_args, num_results, call_conv) =>
      "call_direct[\{call_conv}].\{target}(\{num_args}) -> \{num_results} results"
    CallExternal(symbol, num_args, num_results, call_conv) =>
      "call_external[\{call_conv}].\{symbol}(\{num_args}) -> \{num_results} results"
    AdjustSP(delta) =>
      if delta >= 0 {
        "add sp, sp, #\{delta}"
      } else {
        "sub sp, sp, #\{-delta}"
      }
    StoreToStack(offset) => "str [sp+\{offset}]"
    LoadSP => "mov rd, outgoing_args_base"
    GCAllocStructInline(type_idx, num_fields, _, _) =>
      "gc_alloc_struct_inline type=\{type_idx} fields=\{num_fields}"
    GCAllocStructSlowPrecise(type_idx, num_fields, _) =>
      "gc_alloc_struct_slow_precise type=\{type_idx} fields=\{num_fields}"
    GCAllocArrayFixedInline(type_idx, len, _, _) =>
      "gc_alloc_array_fixed_inline type=\{type_idx} len=\{len}"
    GCAllocArraySlowPrecise(type_idx, _) =>
      "gc_alloc_array_slow_precise type=\{type_idx}"
    // SIMD instructions
    LoadConstV128(_) => "ldi.v128"
    SIMDSplat(lane_size) => "dup.\{lane_size}"
    SIMDSplatF(is_f32) => if is_f32 { "dup.4s" } else { "dup.2d" }
    SIMDExtractU(lane_size, lane) => "umov.\{lane_size}[\{lane}]"
    SIMDExtractS(lane_size, lane) => "smov.\{lane_size}[\{lane}]"
    SIMDExtractF(is_f32, lane) =>
      if is_f32 {
        "dup.s[\{lane}]"
      } else {
        "dup.d[\{lane}]"
      }
    SIMDInsert(lane_size, lane) => "ins.\{lane_size}[\{lane}]"
    SIMDInsertF(is_f32, lane) =>
      if is_f32 {
        "ins.s[\{lane}]"
      } else {
        "ins.d[\{lane}]"
      }
    SIMDShuffle(_) => "tbl1x2.16b"
    SIMDSwizzle => "tbl.16b"
    SIMDNot => "not.16b"
    SIMDAnd => "and.16b"
    SIMDBic => "bic.16b"
    SIMDOr => "orr.16b"
    SIMDXor => "eor.16b"
    SIMDBsl => "bsl.16b"
    SIMDAnyTrue => "v128.any_true"
    SIMDAllTrue(lane_size) => "all_true.\{lane_size}"
    SIMDBitmask(lane_size) => "bitmask.\{lane_size}"
    SIMDAdd(lane_size) => "add.\{lane_size}"
    SIMDSub(lane_size) => "sub.\{lane_size}"
    SIMDMul(lane_size) => "mul.\{lane_size}"
    SIMDSqadd(lane_size) => "sqadd.\{lane_size}"
    SIMDUqadd(lane_size) => "uqadd.\{lane_size}"
    SIMDSqsub(lane_size) => "sqsub.\{lane_size}"
    SIMDUqsub(lane_size) => "uqsub.\{lane_size}"
    SIMDSmin(lane_size) => "smin.\{lane_size}"
    SIMDUmin(lane_size) => "umin.\{lane_size}"
    SIMDSmax(lane_size) => "smax.\{lane_size}"
    SIMDUmax(lane_size) => "umax.\{lane_size}"
    SIMDUrhadd(lane_size) => "urhadd.\{lane_size}"
    SIMDAbs(lane_size) => "abs.\{lane_size}"
    SIMDNeg(lane_size) => "neg.\{lane_size}"
    SIMDCnt => "cnt.16b"
    SIMDBroadcastShift(lane_size, negate) => {
      let neg = if negate { ".neg" } else { "" }
      "dup_shift\{neg}.\{lane_size}"
    }
    SIMDShiftByVec(lane_size, use_ushl) => {
      let op = if use_ushl { "ushl" } else { "sshl" }
      "\{op}.\{lane_size}"
    }
    SIMDCmp(lane_size, kind) => "cmp.\{kind}.\{lane_size}"
    SIMDNarrow(lane_size, signed) => {
      let sign = if signed { "s" } else { "u" }
      "xtn.\{sign}.\{lane_size}"
    }
    SIMDExtendLow(lane_size, signed) => {
      let sign = if signed { "s" } else { "u" }
      "xtl.\{sign}.\{lane_size}"
    }
    SIMDExtendHigh(lane_size, signed) => {
      let sign = if signed { "s" } else { "u" }
      "xtl2.\{sign}.\{lane_size}"
    }
    SIMDExtMulLow(lane_size, signed) => {
      let sign = if signed { "s" } else { "u" }
      "mull.\{sign}.\{lane_size}"
    }
    SIMDExtMulHigh(lane_size, signed) => {
      let sign = if signed { "s" } else { "u" }
      "mull2.\{sign}.\{lane_size}"
    }
    SIMDExtAddPairwise(lane_size, signed) => {
      let sign = if signed { "s" } else { "u" }
      "addlp.\{sign}.\{lane_size}"
    }
    SIMDDot => "dot.i16x8_s"
    SIMDQ15MulrSat => "sqrdmulh.8h"
    SIMDFAdd(is_f32) => if is_f32 { "fadd.4s" } else { "fadd.2d" }
    SIMDFSub(is_f32) => if is_f32 { "fsub.4s" } else { "fsub.2d" }
    SIMDFMul(is_f32) => if is_f32 { "fmul.4s" } else { "fmul.2d" }
    SIMDFDiv(is_f32) => if is_f32 { "fdiv.4s" } else { "fdiv.2d" }
    SIMDFMin(is_f32) => if is_f32 { "fmin.4s" } else { "fmin.2d" }
    SIMDFMax(is_f32) => if is_f32 { "fmax.4s" } else { "fmax.2d" }
    SIMDFPMin(is_f32) => if is_f32 { "fpmin.4s" } else { "fpmin.2d" }
    SIMDFPMax(is_f32) => if is_f32 { "fpmax.4s" } else { "fpmax.2d" }
    SIMDFAbs(is_f32) => if is_f32 { "fabs.4s" } else { "fabs.2d" }
    SIMDFNeg(is_f32) => if is_f32 { "fneg.4s" } else { "fneg.2d" }
    SIMDFSqrt(is_f32) => if is_f32 { "fsqrt.4s" } else { "fsqrt.2d" }
    SIMDFCeil(is_f32) => if is_f32 { "frintp.4s" } else { "frintp.2d" }
    SIMDFFloor(is_f32) => if is_f32 { "frintm.4s" } else { "frintm.2d" }
    SIMDFTrunc(is_f32) => if is_f32 { "frintz.4s" } else { "frintz.2d" }
    SIMDFNearest(is_f32) => if is_f32 { "frintn.4s" } else { "frintn.2d" }
    SIMDFCmp(is_f32, kind) =>
      if is_f32 {
        "fcmp.\{kind}.4s"
      } else {
        "fcmp.\{kind}.2d"
      }
    SIMDFCvtToIntS(is_f32) => if is_f32 { "fcvtzs.4s" } else { "fcvtzs.2d" }
    SIMDFCvtToIntU(is_f32) => if is_f32 { "fcvtzu.4s" } else { "fcvtzu.2d" }
    SIMDIntToFloatS(is_f32) => if is_f32 { "scvtf.4s" } else { "scvtf.2d" }
    SIMDIntToFloatU(is_f32) => if is_f32 { "ucvtf.4s" } else { "ucvtf.2d" }
    SIMDTruncSatF64ToI32SZero => "fcvtzs.f64_i32_zero"
    SIMDTruncSatF64ToI32UZero => "fcvtzu.f64_i32_zero"
    SIMDConvertLowI32ToF64S => "scvtf.i32_f64_low"
    SIMDConvertLowI32ToF64U => "ucvtf.i32_f64_low"
    SIMDDemoteF64ToF32Zero => "fcvtn.f64_f32_zero"
    SIMDPromoteLowF32ToF64 => "fcvtl.f32_f64_low"
    SIMDLoad(offset) => "ldr.q +\{offset}"
    SIMDStore(offset) => "str.q +\{offset}"
    SIMDLoadSplat(lane_size, offset) => "ld1r.\{lane_size} +\{offset}"
    SIMDLoadExtend(bits, signed, offset) => {
      let sign = if signed { "s" } else { "u" }
      "ldext.\{bits}\{sign} +\{offset}"
    }
    SIMDLoadZero(is_64, offset) =>
      if is_64 {
        "ldr.d_zero +\{offset}"
      } else {
        "ldr.s_zero +\{offset}"
      }
    SIMDLoadLane(lane_size, lane, offset) =>
      "ld1.\{lane_size}[\{lane}] +\{offset}"
    SIMDStoreLane(lane_size, lane, offset) =>
      "st1.\{lane_size}[\{lane}] +\{offset}"
    // Relaxed SIMD
    SIMDFMla(is_f32) => if is_f32 { "fmla.4s" } else { "fmla.2d" }
    SIMDFMls(is_f32) => if is_f32 { "fmls.4s" } else { "fmls.2d" }
    SIMDRelaxedDot8to16 => "relaxed_dot.8to16"
    SIMDRelaxedDot8to32Add => "relaxed_dot.8to32_add"
  }
}

///|
pub impl Show for VCodeOpcode with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Memory type for load/store
pub(all) enum MemType {
  I32
  I64
  F32
  F64
  V128 // 128-bit SIMD vector
}

///|
fn MemType::to_string(self : MemType) -> String {
  match self {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
  }
}

///|
pub impl Show for MemType with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Comparison kind for integer comparisons
pub(all) enum CmpKind {
  Eq
  Ne
  Slt
  Sle
  Sgt
  Sge
  Ult
  Ule
  Ugt
  Uge
}

///|
fn CmpKind::to_string(self : CmpKind) -> String {
  match self {
    Eq => "eq"
    Ne => "ne"
    Slt => "slt"
    Sle => "sle"
    Sgt => "sgt"
    Sge => "sge"
    Ult => "ult"
    Ule => "ule"
    Ugt => "ugt"
    Uge => "uge"
  }
}

///|
pub impl Show for CmpKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Comparison kind for float comparisons
pub(all) enum FCmpKind {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
}

///|
fn FCmpKind::to_string(self : FCmpKind) -> String {
  match self {
    Eq => "eq"
    Ne => "ne"
    Lt => "lt"
    Le => "le"
    Gt => "gt"
    Ge => "ge"
  }
}

///|
pub impl Show for FCmpKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Extend kind - how to extend a value
pub(all) enum ExtendKind {
  Signed8To32
  Signed8To64
  Signed16To32
  Signed16To64
  Signed32To64
  Unsigned8To32
  Unsigned8To64
  Unsigned16To32
  Unsigned16To64
  Unsigned32To64
}

///|
fn ExtendKind::to_string(self : ExtendKind) -> String {
  match self {
    Signed8To32 => "s8_32"
    Signed8To64 => "s8_64"
    Signed16To32 => "s16_32"
    Signed16To64 => "s16_64"
    Signed32To64 => "s32_64"
    Unsigned8To32 => "u8_32"
    Unsigned8To64 => "u8_64"
    Unsigned16To32 => "u16_32"
    Unsigned16To64 => "u16_64"
    Unsigned32To64 => "u32_64"
  }
}

///|
pub impl Show for ExtendKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Float to Int conversion kind
/// Encodes: source float type, destination int type, signedness
pub(all) enum FloatToIntKind {
  F32ToI32S // f32 -> i32 signed (FCVTZS Wd, Sn) - trapping
  F32ToI32U // f32 -> i32 unsigned (FCVTZU Wd, Sn) - trapping
  F32ToI64S // f32 -> i64 signed (FCVTZS Xd, Sn) - trapping
  F32ToI64U // f32 -> i64 unsigned (FCVTZU Xd, Sn) - trapping
  F64ToI32S // f64 -> i32 signed (FCVTZS Wd, Dn) - trapping
  F64ToI32U // f64 -> i32 unsigned (FCVTZU Wd, Dn) - trapping
  F64ToI64S // f64 -> i64 signed (FCVTZS Xd, Dn) - trapping
  F64ToI64U // f64 -> i64 unsigned (FCVTZU Xd, Dn) - trapping
  // Saturating conversions (NaN->0, overflow->max/min)
  F32ToI32SSat // f32 -> i32 signed saturating
  F32ToI32USat // f32 -> i32 unsigned saturating
  F32ToI64SSat // f32 -> i64 signed saturating
  F32ToI64USat // f32 -> i64 unsigned saturating
  F64ToI32SSat // f64 -> i32 signed saturating
  F64ToI32USat // f64 -> i32 unsigned saturating
  F64ToI64SSat // f64 -> i64 signed saturating
  F64ToI64USat // f64 -> i64 unsigned saturating
}

///|
fn FloatToIntKind::to_string(self : FloatToIntKind) -> String {
  match self {
    F32ToI32S => "f32_i32_s"
    F32ToI32U => "f32_i32_u"
    F32ToI64S => "f32_i64_s"
    F32ToI64U => "f32_i64_u"
    F64ToI32S => "f64_i32_s"
    F64ToI32U => "f64_i32_u"
    F64ToI64S => "f64_i64_s"
    F64ToI64U => "f64_i64_u"
    F32ToI32SSat => "f32_i32_s_sat"
    F32ToI32USat => "f32_i32_u_sat"
    F32ToI64SSat => "f32_i64_s_sat"
    F32ToI64USat => "f32_i64_u_sat"
    F64ToI32SSat => "f64_i32_s_sat"
    F64ToI32USat => "f64_i32_u_sat"
    F64ToI64SSat => "f64_i64_s_sat"
    F64ToI64USat => "f64_i64_u_sat"
  }
}

///|
pub impl Show for FloatToIntKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Int to Float conversion kind
/// Encodes: source int type, destination float type, signedness
pub(all) enum IntToFloatKind {
  I32SToF32 // i32 signed -> f32 (SCVTF Sd, Wn)
  I32UToF32 // i32 unsigned -> f32 (UCVTF Sd, Wn)
  I64SToF32 // i64 signed -> f32 (SCVTF Sd, Xn)
  I64UToF32 // i64 unsigned -> f32 (UCVTF Sd, Xn)
  I32SToF64 // i32 signed -> f64 (SCVTF Dd, Wn)
  I32UToF64 // i32 unsigned -> f64 (UCVTF Dd, Wn)
  I64SToF64 // i64 signed -> f64 (SCVTF Dd, Xn)
  I64UToF64 // i64 unsigned -> f64 (UCVTF Dd, Xn)
}

///|
fn IntToFloatKind::to_string(self : IntToFloatKind) -> String {
  match self {
    I32SToF32 => "i32_s_f32"
    I32UToF32 => "i32_u_f32"
    I64SToF32 => "i64_s_f32"
    I64UToF32 => "i64_u_f32"
    I32SToF64 => "i32_s_f64"
    I32UToF64 => "i32_u_f64"
    I64SToF64 => "i64_s_f64"
    I64UToF64 => "i64_u_f64"
  }
}

///|
pub impl Show for IntToFloatKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// AArch64 condition codes (for conditional branches and traps)
/// Condition codes for comparisons
pub(all) enum Cond {
  Eq // Equal (Z=1)
  Ne // Not equal (Z=0)
  Hs // Unsigned higher or same (C=1), also known as CS
  Lo // Unsigned lower (C=0), also known as CC
  Mi // Minus/negative (N=1)
  Pl // Plus/positive or zero (N=0)
  Vs // Overflow (V=1) - used for NaN check in float compare
  Vc // No overflow (V=0)
  // x86_64-only: parity flag conditions (used after UCOMIS* for NaN/unordered checks).
  Ps // Parity set (PF=1)
  Pc // Parity clear (PF=0)
  Hi // Unsigned higher (C=1 && Z=0)
  Ls // Unsigned lower or same (C=0 || Z=1)
  Ge // Signed greater or equal (N=V)
  Lt // Signed less than (N!=V)
  Gt // Signed greater than (Z=0 && N=V)
  Le // Signed less or equal (Z=1 || N!=V)
  Al // Always (unconditional)
}

///|
fn Cond::to_string(self : Cond) -> String {
  match self {
    Eq => "eq"
    Ne => "ne"
    Hs => "hs"
    Lo => "lo"
    Mi => "mi"
    Pl => "pl"
    Vs => "vs"
    Vc => "vc"
    Ps => "ps"
    Pc => "pc"
    Hi => "hi"
    Ls => "ls"
    Ge => "ge"
    Lt => "lt"
    Gt => "gt"
    Le => "le"
    Al => "al"
  }
}

///|
pub impl Show for Cond with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Get the condition code value for AArch64 encoding
pub fn Cond::to_bits(self : Cond) -> Int {
  match self {
    Eq => 0
    Ne => 1
    Hs => 2
    Lo => 3
    Mi => 4
    Pl => 5
    Vs => 6
    Vc => 7
    Ps | Pc => abort("Cond::to_bits: parity conditions are x86_64-only")
    Hi => 8
    Ls => 9
    Ge => 10
    Lt => 11
    Gt => 12
    Le => 13
    Al => 14
  }
}

///|
/// Invert condition code (for branch inversion optimization)
/// E.g., Eq -> Ne, Hs -> Lo, Ge -> Lt
pub fn Cond::invert(self : Cond) -> Cond {
  match self {
    Eq => Ne
    Ne => Eq
    Hs => Lo
    Lo => Hs
    Mi => Pl
    Pl => Mi
    Vs => Vc
    Vc => Vs
    Ps => Pc
    Pc => Ps
    Hi => Ls
    Ls => Hi
    Ge => Lt
    Lt => Ge
    Gt => Le
    Le => Gt
    Al => Al // Always is its own inverse (never used in practice)
  }
}

///|
/// VCode terminator - how a block ends
pub(all) enum VCodeTerminator {
  // Jump to target block with SSA block arguments.
  // The length of args must match the target block's params.
  Jump(Int, Array[@abi.Reg])
  Branch(@abi.Reg, Int, Int) // Conditional: condition, then-block, else-block
  // BranchCmp: compare two registers and branch on condition
  // Emits: CMP Xn, Xm + B.cond (saves one instruction vs Branch)
  // Parameters: lhs, rhs, cond, is_64, then-block, else-block
  BranchCmp(@abi.Reg, @abi.Reg, Cond, Bool, Int, Int)
  // BranchZero: branch if register is zero/nonzero
  // Emits: CBZ/CBNZ (saves two instructions vs Branch)
  // Parameters: reg, is_nonzero, is_64, then-block, else-block
  BranchZero(@abi.Reg, Bool, Bool, Int, Int)
  // BranchCmpImm: compare register with immediate and branch on condition
  // Emits: CMP Xn, #imm + B.cond (saves one instruction vs loading const to reg)
  // Parameters: lhs, imm, cond, is_64, then-block, else-block
  BranchCmpImm(@abi.Reg, Int, Cond, Bool, Int, Int)
  Return(Array[@abi.Reg]) // Return with values
  Trap(String) // Trap with message
  // BrTable: index register, target block IDs, default block ID
  // Uses jump table for O(1) dispatch instead of comparison chain
  BrTable(@abi.Reg, Array[Int], Int)
}

///|
fn VCodeTerminator::to_string(self : VCodeTerminator) -> String {
  match self {
    Jump(target, args) => {
      let mut result = "jump block\{target}"
      if args.length() > 0 {
        result = result + " ("
        for i, a in args {
          if i > 0 {
            result = result + ", "
          }
          result = result + a.to_string()
        }
        result = result + ")"
      }
      result
    }
    Branch(cond, then_b, else_b) =>
      "branch \{cond}, block\{then_b}, block\{else_b}"
    BranchCmp(lhs, rhs, cond, _is_64, then_b, else_b) =>
      "br_cmp.\{cond} \{lhs}, \{rhs}, block\{then_b}, block\{else_b}"
    BranchZero(reg, is_nonzero, _is_64, then_b, else_b) => {
      let op = if is_nonzero { "cbnz" } else { "cbz" }
      "\{op} \{reg}, block\{then_b}, block\{else_b}"
    }
    BranchCmpImm(lhs, imm, cond, _is_64, then_b, else_b) =>
      "br_cmp_imm.\{cond} \{lhs}, #\{imm}, block\{then_b}, block\{else_b}"
    Return(values) => {
      let mut result = "ret"
      if values.length() > 0 {
        result = result + " "
        for i, v in values {
          if i > 0 {
            result = result + ", "
          }
          result = result + v.to_string()
        }
      }
      result
    }
    Trap(msg) => "trap \"\{msg}\""
    BrTable(index, targets, default) => {
      let mut result = "br_table \{index}, ["
      for i, t in targets {
        if i > 0 {
          result = result + ", "
        }
        result = result + "block\{t}"
      }
      result = result + "], default block\{default}"
      result
    }
  }
}

///|
pub impl Show for VCodeTerminator with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Get the call type for this opcode
/// Design: instructions that clobber caller-saved registers
/// are classified as calls for register allocation purposes
pub fn VCodeOpcode::call_type(self : VCodeOpcode) -> CallType {
  match self {
    // Direct and indirect function calls (Standard via CallPtr)
    CallPtr(_, _, _)
    | CallDirect(_, _, _, _)
    | CallExternal(_, _, _, _)
    | GCAllocStructInline(_, _, _, _)
    | GCAllocStructSlowPrecise(_, _, _)
    | GCAllocArrayFixedInline(_, _, _, _)
    | GCAllocArraySlowPrecise(_, _) => Regular
    // Conditional helpers can call a C helper on the slow path; treat them as calls.
    CallExternalIfI32NeImm(_, _) => Regular
    // Tail calls that don't return to caller
    ReturnCallIndirect(_, _) => TailCall
    // Everything else is not a call
    _ => None
  }
}

///|
/// Shift type for shifted operand instructions
pub(all) enum ShiftType {
  Lsl // Logical shift left
  Lsr // Logical shift right
  Asr // Arithmetic shift right
}

///|
/// AArch64 addressing-mode extend for register-offset loads/stores.
///
/// Mirrors Cranelift's AMode.{RegExtended,RegScaledExtended} options:
/// - None: use X register offset (LSL option)
/// - Uxtw/Sxtw: extend Wm to X, optionally scaled by access size (S bit)
pub(all) enum IndexExtend {
  None
  Uxtw
  Sxtw
}

///|
fn IndexExtend::to_string(self : IndexExtend) -> String {
  match self {
    None => "none"
    Uxtw => "uxtw"
    Sxtw => "sxtw"
  }
}

///|
pub impl Show for IndexExtend with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn ShiftType::to_string(self : ShiftType) -> String {
  match self {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
}

///|
pub impl Show for ShiftType with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// SIMD lane size for vector operations
pub(all) enum LaneSize {
  B8 // 8-bit lanes (16 lanes in 128-bit vector)
  H16 // 16-bit lanes (8 lanes)
  S32 // 32-bit lanes (4 lanes)
  D64 // 64-bit lanes (2 lanes)
}

///|
fn LaneSize::to_string(self : LaneSize) -> String {
  match self {
    B8 => "8b"
    H16 => "8h"
    S32 => "4s"
    D64 => "2d"
  }
}

///|
pub impl Show for LaneSize with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// SIMD comparison kind for integer vector comparisons
pub(all) enum SIMDCmpKind {
  Eq // CMEQ - equal
  GtS // CMGT - signed greater than
  GeS // CMGE - signed greater than or equal
  GtU // CMHI - unsigned greater than (higher)
  GeU // CMHS - unsigned greater than or equal (higher or same)
}

///|
fn SIMDCmpKind::to_string(self : SIMDCmpKind) -> String {
  match self {
    Eq => "eq"
    GtS => "gt.s"
    GeS => "ge.s"
    GtU => "gt.u"
    GeU => "ge.u"
  }
}

///|
pub impl Show for SIMDCmpKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// SIMD floating-point comparison kind
pub(all) enum SIMDFCmpKind {
  Eq // FCMEQ - equal
  Gt // FCMGT - greater than
  Ge // FCMGE - greater than or equal
}

///|
fn SIMDFCmpKind::to_string(self : SIMDFCmpKind) -> String {
  match self {
    Eq => "eq"
    Gt => "gt"
    Ge => "ge"
  }
}

///|
pub impl Show for SIMDFCmpKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}
