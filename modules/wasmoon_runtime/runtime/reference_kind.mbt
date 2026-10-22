///|
#cfg(target="native")
fn Store::gc_reference_kind(self : Store, index : Int32) -> Int32 {
  if self.closed.val {
    return 0
  }
  if self.references.native.c_heap is Some(heap) {
    return heap.get_kind(index)
  }
  let object = self.heap.get(index) catch { _ => return 0 }
  match object {
    Struct(_) => 1
    Array(_) => 2
  }
}

///|
#cfg(target="wasm")
fn Store::gc_reference_kind(self : Store, index : Int32) -> Int32 {
  if self.closed.val {
    return 0
  }
  let object = self.heap.get(index) catch { _ => return 0 }
  match object {
    Struct(_) => 1
    Array(_) => 2
  }
}

///|
/// Check the live object's kind, independently of a raw Value variant.
pub fn Store::is_struct_reference(self : Store, index : Int32) -> Bool {
  self.gc_reference_kind(index) == 1
}

///|
/// Check the live object's kind, independently of a raw Value variant.
pub fn Store::is_array_reference(self : Store, index : Int32) -> Bool {
  self.gc_reference_kind(index) == 2
}
