///|
pub(all) struct StackSlot {
  id : Int
  size : Int
  align : Int
} derive(Eq, Debug)

///|
pub(all) enum StackEffect {
  None
  Adjust(Int)
  CallFrame(Int)
} derive(Eq, Debug)
