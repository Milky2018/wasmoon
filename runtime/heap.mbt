///|
/// GC Object representation
/// Stores either a struct instance or an array instance
pub(all) enum GCObject {
  Struct(StructInstance)
  Array(ArrayInstance)
} derive(Show)

///|
/// Struct instance - stores field values
pub(all) struct StructInstance {
  type_idx : Int // Index of the struct type in the module
  fields : Array[@types.Value] // Field values
} derive(Show)

///|
/// Array instance - stores element values and length
pub(all) struct ArrayInstance {
  type_idx : Int // Index of the array type in the module
  elements : Array[@types.Value] // Element values
} derive(Show)

///|
/// GC Heap - manages all GC objects with mark-sweep garbage collection
pub struct GCHeap {
  objects : Array[GCObject?] // None means slot is free (tombstone)
  marks : Array[Bool] // Mark bits for GC
  free_list : Array[Int] // List of free slot indices for reuse
  mut total_live : Int // Count of live objects
  mut gc_threshold : Int // Trigger GC when total_live exceeds this
  mut collections : Int // Number of GC cycles performed
} derive(Show)

///|
/// GC statistics
pub(all) struct GCStats {
  total_objects : Int // Total slots in heap
  live_objects : Int // Number of live objects
  free_slots : Int // Number of free slots
  collections : Int // Number of GC cycles performed
} derive(Show)

///|
/// Create a new empty GC heap
pub fn GCHeap::new() -> GCHeap {
  {
    objects: [],
    marks: [],
    free_list: [],
    total_live: 0,
    gc_threshold: 1000, // Default: trigger GC after 1000 allocations
    collections: 0,
  }
}

///|
/// Create a new GC heap with custom threshold
pub fn GCHeap::with_threshold(threshold : Int) -> GCHeap {
  {
    objects: [],
    marks: [],
    free_list: [],
    total_live: 0,
    gc_threshold: threshold,
    collections: 0,
  }
}

///|
/// Get GC statistics
pub fn GCHeap::stats(self : GCHeap) -> GCStats {
  {
    total_objects: self.objects.length(),
    live_objects: self.total_live,
    free_slots: self.free_list.length(),
    collections: self.collections,
  }
}

///|
/// Allocate a struct instance and return its reference index
pub fn GCHeap::alloc_struct(
  self : GCHeap,
  type_idx : Int,
  fields : Array[@types.Value],
) -> Int {
  let obj = GCObject::Struct({ type_idx, fields })
  self.alloc_object(obj)
}

///|
/// Allocate an array instance and return its reference index
pub fn GCHeap::alloc_array(
  self : GCHeap,
  type_idx : Int,
  elements : Array[@types.Value],
) -> Int {
  let obj = GCObject::Array({ type_idx, elements })
  self.alloc_object(obj)
}

///|
/// Internal: allocate an object, reusing free slots if available
fn GCHeap::alloc_object(self : GCHeap, obj : GCObject) -> Int {
  self.total_live += 1
  // Try to reuse a free slot
  if self.free_list.length() > 0 {
    let idx = self.free_list.pop().unwrap()
    self.objects[idx] = Some(obj)
    self.marks[idx] = false
    return idx
  }
  // Allocate new slot
  let idx = self.objects.length()
  self.objects.push(Some(obj))
  self.marks.push(false)
  idx
}

///|
/// Get an object by reference index
pub fn GCHeap::get(self : GCHeap, idx : Int) -> GCObject raise RuntimeError {
  if idx < 0 || idx >= self.objects.length() {
    raise UndefinedElement
  }
  match self.objects[idx] {
    Some(obj) => obj
    None => raise UndefinedElement // Object was collected
  }
}

///|
/// Get a struct instance by reference index
pub fn GCHeap::get_struct(
  self : GCHeap,
  idx : Int,
) -> StructInstance raise RuntimeError {
  match self.get(idx) {
    Struct(s) => s
    Array(_) => raise TypeMismatch
  }
}

///|
/// Get an array instance by reference index
pub fn GCHeap::get_array(
  self : GCHeap,
  idx : Int,
) -> ArrayInstance raise RuntimeError {
  match self.get(idx) {
    Array(a) => a
    Struct(_) => raise TypeMismatch
  }
}

///|
/// Get a struct field value
pub fn GCHeap::struct_get(
  self : GCHeap,
  struct_idx : Int,
  field_idx : Int,
) -> @types.Value raise RuntimeError {
  let s = self.get_struct(struct_idx)
  if field_idx < 0 || field_idx >= s.fields.length() {
    raise UndefinedElement
  }
  s.fields[field_idx]
}

///|
/// Set a struct field value
pub fn GCHeap::struct_set(
  self : GCHeap,
  struct_idx : Int,
  field_idx : Int,
  value : @types.Value,
) -> Unit raise RuntimeError {
  let s = self.get_struct(struct_idx)
  if field_idx < 0 || field_idx >= s.fields.length() {
    raise UndefinedElement
  }
  s.fields[field_idx] = value
}

///|
/// Get array length
pub fn GCHeap::array_len(
  self : GCHeap,
  array_idx : Int,
) -> Int raise RuntimeError {
  let a = self.get_array(array_idx)
  a.elements.length()
}

