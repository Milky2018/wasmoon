///|
/// MilkIR value types.
///
/// TODO(milkir): add lane-aware vector types and target pointer-width modeling.
pub(all) enum Type {
  I32
  I64
  F32
  F64
  V128
  Ptr
  Ref
} derive(Eq, Debug)

///|
pub(all) struct Value {
  id : Int
  ty : Type
} derive(Eq, Debug)

///|
pub(all) struct Signature {
  params : Array[Type]
  results : Array[Type]
} derive(Eq, Debug)

///|
pub fn Signature::new(params : Array[Type], results : Array[Type]) -> Signature {
  { params, results }
}

///|
pub(all) struct ExternalSymbol {
  name : String
} derive(Eq, Debug)

///|
pub fn ExternalSymbol::new(name : String) -> ExternalSymbol {
  { name, }
}

///|
pub(all) struct StackSlot {
  id : Int
  size : Int
  align : Int
} derive(Eq, Debug)

///|
pub(all) enum Metadata {
  SourceLoc(String)
  Comment(String)
} derive(Eq, Debug)
