// E-node vocabulary: the terms an e-graph is built out of.
//
// `EOpcode` is the operation alphabet, `ENode` one applied operation over
// child classes, and `EOpcodeTag` the coarse key the opcode index buckets
// by. Nothing here knows about equivalence -- that starts in
// `union_find.mbt`.

///|
/// E-class identifier (index into the e-graph's class array)
pub(all) struct EClassId(Int) derive(Eq, Hash, Debug, Compare)

///|
/// E-node opcode for e-graph expressions
/// Standard IR opcodes for optimization
pub(all) enum EOpcode {
  // Constants
  Const(Int64) // Integer constant
  // Float constants (bits stored as UInt64, type indicated by context)
  // F32 uses lower 32 bits, F64 uses all 64 bits
  Fconst(UInt64) // Float constant (bit pattern)

  // Integer arithmetic (binary)
  Add
  Sub
  Mul
  Sdiv
  Udiv
  Srem
  Urem

  // Bitwise operations (binary)
  And
  Or
  Xor
  Shl
  Sshr
  Ushr
  Rotl // Rotate left
  Rotr // Rotate right

  // Unary arithmetic
  Neg // Integer negation (-x)
  Bnot // Bitwise NOT (~x)

  // Bit counting/manipulation (unary)
  Clz // Count leading zeros
  Ctz // Count trailing zeros
  Popcnt // Population count (count 1 bits)
  Bswap // Byte swap
  Bitrev // Bit reverse

  // Comparison (binary, returns i1)
  // IntCC: 0=eq, 1=ne, 2=slt, 3=sle, 4=sgt, 5=sge, 6=ult, 7=ule, 8=ugt, 9=uge
  Icmp(Int) // Integer compare with condition code
  Eq // Equal (shorthand for Icmp(0))
  Ne // Not equal (shorthand for Icmp(1))

  // Conditional
  Select // select(cond, a, b) = cond ? a : b
  Bmask // Boolean mask: 0 -> 0, nonzero -> -1

  // Integer min/max (binary)
  Smin // Signed minimum
  Smax // Signed maximum
  Umin // Unsigned minimum
  Umax // Unsigned maximum

  // Integer absolute value (unary)
  Iabs // Integer absolute value

  // Three-way comparison (spaceship operator, returns -1, 0, or 1)
  SpaceshipS // Signed three-way comparison: (x > y) - (x < y)
  SpaceshipU // Unsigned three-way comparison: (x > y) - (x < y)

  // Type conversions (integer) - with bit width info for type-aware optimizations
  // (from_bits, to_bits): e.g., Ireduce(64, 32) means i64 -> i32
  Ireduce(Int, Int) // Integer reduce (truncate to smaller type)
  Uextend(Int, Int) // Unsigned extend to larger type
  Sextend(Int, Int) // Signed extend to larger type

  // Floating point arithmetic (binary)
  Fadd // Float add
  Fsub // Float subtract
  Fmul // Float multiply
  Fdiv // Float divide
  Fmin // Float minimum
  Fmax // Float maximum
  Fcopysign // Copy sign from second operand to first

  // Floating point unary
  Fneg // Float negate
  Fabs // Float absolute value
  Fsqrt // Float square root
  Fceil // Float ceiling
  Ffloor // Float floor
  Ftrunc // Float truncate toward zero
  Fnearest // Float round to nearest

  // Floating point comparison
  // FloatCC: 0=ord, 1=uno, 2=eq, 3=ne, 4=lt, 5=le, 6=gt, 7=ge
  Fcmp(Int) // Float compare with condition code

  // Float-integer conversions
  Fpromote // Promote f32 to f64
  Fdemote // Demote f64 to f32
  FcvtToSint // Float to signed int
  FcvtToUint // Float to unsigned int
  SintToFcvt // Signed int to float
  UintToFcvt // Unsigned int to float

  // Vector operations
  Splat // Broadcast scalar to vector
  Vconst(Bytes) // Vector constant (128-bit)

