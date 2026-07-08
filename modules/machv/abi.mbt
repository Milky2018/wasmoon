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
    Stack(size~, ..) | ReturnArea(size~, ..) => size
    Reg(_) => 0
  }
}

///|
pub fn abi_location_stack_align(location : AbiValueLocation) -> Int {
  match location {
    Stack(align~, ..) | ReturnArea(align~, ..) => align
    Reg(_) => 1
  }
}
