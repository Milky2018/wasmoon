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
pub struct MarkSweepHeap {
  objects : Array[GCObject?] // None means slot is free (tombstone)
  marks : Array[Bool] // Mark bits for GC
  free_list : Array[Int] // List of free slot indices for reuse
  mut total_live : Int // Count of live objects
  mut gc_threshold : Int // Trigger GC when total_live exceeds this
  mut collections : Int // Number of GC cycles performed
} derive(Show)

///|
/// GC statistics
pub struct GCStats {
  total_objects : Int // Total slots in heap
  live_objects : Int // Number of live objects
  free_slots : Int // Number of free slots
  collections : Int // Number of GC cycles performed
} derive(Show)

///|
/// Create a new empty GC heap
pub fn MarkSweepHeap::new() -> MarkSweepHeap {
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
pub fn MarkSweepHeap::with_threshold(threshold : Int) -> MarkSweepHeap {
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
pub fn MarkSweepHeap::stats(self : MarkSweepHeap) -> GCStats {
  {
    total_objects: self.objects.length(),
    live_objects: self.total_live,
    free_slots: self.free_list.length(),
    collections: self.collections,
  }
}

///|
/// Allocate a struct instance and return its reference index
pub fn MarkSweepHeap::alloc_struct(
  self : MarkSweepHeap,
  type_idx : Int,
  fields : Array[@types.Value],
) -> Int {
  let obj = GCObject::Struct({ type_idx, fields })
  self.alloc_object(obj)
}

///|
/// Allocate an array instance and return its reference index
pub fn MarkSweepHeap::alloc_array(
  self : MarkSweepHeap,
  type_idx : Int,
  elements : Array[@types.Value],
) -> Int {
  let obj = GCObject::Array({ type_idx, elements })
  self.alloc_object(obj)
}

///|
/// Internal: allocate an object, reusing free slots if available
fn MarkSweepHeap::alloc_object(self : MarkSweepHeap, obj : GCObject) -> Int {
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
pub fn MarkSweepHeap::get(
  self : MarkSweepHeap,
  idx : Int,
) -> GCObject raise RuntimeError {
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
pub fn MarkSweepHeap::get_struct(
  self : MarkSweepHeap,
  idx : Int,
) -> StructInstance raise RuntimeError {
  match self.get(idx) {
    Struct(s) => s
    Array(_) => raise TypeMismatch
  }
}

///|
/// Get an array instance by reference index
pub fn MarkSweepHeap::get_array(
  self : MarkSweepHeap,
  idx : Int,
) -> ArrayInstance raise RuntimeError {
  match self.get(idx) {
    Array(a) => a
    Struct(_) => raise TypeMismatch
  }
}

///|
/// Get a struct field value
pub fn MarkSweepHeap::struct_get(
  self : MarkSweepHeap,
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
pub fn MarkSweepHeap::struct_set(
  self : MarkSweepHeap,
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
pub fn MarkSweepHeap::array_len(
  self : MarkSweepHeap,
  array_idx : Int,
) -> Int raise RuntimeError {
  let a = self.get_array(array_idx)
  a.elements.length()
}

///|
/// Get an array element value
pub fn MarkSweepHeap::array_get(
  self : MarkSweepHeap,
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
pub fn MarkSweepHeap::array_set(
  self : MarkSweepHeap,
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
pub fn MarkSweepHeap::array_fill(
  self : MarkSweepHeap,
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
pub fn MarkSweepHeap::array_copy(
  self : MarkSweepHeap,
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
pub fn MarkSweepHeap::get_type_idx(
  self : MarkSweepHeap,
  idx : Int,
) -> Int raise RuntimeError {
  match self.get(idx) {
    Struct(s) => s.type_idx
    Array(a) => a.type_idx
  }
}

///|
/// Get total number of allocated objects (including free slots)
pub fn MarkSweepHeap::length(self : MarkSweepHeap) -> Int {
  self.objects.length()
}

// ============================================================
// Mark-Sweep Garbage Collection
// ============================================================

///|
/// Check if an object index is valid and alive
pub fn MarkSweepHeap::is_alive(self : MarkSweepHeap, idx : Int) -> Bool {
  if idx < 0 || idx >= self.objects.length() {
    return false
  }
  self.objects[idx] is Some(_)
}

///|
/// Mark an object as reachable (and recursively mark referenced objects)
pub fn MarkSweepHeap::mark(self : MarkSweepHeap, idx : Int) -> Unit {
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
fn MarkSweepHeap::mark_value(
  self : MarkSweepHeap,
  value : @types.Value,
) -> Unit {
  match value {
    StructRef(idx) => self.mark(idx)
    ArrayRef(idx) => self.mark(idx)
    _ => () // Other values don't reference GC objects
  }
}

///|
/// Mark all objects reachable from the given roots
pub fn MarkSweepHeap::mark_roots(
  self : MarkSweepHeap,
  roots : Array[@types.Value],
) -> Unit {
  for root in roots {
    self.mark_value(root)
  }
}

///|
/// Sweep phase: collect all unmarked objects
pub fn MarkSweepHeap::sweep(self : MarkSweepHeap) -> Int {
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
pub fn MarkSweepHeap::collect(
  self : MarkSweepHeap,
  roots : Array[@types.Value],
) -> Int {
  // Mark phase
  self.mark_roots(roots)
  // Sweep phase
  let collected = self.sweep()
  self.collections += 1
  collected
}

///|
/// Check if GC should be triggered based on allocation count
pub fn MarkSweepHeap::should_collect(self : MarkSweepHeap) -> Bool {
  self.total_live >= self.gc_threshold
}

///|
/// Set the GC threshold
pub fn MarkSweepHeap::set_threshold(
  self : MarkSweepHeap,
  threshold : Int,
) -> Unit {
  self.gc_threshold = threshold
}

///|
/// Get the current GC threshold
pub fn MarkSweepHeap::get_threshold(self : MarkSweepHeap) -> Int {
  self.gc_threshold
}

///|
/// Check if an object reference is valid and alive
pub fn MarkSweepHeap::is_valid(self : MarkSweepHeap, idx : Int) -> Bool {
  self.is_alive(idx)
}

// ============================================================
// Trait Implementations for MarkSweepHeap
// ============================================================

///|
pub impl GcHeap for MarkSweepHeap with alloc_struct(self, type_idx, fields) -> Int {
  MarkSweepHeap::alloc_struct(self, type_idx, fields)
}

///|
pub impl GcHeap for MarkSweepHeap with alloc_array(self, type_idx, elements) -> Int {
  MarkSweepHeap::alloc_array(self, type_idx, elements)
}

///|
pub impl GcHeap for MarkSweepHeap with struct_get(self, struct_idx, field_idx) -> @types.Value {
  MarkSweepHeap::struct_get(self, struct_idx, field_idx)
}

///|
pub impl GcHeap for MarkSweepHeap with struct_set(
  self,
  struct_idx,
  field_idx,
  value,
) -> Unit {
  MarkSweepHeap::struct_set(self, struct_idx, field_idx, value)
}

///|
pub impl GcHeap for MarkSweepHeap with array_len(self, array_idx) -> Int {
  MarkSweepHeap::array_len(self, array_idx)
}

///|
pub impl GcHeap for MarkSweepHeap with array_get(self, array_idx, elem_idx) -> @types.Value {
  MarkSweepHeap::array_get(self, array_idx, elem_idx)
}

///|
pub impl GcHeap for MarkSweepHeap with array_set(
  self,
  array_idx,
  elem_idx,
  value,
) -> Unit {
  MarkSweepHeap::array_set(self, array_idx, elem_idx, value)
}

///|
pub impl GcHeap for MarkSweepHeap with array_fill(
  self,
  array_idx,
  offset,
  value,
  count,
) -> Unit {
  MarkSweepHeap::array_fill(self, array_idx, offset, value, count)
}

///|
pub impl GcHeap for MarkSweepHeap with array_copy(
  self,
  dst_idx,
  dst_offset,
  src_idx,
  src_offset,
  count,
) -> Unit {
  MarkSweepHeap::array_copy(
    self, dst_idx, dst_offset, src_idx, src_offset, count,
  )
}

///|
pub impl GcHeap for MarkSweepHeap with get_type_idx(self, idx) -> Int {
  MarkSweepHeap::get_type_idx(self, idx)
}

///|
pub impl GcHeap for MarkSweepHeap with is_valid(self, idx) -> Bool {
  MarkSweepHeap::is_valid(self, idx)
}

// ============================================================
// GcRuntime Trait Implementation for MarkSweepHeap
// ============================================================

///|
pub impl GcRuntime for MarkSweepHeap with should_collect(self) -> Bool {
  MarkSweepHeap::should_collect(self)
}

///|
pub impl GcRuntime for MarkSweepHeap with collect(self, roots) -> Unit {
  MarkSweepHeap::collect(self, roots) |> ignore
}

///|
pub impl GcRuntime for MarkSweepHeap with force_collect(self, roots) -> Unit {
  MarkSweepHeap::collect(self, roots) |> ignore
}

///|
pub impl GcRuntime for MarkSweepHeap with write_barrier_pre(
  _self,
  _obj_idx,
  _old_value,
  _new_value,
) -> Unit {
  // No-op for stop-the-world mark-sweep GC
}

///|
pub impl GcRuntime for MarkSweepHeap with write_barrier_post(
  _self,
  _obj_idx,
  _new_value,
) -> Unit {
  // No-op for stop-the-world mark-sweep GC
}

///|
pub impl GcRuntime for MarkSweepHeap with read_barrier(_self, idx) -> @types.Value {
  // No-op for stop-the-world GC - just return the reference unchanged
  @types.Value::StructRef(idx)
}

///|
pub impl GcRuntime for MarkSweepHeap with stats(self) -> GcStats {
  let old_stats = MarkSweepHeap::stats(self)
  {
    total_slots: old_stats.total_objects,
    live_objects: old_stats.live_objects,
    free_slots: old_stats.free_slots,
    collections: old_stats.collections,
    bytes_allocated: 0L, // Not tracked in this implementation
    bytes_collected: 0L, // Not tracked in this implementation
  }
}

///|
pub impl GcRuntime for MarkSweepHeap with collection_count(self) -> Int {
  self.collections
}

///|
pub impl GcRuntime for MarkSweepHeap with set_threshold(self, threshold) -> Unit {
  MarkSweepHeap::set_threshold(self, threshold)
}

///|
pub impl GcRuntime for MarkSweepHeap with get_threshold(self) -> Int {
  MarkSweepHeap::get_threshold(self)
}

// ============================================================
// GcManager Trait Implementation for MarkSweepHeap
// ============================================================

///|
pub impl GcManager for MarkSweepHeap with alloc_struct(self, type_idx, fields) -> Int {
  MarkSweepHeap::alloc_struct(self, type_idx, fields)
}

///|
pub impl GcManager for MarkSweepHeap with alloc_array(self, type_idx, elements) -> Int {
  MarkSweepHeap::alloc_array(self, type_idx, elements)
}

///|
pub impl GcManager for MarkSweepHeap with struct_get(
  self,
  struct_idx,
  field_idx,
) -> @types.Value {
  MarkSweepHeap::struct_get(self, struct_idx, field_idx)
}

///|
pub impl GcManager for MarkSweepHeap with struct_set(
  self,
  struct_idx,
  field_idx,
  value,
) -> Unit {
  MarkSweepHeap::struct_set(self, struct_idx, field_idx, value)
}

///|
pub impl GcManager for MarkSweepHeap with array_len(self, array_idx) -> Int {
  MarkSweepHeap::array_len(self, array_idx)
}

///|
pub impl GcManager for MarkSweepHeap with array_get(self, array_idx, elem_idx) -> @types.Value {
  MarkSweepHeap::array_get(self, array_idx, elem_idx)
}

///|
pub impl GcManager for MarkSweepHeap with array_set(
  self,
  array_idx,
  elem_idx,
  value,
) -> Unit {
  MarkSweepHeap::array_set(self, array_idx, elem_idx, value)
}

///|
pub impl GcManager for MarkSweepHeap with array_fill(
  self,
  array_idx,
  offset,
  value,
  count,
) -> Unit {
  MarkSweepHeap::array_fill(self, array_idx, offset, value, count)
}

///|
pub impl GcManager for MarkSweepHeap with array_copy(
  self,
  dst_idx,
  dst_offset,
  src_idx,
  src_offset,
  count,
) -> Unit {
  MarkSweepHeap::array_copy(
    self, dst_idx, dst_offset, src_idx, src_offset, count,
  )
}

///|
pub impl GcManager for MarkSweepHeap with get_type_idx(self, idx) -> Int {
  MarkSweepHeap::get_type_idx(self, idx)
}

///|
pub impl GcManager for MarkSweepHeap with is_valid(self, idx) -> Bool {
  MarkSweepHeap::is_valid(self, idx)
}

///|
pub impl GcManager for MarkSweepHeap with should_collect(self) -> Bool {
  MarkSweepHeap::should_collect(self)
}

///|
pub impl GcManager for MarkSweepHeap with collect(self, roots) -> Unit {
  MarkSweepHeap::collect(self, roots) |> ignore
}

///|
pub impl GcManager for MarkSweepHeap with stats(self) -> GcStats {
  let old_stats = MarkSweepHeap::stats(self)
  {
    total_slots: old_stats.total_objects,
    live_objects: old_stats.live_objects,
    free_slots: old_stats.free_slots,
    collections: old_stats.collections,
    bytes_allocated: 0L,
    bytes_collected: 0L,
  }
}

///|
pub impl GcManager for MarkSweepHeap with write_barrier(
  _self,
  _obj_idx,
  _old_value,
  _new_value,
) -> Unit {
  // No-op for stop-the-world mark-sweep GC
}
