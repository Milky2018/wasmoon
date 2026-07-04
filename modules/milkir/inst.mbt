///|
/// Generic MilkIR operation.
///
/// TODO(milkir): split memory flags from opcodes before adding alias metadata.
pub(all) enum Opcode {
  Iadd
  Isub
  Imul
  IcmpEq
  Fadd
  Fsub
  Fmul
  Select
  Load
  Store
  StackAddr(StackSlot)
  Call(ExternalSymbol)
  CallIndirect(Signature)
  Trap(String)
} derive(Eq, Debug)

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
  TrapExit(String)
} derive(Eq, Debug)
