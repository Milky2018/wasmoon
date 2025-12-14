///|
/// VCode instruction - a machine-level instruction with virtual registers
pub(all) struct VCodeInst {
  opcode : VCodeOpcode
  defs : Array[@abi.Writable] // Registers defined (written)
  uses : Array[@abi.Reg] // Registers used (read)
}

///|
pub fn VCodeInst::new(opcode : VCodeOpcode) -> VCodeInst {
  { opcode, defs: [], uses: [] }
}

///|
pub fn VCodeInst::add_def(self : VCodeInst, reg : @abi.Writable) -> Unit {
  self.defs.push(reg)
}

///|
pub fn VCodeInst::add_use(self : VCodeInst, reg : @abi.Reg) -> Unit {
  self.uses.push(reg)
}

///|
fn VCodeInst::to_string(self : VCodeInst) -> String {
  let mut result = ""
  // Print definitions (skip clobbers for CallIndirect)
  let defs_to_print = if self.opcode is CallIndirect(_, num_results) {
    // Only print result registers, not clobbers
    self.defs.iter().take(num_results).collect()
  } else {
    self.defs
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
  // Print uses (simplified for CallIndirect)
  if self.opcode is CallIndirect(_, _) {
    // For call_indirect, only print the function pointer (first use)
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
  // Integer arithmetic
  Add
  AddImm(Int) // ADD Xd, Xn, #imm (immediate add)
  Sub
  Mul
  SDiv
  UDiv
  SRem // Signed remainder (implemented as: rem = a - (a/b)*b)
  URem // Unsigned remainder
  // Bitwise operations
  And
  Or
  Xor
  Shl
  AShr // Arithmetic shift right
  LShr // Logical shift right
  Rotr // Rotate right
  Rotl // Rotate left (emulated as rotr with (64-n))
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
  Cmp(CmpKind)
  FCmp(FCmpKind)
  // Conversions
  Extend(ExtendKind)
  Truncate
  IntToFloat(IntToFloatKind)
  FloatToInt(FloatToIntKind)
  FPromote // f32 -> f64
  FDemote // f64 -> f32
  Bitcast // Reinterpret bits between int/float of same size
  // Conditional select
  // Select: Xd = cond ? Xn : Xm
  // Uses: [cond, true_val, false_val], Defs: [result]
  Select
  // Bit counting operations
  Clz // Count leading zeros
  Ctz // Count trailing zeros
  Popcnt // Population count (number of 1 bits)
  // Special
  Nop
  // Memory bounds check (for WASM linear memory safety)
  // BoundsCheck(offset, access_size): checks wasm_addr + offset + access_size <= memory_size
  // Uses: [wasm_addr], traps if out of bounds
  BoundsCheck(Int, Int)
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
  // TypeCheckIndirect: check if actual_type == expected_type, trap if not
  // Uses: [actual_type_vreg], Parameters: expected_type (immediate)
  // Emits: CMP actual, expected; B.EQ +8; BRK #2 (type mismatch trap)
  TypeCheckIndirect(Int)
  // Stack operations for spilling
  // StackLoad(offset): Load from [SP + offset] into the def register
  // StackStore(offset): Store the use register to [SP + offset]
  StackLoad(Int)
  StackStore(Int)
  // Stack parameter load (for params >= 8 that are passed on the stack)
  // LoadStackParam(param_idx, class): Load from [SP + frame_size + (param_idx - 8) * 8]
  // The actual offset is computed at emit time when frame_size is known
  LoadStackParam(Int, @abi.RegClass)
  // Memory management
  // MemoryGrow: grow memory by delta pages, returns previous size in pages or -1
  // Int = max_pages (0 = no limit)
  // Uses: [delta], Defs: [result]
  MemoryGrow(Int)
  // MemorySize: get current memory size in pages
  // Uses: [], Defs: [result]
  MemorySize
  // Table operations (for reference types)
  // TableGet(table_idx): load from indirect table at index
  // Uses: [elem_idx], Defs: [result (function pointer)]
  TableGet(Int)
  // TableSet(table_idx): store to indirect table at index
  // Uses: [elem_idx, value], Defs: []
  TableSet(Int)
}

///|
fn VCodeOpcode::to_string(self : VCodeOpcode) -> String {
  match self {
    Add => "add"
    AddImm(imm) => "add #\{imm}"
    Sub => "sub"
    Mul => "mul"
    SDiv => "sdiv"
    UDiv => "udiv"
    SRem => "srem"
    URem => "urem"
    And => "and"
    Or => "or"
    Xor => "xor"
    Shl => "shl"
    AShr => "ashr"
    LShr => "lshr"
    Rotr => "rotr"
    Rotl => "rotl"
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
    Cmp(kind) => "cmp.\{kind}"
    FCmp(kind) => "fcmp.\{kind}"
    Extend(kind) => "extend.\{kind}"
    Truncate => "trunc"
    IntToFloat(kind) => "i2f.\{kind}"
    FloatToInt(kind) => "f2i.\{kind}"
    FPromote => "fpromote"
    FDemote => "fdemote"
    Bitcast => "bitcast"
    Select => "select"
    Clz => "clz"
    Ctz => "ctz"
    Popcnt => "popcnt"
    Nop => "nop"
    BoundsCheck(offset, size) => "bounds_check +\{offset}, \{size}"
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
    TypeCheckIndirect(expected_type) => "type_check_indirect \{expected_type}"
    StackLoad(offset) => "stack_load [sp+\{offset}]"
    StackStore(offset) => "stack_store [sp+\{offset}]"
    LoadStackParam(param_idx, class) =>
      "load_stack_param \{param_idx} (\{class})"
    MemoryGrow(max_pages) =>
      if max_pages == 0 {
        "memory_grow"
      } else {
        "memory_grow max=\{max_pages}"
      }
    MemorySize => "memory_size"
    TableGet(table_idx) => "table_get \{table_idx}"
    TableSet(table_idx) => "table_set \{table_idx}"
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
  F32ToI32S // f32 -> i32 signed (FCVTZS Wd, Sn)
  F32ToI32U // f32 -> i32 unsigned (FCVTZU Wd, Sn)
  F32ToI64S // f32 -> i64 signed (FCVTZS Xd, Sn)
  F32ToI64U // f32 -> i64 unsigned (FCVTZU Xd, Sn)
  F64ToI32S // f64 -> i32 signed (FCVTZS Wd, Dn)
  F64ToI32U // f64 -> i32 unsigned (FCVTZU Wd, Dn)
  F64ToI64S // f64 -> i64 signed (FCVTZS Xd, Dn)
  F64ToI64U // f64 -> i64 unsigned (FCVTZU Xd, Dn)
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
