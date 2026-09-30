///|
/// Resource counts defining an instance's native storage. Legacy contexts allow
/// resources to be configured after allocation and retain the fixed public ABI.
pub(all) enum ContextShape {
  Legacy
  Module(Int, Int, Int)
} derive(Eq, Debug)

///|
pub fn ContextShape::from_module(module_ : @types.Module) -> ContextShape {
  let mut memories = module_.memories.length()
  let mut tables = module_.tables.length()
  let mut globals = module_.globals.length()
  for entry in module_.imports {
    match entry.desc {
      Memory(_) => memories += 1
      Table(_) => tables += 1
      Global(_) => globals += 1
      _ => ()
    }
  }
  Module(memories, tables, globals)
}

///|
/// Includes the trailing pointer arrays, with checked arithmetic before native
/// allocation. The descriptor itself is shared immutable module metadata.
pub fn ContextShape::descriptor(self : ContextShape) -> ReadOnlyArray[Int]? {
  guard self is Module(memories, tables, globals) else { return None }
  // Bound byte offsets to signed 32-bit displacement/allocation arithmetic.
  if memories < 0 ||
    tables < 0 ||
    globals < 0 ||
    memories.to_int64() * 8L + tables.to_int64() * 24L + 128L > 2147483647L {
    return None
  }
  let offsets = FixedArray::make(30, -1)
  let mut next = 0
  // Pointer-width fields first; pack scalar counts together at the end.
  for index in [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 15, 16, 17, 8, 9, 13, 14] {
    let present = match index {
      0 | 1 | 2 | 12 | 13 => memories > 0
      4 | 5 | 7 | 8 | 10 | 11 => tables > 0
      6 => globals > 0
      _ => true
    }
    if present {
      offsets[index] = next
      next += if index == 8 || index == 9 || index == 13 || index == 14 {
        4
      } else {
        8
      }
    }
  }
  next = (next + 7) / 8 * 8
  offsets[18] = 8
  offsets[19] = 8
  offsets[20] = 0
  offsets[21] = 16
  offsets[22] = 8
  offsets[24] = next
  next += memories * 8
  offsets[25] = next
  next += tables * 8
  offsets[26] = next
  next += tables * 8
  offsets[27] = next
  next += tables * 8
  offsets[23] = next
  offsets[28] = memories
  offsets[29] = tables
  Some(ReadOnlyArray::from_array(offsets[:]))
}

///|
pub extend ContextShape with Eq::{equal, not_equal}

///|
pub extend ContextShape with Debug::{to_repr}

///|
/// Immutable layout retained by a loaded module and shared by its instances.
pub struct ContextLayout {
  priv fields : Bytes
}

///|
pub fn ContextLayout::new(shape : ContextShape) -> ContextLayout? {
  guard shape.descriptor() is Some(words) else { return None }
  let fields = Bytes::makei(48, i => {
    if i < 18 {
      (if words[i] < 0 { 255 } else { words[i] }).to_byte()
    } else if i < 20 {
      0
    } else {
      (words[i / 4 + 18] >> (i % 4 * 8)).to_byte()
    }
  })
  Some({ fields, })
}

///|
pub fn ContextLayout::field(self : ContextLayout, index : Int) -> Int {
  if index < 18 {
    let offset = self.fields[index].to_int()
    if offset == 255 {
      -1
    } else {
      offset
    }
  } else if index < 23 {
    match index {
      20 => 0
      21 => 16
      _ => 8
    }
  } else {
    let start = (index - 18) * 4
    self.fields[start].to_int() |
    (self.fields[start + 1].to_int() << 8) |
    (self.fields[start + 2].to_int() << 16) |
    (self.fields[start + 3].to_int() << 24)
  }
}

///|
/// Immutable packed descriptor at the native FFI boundary; retaining it keeps the
/// descriptor valid independently of the loaded artifact's lifetime.
pub fn ContextLayout::words(self : ContextLayout) -> Bytes {
  self.fields
}
