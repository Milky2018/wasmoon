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
} derive(Eq, Debug, Hash)

///|
pub impl Show for Type with fn output(self, logger) {
  logger.write_string(
    match self {
      I32 => "i32"
      I64 => "i64"
      F32 => "f32"
      F64 => "f64"
      V128 => "v128"
      Ptr => "ptr"
      Ref => "ref"
    },
  )
}

///|
pub(all) struct Value {
  id : Int
  ty : Type
} derive(Eq, Debug, Hash)

///|
pub(all) struct Signature {
  params : Array[Type]
  results : Array[Type]
} derive(Eq, Debug, Hash)

///|
pub fn Signature::new(params : Array[Type], results : Array[Type]) -> Signature {
  { params, results }
}

///|
pub(all) struct ExternalSymbol {
  name : String
} derive(Eq, Debug, Hash)

///|
pub fn ExternalSymbol::new(name : String) -> ExternalSymbol {
  { name, }
}

///|
pub(all) struct StackSlot {
  id : Int
  size : Int
  align : Int
} derive(Eq, Debug, Hash)

///|
pub(all) enum Metadata {
  SourceLoc(String)
  Comment(String)
} derive(Eq, Debug)
