// Shared selected-instruction descriptors. Register constraints and encodings
// remain target-specific.

///|
#derive(Eq, Debug)
pub(all) enum RegisterWidth {
  W32
  W64
}

///|
pub extend RegisterWidth with Debug::{to_repr}

///|
pub extend RegisterWidth with Eq::{not_equal, equal}

///|
#derive(Eq, Debug)
pub(all) enum ScalarIntUnary {
  Mvn
  Clz
  Rbit
  Neg
}

///|
pub extend ScalarIntUnary with Debug::{to_repr}

///|
pub extend ScalarIntUnary with Eq::{not_equal, equal}

///|
#derive(Eq, Debug)
pub(all) enum IntegerCondition {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  Lo
  Ls
  Hi
  Hs
}

///|
pub extend IntegerCondition with Debug::{to_repr}

///|
pub extend IntegerCondition with Eq::{not_equal, equal}

///|
#derive(Eq, Debug)
pub(all) enum FloatTrapCondition {
  Unordered
  LessThan
  LessOrEqual
  GreaterOrEqual
}

///|
pub extend FloatTrapCondition with Debug::{to_repr}

///|
pub extend FloatTrapCondition with Eq::{not_equal, equal}

///|
#derive(Eq, Debug)
pub(all) enum SymbolicAddress {
  Code(@native.CodeSymbol)
  External(@native.ExternalSymbol)
  Data(@native.DataSymbol)
}

///|
pub extend SymbolicAddress with Debug::{to_repr}

///|
pub extend SymbolicAddress with Eq::{not_equal, equal}

///|
/// A function-local stack object before target frame placement.
#derive(Eq, Debug)
pub struct SizedStackObject {
  id : Int32
  size : Int32
  alignment : Int32
}

///|
pub fn SizedStackObject::new(
  id : Int32,
  size : Int32,
  alignment : Int32,
) -> SizedStackObject {
  { id, size, alignment, }
}

///|
pub fn SizedStackObject::is_valid(self : SizedStackObject) -> Bool {
  self.id >= 0 &&
  self.size > 0 &&
  self.alignment > 0 &&
  (self.alignment & (self.alignment - 1)) == 0
}

///|
pub extend SizedStackObject with Debug::{to_repr}

///|
pub extend SizedStackObject with Eq::{not_equal, equal}

///|
pub fn select_condition(
  comparison : @lowering.IntComparison,
) -> IntegerCondition {
  match comparison {
    Equal => Eq
    NotEqual => Ne
    SignedLessThan => Lt
    SignedLessOrEqual => Le
    SignedGreaterThan => Gt
    SignedGreaterOrEqual => Ge
    UnsignedLessThan => Lo
    UnsignedLessOrEqual => Ls
    UnsignedGreaterThan => Hi
    UnsignedGreaterOrEqual => Hs
  }
}

///|
pub fn select_reference_condition(
  comparison : @lowering.ReferenceComparison,
) -> IntegerCondition {
  match comparison {
    Equal => Eq
    NotEqual => Ne
  }
}