///|
/// Get an array element value
pub fn GCHeap::array_get(
  self : GCHeap,
  array_idx : Int,
  elem_idx : Int,
) -> @types.Value raise RuntimeError {
  let a = self.get_array(array_idx)
  if elem_idx < 0 || elem_idx >= a.elements.length() {
    raise OutOfBoundsArrayAccess
  }
  a.elements[elem_idx]
}

///|
/// Set an array element value
pub fn GCHeap::array_set(
  self : GCHeap,
  array_idx : Int,
  elem_idx : Int,
  value : @types.Value,
) -> Unit raise RuntimeError {
  let a = self.get_array(array_idx)
  if elem_idx < 0 || elem_idx >= a.elements.length() {
    raise OutOfBoundsArrayAccess
  }
  a.elements[elem_idx] = value
}

///|
/// Fill array elements with a value
pub fn GCHeap::array_fill(
  self : GCHeap,
  array_idx : Int,
  offset : Int,
  value : @types.Value,
  count : Int,
) -> Unit raise RuntimeError {
  let a = self.get_array(array_idx)
  if offset < 0 || count < 0 || offset + count > a.elements.length() {
    raise OutOfBoundsArrayAccess
  }
  for i in offset..<(offset + count) {
    a.elements[i] = value
  }
}

///|
/// Copy elements between arrays
pub fn GCHeap::array_copy(
  self : GCHeap,
  dst_idx : Int,
  dst_offset : Int,
  src_idx : Int,
  src_offset : Int,
  count : Int,
) -> Unit raise RuntimeError {
  let dst = self.get_array(dst_idx)
  let src = self.get_array(src_idx)
  if dst_offset < 0 ||
    src_offset < 0 ||
    count < 0 ||
    dst_offset + count > dst.elements.length() ||
    src_offset + count > src.elements.length() {
    raise OutOfBoundsArrayAccess
  }
  // Handle overlapping copy correctly
  if dst_idx == src_idx && dst_offset > src_offset {
    // Copy backwards to handle overlap
    for i = count - 1; i >= 0; i = i - 1 {
      dst.elements[dst_offset + i] = src.elements[src_offset + i]
    }
  } else {
    // Copy forwards
    for i in 0..<count {
      dst.elements[dst_offset + i] = src.elements[src_offset + i]
    }
  }
}

///|
/// Get the type index of an object
pub fn GCHeap::get_type_idx(self : GCHeap, idx : Int) -> Int raise RuntimeError {
  match self.get(idx) {
    Struct(s) => s.type_idx
    Array(a) => a.type_idx
  }
}

///|
/// Get total number of allocated objects (including free slots)
pub fn GCHeap::length(self : GCHeap) -> Int {
  self.objects.length()
}

// ============================================================
// Mark-Sweep Garbage Collection
// ============================================================

///|
/// Check if an object index is valid and alive
pub fn GCHeap::is_alive(self : GCHeap, idx : Int) -> Bool {
  if idx < 0 || idx >= self.objects.length() {
    return false
  }
  self.objects[idx] is Some(_)
}

///|
/// Mark an object as reachable (and recursively mark referenced objects)
pub fn GCHeap::mark(self : GCHeap, idx : Int) -> Unit {
  // Bounds check
  if idx < 0 || idx >= self.objects.length() {
    return
  }
  // Already marked or freed
  if self.marks[idx] || self.objects[idx] is None {
    return
  }
  // Mark this object
  self.marks[idx] = true
  // Recursively mark referenced objects
  match self.objects[idx] {
    Some(Struct(s)) =>
      for field in s.fields {
        self.mark_value(field)
      }
    Some(Array(a)) =>
      for elem in a.elements {
        self.mark_value(elem)
      }
    None => ()
  }
}

///|
/// Mark objects referenced by a value
fn GCHeap::mark_value(self : GCHeap, value : @types.Value) -> Unit {
  match value {
    StructRef(idx) => self.mark(idx)
    ArrayRef(idx) => self.mark(idx)
    _ => () // Other values don't reference GC objects
  }
}

///|
/// Mark all objects reachable from the given roots
pub fn GCHeap::mark_roots(self : GCHeap, roots : Array[@types.Value]) -> Unit {
  for root in roots {
    self.mark_value(root)
  }
}

///|
/// Sweep phase: collect all unmarked objects
pub fn GCHeap::sweep(self : GCHeap) -> Int {
  let mut collected = 0
  for i in 0..<self.objects.length() {
    if self.objects[i] is Some(_) {
      if not(self.marks[i]) {
        // Object is not reachable, collect it
        self.objects[i] = None
        self.free_list.push(i)
        self.total_live -= 1
        collected += 1
      }
    }
    // Reset mark bit for next collection
    self.marks[i] = false
  }
  collected
}

///|
/// Perform a full garbage collection cycle
/// Returns the number of objects collected
pub fn GCHeap::collect(self : GCHeap, roots : Array[@types.Value]) -> Int {
  // Mark phase
  self.mark_roots(roots)
  // Sweep phase
  let collected = self.sweep()
  self.collections += 1
  collected
}

///|
/// Check if GC should be triggered based on allocation count
pub fn GCHeap::should_collect(self : GCHeap) -> Bool {
  self.total_live >= self.gc_threshold
}

///|
/// Set the GC threshold
pub fn GCHeap::set_threshold(self : GCHeap, threshold : Int) -> Unit {
  self.gc_threshold = threshold
}

///|
/// Get the current GC threshold
pub fn GCHeap::get_threshold(self : GCHeap) -> Int {
  self.gc_threshold
}
