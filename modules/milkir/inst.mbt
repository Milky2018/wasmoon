///|
pub(all) enum IntCC {
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
} derive(Eq, Debug, Hash)

///|
pub(all) enum FloatCC {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Eq, Debug, Hash)

///|
/// Generic MilkIR operation.
///
/// TODO(milkir): split memory flags from opcodes before adding alias metadata.
pub(all) enum Opcode {
  Iconst(Int64)
  Fconst(Double)
  Iadd
  Isub
  Imul
  Umulh
  Smulh
  Sdiv
  Udiv
  Srem
  Urem
  Band
  Bor
  Bxor
  Bnot
  Ishl
  Sshr
  Ushr
  Rotl
  Rotr
  Clz
  Ctz
  Popcnt
  Icmp(IntCC)
  IcmpEq
  Fadd
  Fsub
  Fmul
  Fdiv
  Fmin
  Fmax
  Fcmp(FloatCC)
  Fneg
  Fabs
  Fsqrt
  Fceil
  Ffloor
  Ftrunc
  Fnearest
  Ireduce
  Sextend
  Uextend
  Fpromote
  Fdemote
  FcvtToSint
  FcvtToUint
  FcvtToSintSat
  FcvtToUintSat
  SintToFcvt
  UintToFcvt
  Bitcast
  Sextend8
  Sextend16
  Sextend32
  Select
  Copy
  Load
  Store
  LoadPtr(Type)
  StorePtr(Type)
  StackAddr(StackSlot)
  Call(ExternalSymbol)
  CallIndirect(Signature)
  CallPtr(Int, Int)
  Trap(String)
  Custom(String)
} derive(Eq, Debug, Hash)

///|
pub(all) struct Inst {
  id : Int
  opcode : Opcode
  args : Array[Value]
  results : Array[Value]
  metadata : Array[Metadata]
} derive(Eq, Debug)

///|
pub fn Inst::new(
  id : Int,
  opcode : Opcode,
  args : Array[Value],
  results : Array[Value],
) -> Inst {
  { id, opcode, args, results, metadata: [] }
}

///|
pub fn Inst::add_metadata(self : Inst, metadata : Metadata) -> Unit {
  self.metadata.push(metadata)
}

///|
pub(all) enum Terminator {
  Return(Array[Value])
  Jump(Int, Array[Value])
  Branch(Value, Int, Array[Value], Int, Array[Value])
  Brz(Value, Int, Int)
  Brnz(Value, Int, Int)
  BrTable(Value, Array[Int], Int)
  TrapExit(String)
} derive(Eq, Debug)
