///|
/// A target physical register identified within one register class.
#valtype
pub(all) struct PhysicalReg {
  id : Int
  class : RegClass
} derive(Eq)

///|
pub fn PhysicalReg::new(id : Int, class : RegClass) -> PhysicalReg {
  { id, class, }
}

///|
pub impl Debug for PhysicalReg with fn to_repr(self) {
  Repr::literal("p\{self.id}:\{self.class.text()}")
}

///|
pub extend PhysicalReg with Debug::{to_repr}

///|
pub extend PhysicalReg with Eq::{not_equal, equal}