  // Variable reference (leaf node representing an IR value)
  Var(Int) // IR Value id
} derive(Eq, Hash, Debug, Compare)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for EClassId with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub impl Show for EOpcode with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
/// E-opcode tag for indexing (ignores parameters like Const value)
enum EOpcodeTag {
  TConst
  TFconst
  // Arithmetic
  TAdd
  TSub
  TMul
  TSdiv
  TUdiv
  TSrem
  TUrem
  // Bitwise
  TAnd
  TOr
  TXor
  TShl
  TSshr
  TUshr
  TRotl
  TRotr
  // Unary
  TNeg
  TBnot
  // Bit manipulation
  TClz
  TCtz
  TPopcnt
  TBswap
  TBitrev
  // Comparison
  TIcmp
  TEq
  TNe
  // Conditional
  TSelect
  TBmask
  // Integer min/max
  TSmin
  TSmax
  TUmin
  TUmax
  // Integer absolute value
  TIabs
  // Three-way comparison
  TSpaceshipS
  TSpaceshipU
  // Type conversion (integer)
  TIreduce
  TUextend
  TSextend
  // Float arithmetic
  TFadd
  TFsub
  TFmul
  TFdiv
  TFmin
  TFmax
  TFcopysign
  // Float unary
  TFneg
  TFabs
  TFsqrt
  TFceil
  TFfloor
  TFtrunc
  TFnearest
  // Float comparison
  TFcmp
  // Float-integer conversion
  TFpromote
  TFdemote
  TFcvtToSint
  TFcvtToUint
  TSintToFcvt
  TUintToFcvt
  // Vector
  TSplat
  TVconst
  // Variable
  TVar
} derive(Eq, Hash, Debug)

///|
/// Get the tag of an opcode (for indexing)
pub fn EOpcode::tag(self : EOpcode) -> EOpcodeTag {
  match self {
    Const(_) => TConst
    Fconst(_) => TFconst
    // Arithmetic
    Add => TAdd
    Sub => TSub
    Mul => TMul
    Sdiv => TSdiv
    Udiv => TUdiv
    Srem => TSrem
    Urem => TUrem
    // Bitwise
    And => TAnd
    Or => TOr
    Xor => TXor
    Shl => TShl
    Sshr => TSshr
    Ushr => TUshr
    Rotl => TRotl
    Rotr => TRotr
    // Unary
    Neg => TNeg
    Bnot => TBnot
    // Bit manipulation
    Clz => TClz
    Ctz => TCtz
    Popcnt => TPopcnt
    Bswap => TBswap
    Bitrev => TBitrev
    // Comparison
    Icmp(_) => TIcmp
    Eq => TEq
    Ne => TNe
    // Conditional
    Select => TSelect
    Bmask => TBmask
    // Integer min/max
    Smin => TSmin
    Smax => TSmax
    Umin => TUmin
    Umax => TUmax
    // Integer absolute value
    Iabs => TIabs
    // Three-way comparison
    SpaceshipS => TSpaceshipS
    SpaceshipU => TSpaceshipU
    // Type conversion (integer) - ignore bit width parameters for tagging
    Ireduce(_, _) => TIreduce
    Uextend(_, _) => TUextend
    Sextend(_, _) => TSextend
    // Float arithmetic
    Fadd => TFadd
    Fsub => TFsub
    Fmul => TFmul
    Fdiv => TFdiv
    Fmin => TFmin
    Fmax => TFmax
    Fcopysign => TFcopysign
    // Float unary
    Fneg => TFneg
    Fabs => TFabs
    Fsqrt => TFsqrt
    Fceil => TFceil
    Ffloor => TFfloor
    Ftrunc => TFtrunc
    Fnearest => TFnearest
    // Float comparison
    Fcmp(_) => TFcmp
    // Float-integer conversion
    Fpromote => TFpromote
    Fdemote => TFdemote
    FcvtToSint => TFcvtToSint
    FcvtToUint => TFcvtToUint
    SintToFcvt => TSintToFcvt
    UintToFcvt => TUintToFcvt
    // Vector
    Splat => TSplat
    Vconst(_) => TVconst
    // Variable
    Var(_) => TVar
  }
}

///|
/// E-node: an expression node in the e-graph
/// Children are EClassIds, not direct node references
pub(all) struct ENode {
  op : EOpcode
  children : Array[EClassId]
} derive(Eq, Hash, Debug, Compare)
