///|
pub(all) enum AtomicRmwOp {
  Add
  Sub
  And
  Or
  Xor
  Exchange
}

///|
pub(all) enum AtomicOperation {
  Notify
  Wait
  Fence
  Load
  Store
  Rmw(AtomicRmwOp)
  CompareExchange
}

///|
/// Shared binary and text description of one standard atomic opcode.
pub struct AtomicOpcode {
  operation : AtomicOperation
  value_type : ValueType
  width : Int32
  natural_alignment : Int32
  name : String
}

///|
fn make_atomic_opcode(code : Int32) -> AtomicOpcode? {
  if code < 4 {
    let (operation, value_type, width, natural_alignment, name) : (
      AtomicOperation,
      ValueType,
      Int32,
      Int32,
      String,
    ) = match code {
      0 => (Notify, I32, 4, 2, "memory.atomic.notify")
      1 => (Wait, I32, 4, 2, "memory.atomic.wait32")
      2 => (Wait, I64, 8, 3, "memory.atomic.wait64")
      _ => (Fence, I32, 0, 0, "atomic.fence")
    }
    return Some({ operation, value_type, width, natural_alignment, name, })
  }
  if code < 0x10 || code > 0x4E {
    return None
  }
  let relative = code - 0x10
  let (value_type, width, natural_alignment) : (ValueType, Int32, Int32) = match
    relative % 7 {
    0 => (I32, 4, 2)
    1 => (I64, 8, 3)
    2 => (I32, 1, 0)
    3 => (I32, 2, 1)
    4 => (I64, 1, 0)
    5 => (I64, 2, 1)
    _ => (I64, 4, 2)
  }
  let (operation, suffix) : (AtomicOperation, String) = match relative / 7 {
    0 => (Load, "load")
    1 => (Store, "store")
    2 => (Rmw(Add), "add")
    3 => (Rmw(Sub), "sub")
    4 => (Rmw(And), "and")
    5 => (Rmw(Or), "or")
    6 => (Rmw(Xor), "xor")
    7 => (Rmw(Exchange), "xchg")
    _ => (CompareExchange, "cmpxchg")
  }
  let prefix = if value_type == I32 { "i32.atomic." } else { "i64.atomic." }
  let narrow = width < (if value_type == I32 { 4 } else { 8 })
  let width_name = if narrow { (width * 8).to_string() } else { "" }
  let name = match operation {
    Load => prefix + suffix + width_name + (if narrow { "_u" } else { "" })
    Store => prefix + suffix + width_name
    _ =>
      prefix +
      "rmw" +
      width_name +
      "." +
      suffix +
      (if narrow { "_u" } else { "" })
  }
  Some({ operation, value_type, width, natural_alignment, name, })
}

///|
let atomic_opcodes : ReadOnlyArray[AtomicOpcode?] = ReadOnlyArray::from_array(
  Array::makei(0x4F, make_atomic_opcode),
)

///|
let atomic_subopcodes : Map[String, Int32] = {
  let by_name : Map[String, Int32] = Map([])
  for code, opcode in atomic_opcodes {
    if opcode is Some(info) {
      by_name[info.name] = code
    }
  }
  by_name
}

///|
pub fn atomic_opcode(code : Int32) -> AtomicOpcode? {
  if code >= 0 && code < atomic_opcodes.length() {
    atomic_opcodes[code]
  } else {
    None
  }
}

///|
pub fn atomic_subopcode(name : String) -> Int32? {
  atomic_subopcodes.get(name)
}

///|
/// Keep the diagnostic family independent of narrow access spelling.
pub fn AtomicOpcode::validation_name(self : AtomicOpcode) -> String {
  match self.operation {
    Notify | Wait | Fence => self.name
    Load =>
      if self.value_type == I32 {
        "i32.atomic.load"
      } else {
        "i64.atomic.load"
      }
    Store =>
      if self.value_type == I32 {
        "i32.atomic.store"
      } else {
        "i64.atomic.store"
      }
    Rmw(_) =>
      if self.value_type == I32 {
        "i32.atomic.rmw"
      } else {
        "i64.atomic.rmw"
      }
    CompareExchange =>
      if self.value_type == I32 {
        "i32.atomic.rmw.cmpxchg"
      } else {
        "i64.atomic.rmw.cmpxchg"
      }
  }
}
