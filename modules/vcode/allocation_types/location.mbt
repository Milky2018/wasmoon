///|
/// A packed allocation result location within one allocation session.
///
/// Spill indices are session-local and must be translated at ownership
/// boundaries before they are exposed as product-facing stack-slot handles.
#valtype
pub(all) struct AllocationLocation {
  encoded : Int64
} derive(Eq)

///|
fn reg_class_code(class : RegClass) -> Int {
  match class {
    Int => 0
    Float => 1
    Vector => 2
    FpVector => 3
  }
}

///|
fn reg_class_from_code(code : Int) -> RegClass {
  match code {
    0 => Int
    1 => Float
    2 => Vector
    _ => FpVector
  }
}

///|
pub fn AllocationLocation::reg(reg : PhysicalReg) -> AllocationLocation {
  { encoded: (reg.id.to_int64() << 3) | reg_class_code(reg.class).to_int64(), }
}

///|
pub fn AllocationLocation::spill(index : Int) -> AllocationLocation {
  { encoded: (index.to_int64() << 3) | 4L, }
}

///|
pub fn AllocationLocation::register(self : AllocationLocation) -> PhysicalReg? {
  if self.is_spill() {
    None
  } else {
    Some(self.register_unchecked())
  }
}

///|
/// Decode a register location after `is_register` has been established.
pub fn AllocationLocation::register_unchecked(
  self : AllocationLocation,
) -> PhysicalReg {
  PhysicalReg::new(
    (self.encoded >> 3).to_int(),
    reg_class_from_code((self.encoded & 7L).to_int()),
  )
}

///|
pub fn AllocationLocation::spill_index(self : AllocationLocation) -> Int? {
  if self.is_spill() {
    Some(self.spill_index_unchecked())
  } else {
    None
  }
}

///|
/// Decode a spill location after `is_spill` has been established.
pub fn AllocationLocation::spill_index_unchecked(
  self : AllocationLocation,
) -> Int {
  (self.encoded >> 3).to_int()
}

///|
pub fn AllocationLocation::is_register(self : AllocationLocation) -> Bool {
  (self.encoded & 7L) != 4L
}

///|
pub fn AllocationLocation::is_spill(self : AllocationLocation) -> Bool {
  (self.encoded & 7L) == 4L
}

///|
pub impl Debug for AllocationLocation with fn to_repr(self) {
  match self.register() {
    Some(reg) => Repr::ctor("Reg", [(None, Repr(reg))])
    None => Repr::ctor("Spill", [(None, Repr(self.spill_index().unwrap()))])
  }
}

///|
pub extend AllocationLocation with Debug::{to_repr}

///|
pub extend AllocationLocation with Eq::{not_equal, equal}
