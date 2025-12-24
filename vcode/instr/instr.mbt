///|
/// Call type - classifies instructions that behave like calls
/// Following Cranelift's CallType enum
pub(all) enum CallType {
  None // Not a call instruction
  Regular // Regular call that returns to caller
  TailCall // Tail call that doesn't return to caller
}

///|
/// VCode instruction - a machine-level instruction with virtual registers
/// Following Cranelift's design with operand constraints for fixed register allocation
pub(all) struct VCodeInst {
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
  self.def_constraints.push(@abi.Any)
}

///|
pub fn VCodeInst::add_use(self : VCodeInst, reg : @abi.Reg) -> Unit {
  self.uses.push(reg)
  self.use_constraints.push(@abi.Any)
}

///|
/// Add a use operand with a fixed register constraint
pub fn VCodeInst::add_use_fixed(
  self : VCodeInst,
  reg : @abi.Reg,
  preg : @abi.PReg,
) -> Unit {
  self.uses.push(reg)
  self.use_constraints.push(@abi.FixedReg(preg))
}

///|
/// Add a def operand with a fixed register constraint
pub fn VCodeInst::add_def_fixed(
  self : VCodeInst,
  reg : @abi.Writable,
  preg : @abi.PReg,
) -> Unit {
  self.defs.push(reg)
  self.def_constraints.push(@abi.FixedReg(preg))
}

