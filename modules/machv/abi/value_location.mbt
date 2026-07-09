///|
pub(all) enum AbiValueLocation {
  Reg(PReg)
  Stack(offset~ : Int, size~ : Int, align~ : Int)
  ReturnArea(offset~ : Int, size~ : Int, align~ : Int)
} derive(Eq, Debug)

///|
pub(all) struct AbiReturnArea {
  size : Int
  align : Int
} derive(Eq, Debug)

///|
pub fn abi_location_stack_size(location : AbiValueLocation) -> Int {
  match location {
    Reg(_) => 0
    Stack(size~, ..) | ReturnArea(size~, ..) => size
  }
}

///|
pub fn abi_location_stack_align(location : AbiValueLocation) -> Int {
  match location {
    Reg(_) => 1
    Stack(align~, ..) | ReturnArea(align~, ..) => align
  }
}