///|
fn VCodeInst::to_string(self : VCodeInst) -> String {
  let mut result = ""
  // Print definitions (skip clobbers for CallIndirect and ReturnCallIndirect)
  let defs_to_print = match self.opcode {
    CallIndirect(_, num_results) | ReturnCallIndirect(_, num_results) =>
      // Only print result registers, not clobbers
      self.defs.iter().take(num_results).collect()
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
  // Print uses (simplified for CallIndirect and ReturnCallIndirect)
  if self.opcode is CallIndirect(_, _) ||
    self.opcode is ReturnCallIndirect(_, _) {
    // For call_indirect/return_call_indirect, only print the function pointer (first use)
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
pub impl Show for VCodeInst with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// VCode opcode - machine-level operation (target-independent subset)
pub(all) enum VCodeOpcode {
  // Integer arithmetic (Bool = true for 64-bit, false for 32-bit)
  Add(Bool) // ADD with size: true = 64-bit, false = 32-bit
  AddImm(Int, Bool) // ADD Xd, Xn, #imm with size: true = 64-bit, false = 32-bit
  Sub(Bool) // SUB with size: true = 64-bit, false = 32-bit
  Mul(Bool) // MUL with size: true = 64-bit, false = 32-bit
  SDiv(Bool) // SDIV with size: true = 64-bit, false = 32-bit
  UDiv(Bool) // UDIV with size: true = 64-bit, false = 32-bit
  // Bitwise operations (Bool = true for 64-bit, false for 32-bit)
  And
  Or
  Xor
  Shl(Bool) // LSL with size
  AShr(Bool) // Arithmetic shift right with size
  LShr(Bool) // Logical shift right with size
  Rotr(Bool) // Rotate right with size
  Not // Bitwise NOT
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
  SubShifted(ShiftType, Int) // SUB Xd, Xn, Xm, shift #amount
  AndShifted(ShiftType, Int) // AND Xd, Xn, Xm, shift #amount
  OrShifted(ShiftType, Int) // ORR Xd, Xn, Xm, shift #amount
  XorShifted(ShiftType, Int) // EOR Xd, Xn, Xm, shift #amount
  // AArch64-specific: multiply-accumulate instructions
  Madd // Xd = Xa + Xn * Xm (3 uses: acc, src1, src2)
  Msub // Xd = Xa - Xn * Xm (3 uses: acc, src1, src2)
  Mneg // Xd = -(Xn * Xm) (2 uses: src1, src2)
  // Function calls
  // CallIndirect: call through a function pointer in a register
  // Uses: [func_ptr, arg0, arg1, ...]
  // Defs: [result0, result1, ...] (multiple results supported)
  // Parameters: num_args, num_results
  CallIndirect(Int, Int)
  // ReturnCallIndirect: tail call through a function pointer
  // Uses: [func_ptr, arg0, arg1, ...]
  // Parameters: num_args, num_results
  // This is a terminator - it does not return to the caller
  ReturnCallIndirect(Int, Int)
  // TypeCheckIndirect: check if actual_type == expected_type, trap if not
  // Uses: [actual_type_vreg], Parameters: expected_type (immediate)
  // Emits: CMP actual, expected; B.EQ +8; BRK #2 (type mismatch trap)
  TypeCheckIndirect(Int)
  // Stack operations for spilling
  // StackLoad(offset): Load from [SP + offset] into the def register
  // StackStore(offset): Store the use register to [SP + offset]
  StackLoad(Int)
  StackStore(Int)
  // Stack parameter load (for params that overflow registers)
  // LoadStackParam(param_idx, class, int_overflow_count):
  //   param_idx >= 0: int overflow param at index param_idx
  //   param_idx < 0: float overflow param at index (-param_idx - 1), after int_overflow_count int params
  // Stack layout: [int_overflow..., float_overflow...]
  LoadStackParam(Int, @abi.RegClass, Int)
  // Memory management
  // MemoryGrow: grow memory by delta pages, returns previous size in pages or -1
  // Int = max_pages (0 = no limit)
  // Uses: [delta], Defs: [result]
  MemoryGrow(Int)
  // MemorySize: get current memory size in pages
  // Uses: [], Defs: [result]
  MemorySize
  // MemoryFill: fill memory region with a byte value
  // Uses: [dst, val, size], Defs: []
  MemoryFill
  // MemoryCopy: copy memory region (handles overlapping regions)
  // Uses: [dst, src, size], Defs: []
  MemoryCopy
  // Table operations (for reference types)
  // TableGet(table_idx): load from indirect table at index
  // Uses: [elem_idx], Defs: [result (function pointer)]
  TableGet(Int)
  // TableSet(table_idx): store to indirect table at index
  // Uses: [elem_idx, value], Defs: []
  TableSet(Int)
  // TableGrow(table_idx): grow table, returns previous size or -1
  // Uses: [delta, init_value], Defs: [result]
  TableGrow(Int)
  // Global operations
  // GlobalGet(global_idx): load global variable value
  // Uses: [], Defs: [result]
  GlobalGet(Int)
  // GlobalSet(global_idx): store global variable value
  // Uses: [value], Defs: []
  GlobalSet(Int)

  // GC operations (use runtime libcalls)
  // GCRefTest(type_idx, nullable): test if reference matches type
  // Uses: [ref], Defs: [result (0 or 1)]
  GCRefTest(Int, Bool)
  // GCRefCast(type_idx, nullable): cast reference to type (traps on failure)
  // Uses: [ref], Defs: [result]
  GCRefCast(Int, Bool)
  // GCStructNew(type_idx, num_fields): allocate struct
  // Uses: [field0, field1, ...], Defs: [result]
  GCStructNew(Int, Int)
  // GCStructGet(type_idx, field_idx): get struct field
  // Uses: [ref], Defs: [result]
  GCStructGet(Int, Int)
  // GCStructSet(type_idx, field_idx): set struct field
  // Uses: [ref, value], Defs: []
  GCStructSet(Int, Int)
  // GCArrayNew(type_idx): allocate array
  // Uses: [init_value, length], Defs: [result]
  GCArrayNew(Int)
  // GCArrayGet(type_idx): get array element
  // Uses: [ref, idx], Defs: [result]
  GCArrayGet(Int)
  // GCArraySet(type_idx): set array element
  // Uses: [ref, idx, value], Defs: []
  GCArraySet(Int)
  // GCArrayLen: get array length
  // Uses: [ref], Defs: [result]
  GCArrayLen

  // Raw pointer operations (for trampolines, no bounds checking)
  // LoadPtr(type, offset): Load from [base + offset]
  // Uses: [base], Defs: [result]
  LoadPtr(MemType, Int)
  // StorePtr(type, offset): Store to [base + offset]
  // Uses: [base, value], Defs: []
  StorePtr(MemType, Int)

  // CallPtr: call through a function pointer (for trampolines)
  // Uses: [func_ptr, vmctx, arg0, arg1, ...]
  // Defs: [result0, result1, ...] (multiple results supported)
  // Parameters: num_args (excluding vmctx), num_results
  CallPtr(Int, Int)

  // Stack pointer adjustment for outgoing call arguments (Cranelift-style)
  // AdjustSP(delta): Adjust SP by delta bytes
  //   delta > 0: deallocate (add to SP)
  //   delta < 0: allocate (sub from SP)
  // Used in call lowering to allocate space for overflow args
  AdjustSP(Int)

  // Store to outgoing call argument area (Cranelift-style)
  // StoreToStack(offset): Store use[0] to [SP + offset]
  // Used in call lowering to store overflow args before the call
  // Uses: [value], Defs: []
  StoreToStack(Int)
}

///|
fn VCodeOpcode::to_string(self : VCodeOpcode) -> String {
  match self {
    Add(is_64) => if is_64 { "add" } else { "add32" }
    AddImm(imm, is_64) => if is_64 { "add #\{imm}" } else { "add32 #\{imm}" }
    Sub(is_64) => if is_64 { "sub" } else { "sub32" }
    Mul(is_64) => if is_64 { "mul" } else { "mul32" }
    SDiv(is_64) => if is_64 { "sdiv" } else { "sdiv32" }
    UDiv(is_64) => if is_64 { "udiv" } else { "udiv32" }
    And => "and"
    Or => "or"
    Xor => "xor"
    Shl(is_64) => if is_64 { "shl" } else { "shl32" }
    AShr(is_64) => if is_64 { "ashr" } else { "ashr32" }
    LShr(is_64) => if is_64 { "lshr" } else { "lshr32" }
    Rotr(is_64) => if is_64 { "rotr" } else { "rotr32" }
    Not => "not"
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
    FCmp(kind) => "fcmp.\{kind}"
    Extend(kind) => "extend.\{kind}"
    Truncate => "trunc"
    IntToFloat(kind) => "i2f.\{kind}"
    FPromote => "fpromote"
    FDemote => "fdemote"
    Bitcast => "bitcast"
    Select => "select"
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
    SubShifted(shift, amount) => "sub.\{shift} #\{amount}"
    AndShifted(shift, amount) => "and.\{shift} #\{amount}"
    OrShifted(shift, amount) => "or.\{shift} #\{amount}"
    XorShifted(shift, amount) => "xor.\{shift} #\{amount}"
    Madd => "madd"
    Msub => "msub"
    Mneg => "mneg"
    CallIndirect(num_args, num_results) =>
      "call_indirect(\{num_args}) -> \{num_results} results"
    ReturnCallIndirect(num_args, num_results) =>
      "return_call_indirect(\{num_args}) -> \{num_results} results"
    TypeCheckIndirect(expected_type) => "type_check_indirect \{expected_type}"
    StackLoad(offset) => "stack_load [sp+\{offset}]"
    StackStore(offset) => "stack_store [sp+\{offset}]"
    LoadStackParam(param_idx, class, _) =>
      "load_stack_param \{param_idx} (\{class})"
    MemoryGrow(max_pages) =>
      if max_pages == 0 {
        "memory_grow"
      } else {
        "memory_grow max=\{max_pages}"
      }
    MemorySize => "memory_size"
    MemoryFill => "memory_fill"
    MemoryCopy => "memory_copy"
    TableGet(table_idx) => "table_get \{table_idx}"
    TableSet(table_idx) => "table_set \{table_idx}"
    TableGrow(table_idx) => "table_grow \{table_idx}"
    GlobalGet(global_idx) => "global_get \{global_idx}"
    GlobalSet(global_idx) => "global_set \{global_idx}"
    GCRefTest(type_idx, nullable) =>
      "gc_ref_test \{type_idx} nullable=\{nullable}"
    GCRefCast(type_idx, nullable) =>
      "gc_ref_cast \{type_idx} nullable=\{nullable}"
    GCStructNew(type_idx, num_fields) =>
      "gc_struct_new \{type_idx} fields=\{num_fields}"
    GCStructGet(type_idx, field_idx) => "gc_struct_get \{type_idx}.\{field_idx}"
    GCStructSet(type_idx, field_idx) => "gc_struct_set \{type_idx}.\{field_idx}"
    GCArrayNew(type_idx) => "gc_array_new \{type_idx}"
    GCArrayGet(type_idx) => "gc_array_get \{type_idx}"
    GCArraySet(type_idx) => "gc_array_set \{type_idx}"
    GCArrayLen => "gc_array_len"
    LoadPtr(ty, offset) => "load_ptr.\{ty} +\{offset}"
    StorePtr(ty, offset) => "store_ptr.\{ty} +\{offset}"
    CallPtr(num_args, num_results) =>
      "call_ptr(\{num_args}) -> \{num_results} results"
    AdjustSP(delta) =>
      if delta >= 0 {
        "add sp, sp, #\{delta}"
      } else {
        "sub sp, sp, #\{-delta}"
      }
    StoreToStack(offset) => "str [sp+\{offset}]"
  }
}

///|
pub impl Show for VCodeOpcode with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Memory type for load/store
pub(all) enum MemType {
  I8
  I16
  I32
  I64
  F32
  F64
}

///|
fn MemType::to_string(self : MemType) -> String {
  match self {
    I8 => "i8"
    I16 => "i16"
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
  }
}

///|
pub impl Show for MemType with output(self, logger) {
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
pub impl Show for CmpKind with output(self, logger) {
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
pub impl Show for FCmpKind with output(self, logger) {
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
pub impl Show for ExtendKind with output(self, logger) {
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
pub impl Show for FloatToIntKind with output(self, logger) {
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
pub impl Show for IntToFloatKind with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// AArch64 condition codes (for conditional branches and traps)
/// Following Cranelift's Cond enum
pub(all) enum Cond {
  Eq // Equal (Z=1)
  Ne // Not equal (Z=0)
  Hs // Unsigned higher or same (C=1), also known as CS
  Lo // Unsigned lower (C=0), also known as CC
  Mi // Minus/negative (N=1)
  Pl // Plus/positive or zero (N=0)
  Vs // Overflow (V=1) - used for NaN check in float compare
  Vc // No overflow (V=0)
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
pub impl Show for Cond with output(self, logger) {
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
/// VCode terminator - how a block ends
pub(all) enum VCodeTerminator {
  Jump(Int) // Unconditional jump to block
  Branch(@abi.Reg, Int, Int) // Conditional: condition, then-block, else-block
  Return(Array[@abi.Reg]) // Return with values
  Trap(String) // Trap with message
  // BrTable: index register, target block IDs, default block ID
  // Uses jump table for O(1) dispatch instead of comparison chain
  BrTable(@abi.Reg, Array[Int], Int)
}

///|
fn VCodeTerminator::to_string(self : VCodeTerminator) -> String {
  match self {
    Jump(target) => "jump block\{target}"
    Branch(cond, then_b, else_b) =>
      "branch \{cond}, block\{then_b}, block\{else_b}"
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
pub impl Show for VCodeTerminator with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Get the call type for this opcode
/// Following Cranelift's design: instructions that clobber caller-saved registers
/// are classified as calls for register allocation purposes
pub fn VCodeOpcode::call_type(self : VCodeOpcode) -> CallType {
  match self {
    // Direct and indirect function calls
    CallIndirect(_, _) | CallPtr(_, _) => Regular
    // Tail calls that don't return to caller
    ReturnCallIndirect(_, _) => TailCall
    // Memory operations that call C runtime functions
    MemoryGrow(_) | MemorySize | MemoryFill | MemoryCopy => Regular
    // Table operations that call C runtime functions
    TableGrow(_) => Regular
    // GC operations that call C runtime functions
    GCRefTest(_, _)
    | GCRefCast(_, _)
    | GCStructNew(_, _)
    | GCStructGet(_, _)
    | GCStructSet(_, _)
    | GCArrayNew(_)
    | GCArrayGet(_)
    | GCArraySet(_)
    | GCArrayLen => Regular
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
fn ShiftType::to_string(self : ShiftType) -> String {
  match self {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
}

///|
pub impl Show for ShiftType with output(self, logger) {
  logger.write_string(self.to_string())
}
