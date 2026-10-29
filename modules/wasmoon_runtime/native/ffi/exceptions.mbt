///|
// The bridge retains state. State owns payload leases, never the bridge or a
// context. Native contexts may consequently retain the bridge without a cycle.
priv type ExceptionBridge

///|
priv type ExceptionStorage

///|
#external
priv type ExceptionInsertRequest

///|
#external
priv type ExceptionRootOutput

///|
#valtype
priv struct ExceptionEntry {
  reference : Int64
  live : Bool
  marked : Bool
}

///|
priv struct ExceptionState {
  // Numeric metadata is unboxed; owning FFI handles cannot be value fields.
  // Metadata and physical slots have identical lengths. Only this registry
  // appends, retires or compacts them; native storage has no identity policy.
  entries : Array[ExceptionEntry]
  storage : ExceptionStorage
  mut dead_entries : Int32
  layouts : Map[Int32, FixedArray[Int32]]
  mut last_tag : Int32
  mut last_mask : FixedArray[Int32]?
  mut next_reference : Int32
  mut closed : Bool
  mut traced : Bool
  mut quotas_bound : Bool
  mut bytes : Quota
  mut objects : Quota
  mut quota_denied : Int32
}

///|
/// Store-owned immutable exception snapshots shared by native instances.
pub struct NativeExceptionArena {
  priv bridge : ExceptionBridge
  priv state : ExceptionState
}

///|
fn ExceptionState::new() -> ExceptionState {
  {
    entries: [],
    storage: ExceptionStorage::new(),
    dead_entries: 0,
    layouts: {},
    last_tag: 0,
    last_mask: None,
    next_reference: 0,
    closed: false,
    traced: false,
    quotas_bound: false,
    bytes: Quota::unlimited(),
    objects: Quota::unlimited(),
    quota_denied: 0,
  }
}

///|
#borrow(mask)
extern "c" fn ExceptionInsertRequest::append_payload(
  self : ExceptionInsertRequest,
  reference : Int64,
  mask : FixedArray[Int32],
  traced : Bool,
  byte_charge : Int64,
  object_charge : Int64,
) -> Bool = "wasmoon_exception_storage_append"

///|
extern "c" fn ExceptionStorage::new() -> ExceptionStorage = "wasmoon_exception_storage_new"

///|
#borrow(self)
extern "c" fn ExceptionStorage::clear(self : ExceptionStorage) -> Unit = "wasmoon_exception_storage_clear"

///|
#borrow(self, bytes, objects)
extern "c" fn ExceptionStorage::bind_quotas(
  self : ExceptionStorage,
  bytes : Quota,
  objects : Quota,
) -> Bool = "wasmoon_exception_storage_bind_quotas"

///|
#borrow(self)
extern "c" fn ExceptionStorage::capacity(self : ExceptionStorage) -> Int32 = "wasmoon_exception_storage_capacity"

///|
#borrow(self)
extern "c" fn ExceptionStorage::shrink_to_fit(self : ExceptionStorage) -> Unit = "wasmoon_exception_storage_shrink"

///|
#borrow(self)
extern "c" fn ExceptionStorage::close_at(
  self : ExceptionStorage,
  index : Int32,
) -> Unit = "wasmoon_exception_storage_close_at"

///|
#borrow(self)
extern "c" fn ExceptionStorage::move_entry(
  self : ExceptionStorage,
  from : Int32,
  to : Int32,
) -> Unit = "wasmoon_exception_storage_move"

///|
#borrow(self)
extern "c" fn ExceptionStorage::truncate(
  self : ExceptionStorage,
  count : Int32,
) -> Unit = "wasmoon_exception_storage_truncate"

///|
#borrow(self)
extern "c" fn ExceptionStorage::tag(
  self : ExceptionStorage,
  index : Int32,
) -> Int32 = "wasmoon_exception_storage_tag"

///|
#borrow(self)
extern "c" fn ExceptionStorage::values(
  self : ExceptionStorage,
  index : Int32,
) -> FixedArray[Int64] = "wasmoon_exception_storage_values"

///|
#borrow(self)
extern "c" fn ExceptionStorage::on_heap(
  self : ExceptionStorage,
  index : Int32,
  heap : Int64,
) -> Bool = "wasmoon_exception_storage_on_heap"

///|
#borrow(mask)
extern "c" fn exception_layout_address(mask : FixedArray[Int32]) -> Int64 = "wasmoon_exception_layout_address"

///|
extern "c" fn ExceptionRootOutput::write(
  self : ExceptionRootOutput,
  index : Int32,
  value : Int64,
) -> Unit = "wasmoon_exception_root_write"

///|
fn ExceptionState::insert(
  self : ExceptionState,
  request : ExceptionInsertRequest,
  tag : Int32,
  count : Int32,
) -> Int64 {
  self.quota_denied = 0
  guard !self.closed && count >= 0 && self.next_reference < 0x7fffffff else {
    return -9
  }
  if self.last_tag != tag {
    self.cache_layout(tag)
  }
  let mask = match self.last_mask {
    Some(mask) => {
      guard mask.length() == count else { return -9 }
      mask
    }
    None => [] // Empty mask preserves conservative roots for unknown tags.
  }
  let amount = 16L + count.to_int64() * 16L
  guard !self.quotas_bound || self.bytes.acquire(amount) else {
    self.quota_denied = 25
    return -25
  }
  guard !self.quotas_bound || self.objects.acquire(1L) else {
    self.bytes.release(amount)
    self.quota_denied = 26
    return -26
  }
  let reference = 0x1000000000000001L | (self.next_reference.to_int64() << 1)
  let copied = request.append_payload(
    reference,
    mask,
    self.traced,
    if self.quotas_bound {
      amount
    } else {
      0L
    },
    if self.quotas_bound {
      1L
    } else {
      0L
    },
  )
  guard copied else {
    if self.quotas_bound {
      self.bytes.release(amount)
      self.objects.release(1L)
    }
    return -9
  }
  self.entries.push({ reference, live: true, marked: false, })
  self.next_reference += 1
  reference
}

///|
// Identities are appended monotonically. Dead entries remain searchable until
// compaction, but never yield a payload. Storage tracks live/peak occupancy,
// rather than the total number of identities issued over the arena lifetime.
fn ExceptionState::lookup(self : ExceptionState, reference : Int64) -> Int64 {
  // In an uncompacted run, monotonic identities give the slot directly. After
  // compaction the estimate may be wrong: compare the full live identity and
  // fall back to ordered search. Storage and liveness remain authoritative.
  let length = self.entries.length()
  if length > 0 {
    let offset = (reference - self.entries[0].reference) >> 1
    if offset >= 0L && offset < length.to_int64() {
      let index = offset.to_int()
      let entry = self.entries[index]
      if entry.reference == reference && entry.live {
        return offset + 1L
      }
    }
  }
  for low = 0, high = self.entries.length(); low < high; {
    let middle = low + (high - low) / 2
    let entry = self.entries[middle]
    if entry.reference < reference {
      continue middle + 1, high
    } else if entry.reference > reference {
      continue low, middle
    } else {
      return if entry.live { middle.to_int64() + 1L } else { 0L }
    }
  }
  0L
}

///|
fn ExceptionState::cache_layout(self : ExceptionState, tag : Int32) -> Unit {
  self.last_mask = self.layouts.get(tag)
  self.last_tag = tag
}

///|
fn ExceptionState::layout(self : ExceptionState, tag : Int32) -> Int64 {
  if self.last_tag != tag {
    self.cache_layout(tag)
  }
  match self.last_mask {
    Some(mask) => exception_layout_address(mask)
    None => 0L
  }
}

///|
fn ExceptionState::mark(self : ExceptionState, reference : Int64) -> Unit {
  let index = self.lookup(reference).to_int() - 1
  if index >= 0 {
    self.entries[index] = { ..self.entries[index], marked: true, }
  }
}

///|
fn ExceptionState::marked_count(self : ExceptionState) -> Int32 {
  let mut count = 0
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].marked {
      count += 1
    }
  }
  count
}

///|
fn ExceptionState::copy_marked(
  self : ExceptionState,
  output : ExceptionRootOutput,
) -> Unit {
  let mut index = 0
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].marked {
      output.write(index, self.entries[i].reference)
      index += 1
    }
  }
}

///|
fn ExceptionState::reset_marks(self : ExceptionState) -> Unit {
  for i = 0; i < self.entries.length(); i = i + 1 {
    self.entries[i] = { ..self.entries[i], marked: false, }
  }
}

///|
fn ExceptionState::compact(self : ExceptionState) -> Unit {
  if self.dead_entries > 0 {
    let mut write = 0
    for read = 0; read < self.entries.length(); read = read + 1 {
      let entry = self.entries[read]
      if entry.live {
        if write != read {
          self.entries[write] = entry
          self.storage.move_entry(read, write)
        }
        write += 1
      }
    }
    self.entries.truncate(write)
    self.storage.truncate(write)
    self.dead_entries = 0
  }
  // Keep headroom during ordinary GC. Shrinking after every surviving sweep
  // would force another growth on the next insertion and break amortization.
  if self.entries.length() <= self.entries.capacity() / 4 {
    self.entries.shrink_to_fit()
  }
  if self.entries.length() <= self.storage.capacity() / 4 {
    self.storage.shrink_to_fit()
  }
}

///|
fn ExceptionState::retire(self : ExceptionState, index : Int32) -> Unit {
  self.entries[index] = { ..self.entries[index], live: false, marked: false, }
  self.storage.close_at(index)
  self.dead_entries += 1
}

///|
fn ExceptionState::release_snapshot(
  self : ExceptionState,
  reference : Int64,
) -> Unit {
  let index = self.lookup(reference).to_int() - 1
  if index < 0 {
    return
  }
  self.retire(index)
  // Batch removal avoids shifting the whole registry for every retirement.
  if self.dead_entries > self.entries.length() / 2 {
    self.compact()
  }
}

///|
fn ExceptionState::sweep(self : ExceptionState, heap : Int64) -> Unit {
  guard self.traced else { return }
  for i = 0; i < self.entries.length(); i = i + 1 {
    let entry = self.entries[i]
    if entry.live && !entry.marked && self.storage.on_heap(i, heap) {
      self.retire(i)
    } else if entry.marked {
      self.entries[i] = { ..entry, marked: false, }
    }
  }
  self.compact()
}

///|
#borrow(state, storage)
extern "c" fn ExceptionBridge::allocate(
  state : ExceptionState,
  storage : ExceptionStorage,
  insert : FuncRef[
    (ExceptionState, ExceptionInsertRequest, Int32, Int32) -> Int64,
  ],
  lookup : FuncRef[(ExceptionState, Int64) -> Int64],
  layout : FuncRef[(ExceptionState, Int32) -> Int64],
  mark : FuncRef[(ExceptionState, Int64) -> Unit],
  marked_count : FuncRef[(ExceptionState) -> Int32],
  copy_marked : FuncRef[(ExceptionState, ExceptionRootOutput) -> Unit],
  reset_marks : FuncRef[(ExceptionState) -> Unit],
  sweep : FuncRef[(ExceptionState, Int64) -> Unit],
) -> ExceptionBridge = "wasmoon_exception_arena_new"

///|
fn ExceptionBridge::new(state : ExceptionState) -> ExceptionBridge {
  ExceptionBridge::allocate(
    state,
    state.storage,
    fn(state, request, tag, count) { state.insert(request, tag, count) },
    fn(state, reference) { state.lookup(reference) },
    fn(state, tag) { state.layout(tag) },
    fn(state, reference) { state.mark(reference) },
    fn(state) { state.marked_count() },
    fn(state, output) { state.copy_marked(output) },
    fn(state) { state.reset_marks() },
    fn(state, heap) { state.sweep(heap) },
  )
}

///|
#borrow(self)
extern "c" fn ExceptionBridge::is_available(self : ExceptionBridge) -> Bool = "wasmoon_exception_arena_is_available"

///|
pub fn NativeExceptionArena::new() -> NativeExceptionArena raise NativeAllocationError {
  let state = ExceptionState::new()
  let bridge = ExceptionBridge::new(state)
  guard bridge.is_available() else { raise OutOfMemory }
  { state, bridge, }
}

///|
pub fn NativeExceptionArena::clear(self : NativeExceptionArena) -> Unit {
  self.state.entries.clear()
  self.state.entries.shrink_to_fit()
  self.state.storage.clear()
  self.state.dead_entries = 0
  self.state.layouts.clear()
  self.state.last_tag = 0
  self.state.last_mask = None
  self.state.closed = true
}

///|
/// Store-managed arenas reclaim snapshots through the heap's root visitor.
pub fn NativeExceptionArena::enable_reclamation(
  self : NativeExceptionArena,
) -> Unit {
  self.state.traced = true
}

///|
pub fn NativeExceptionArena::release_snapshot(
  self : NativeExceptionArena,
  reference : Int64,
) -> Unit {
  self.state.release_snapshot(reference)
}

///|
#borrow(self, values, heap)
extern "c" fn ExceptionBridge::insert_raw(
  self : ExceptionBridge,
  heap : GCHeapHandle,
  tag : Int32,
  values : FixedArray[Int64],
  count : Int32,
) -> Int64 = "wasmoon_exception_arena_insert"

///|
pub fn NativeExceptionArena::snapshot(
  self : NativeExceptionArena,
  reference : Int64,
) -> (Int32, Array[Int64])? {
  let index = self.state.lookup(reference).to_int() - 1
  if index < 0 {
    return None
  }
  let values = self.state.storage.values(index)
  Some(
    (
      self.state.storage.tag(index),
      Array::makei(values.length(), fn(i) { values[i] }),
    ),
  )
}

///|
pub fn NativeExceptionArena::insert(
  self : NativeExceptionArena,
  heap : GCHeapHandle,
  tag : Int32,
  values : Array[Int64],
) -> Int64 {
  let buffer = FixedArray::makei(values.length(), fn(i) { values[i] })
  self.bridge.insert_raw(heap, tag, buffer, buffer.length())
}

///|
/// Describe reference-bearing payload words; scalar and SIMD words are never
/// retained as accidental GC roots.
pub fn NativeExceptionArena::define_tag(
  self : NativeExceptionArena,
  tag : Int32,
  params : ArrayView[@types.ValueType],
) -> Bool {
  guard !self.state.closed else { return false }
  if self.state.layouts.contains(tag) {
    return true
  }
  let roots : Array[Int32] = []
  for ty in params {
    match ty {
      I32 | I64 | F32 | F64 => roots.push(0)
      V128 => {
        roots.push(0)
        roots.push(0)
      }
      _ => roots.push(1)
    }
  }
  let mask = FixedArray::makei(roots.length(), fn(i) { roots[i] })
  self.state.layouts[tag] = mask
  self.state.last_tag = tag
  self.state.last_mask = Some(mask)
  true
}

///|
pub fn NativeExceptionArena::bind_quotas(
  self : NativeExceptionArena,
  bytes : Quota,
  objects : Quota,
) -> Bool {
  guard !self.state.closed &&
    self.state.entries.length() == self.state.dead_entries &&
    !self.state.quotas_bound else {
    return false
  }
  guard self.state.storage.bind_quotas(bytes, objects) else { return false }
  self.state.bytes = bytes
  self.state.objects = objects
  self.state.quotas_bound = true
  true
}

///|
pub fn NativeExceptionArena::quota_denied(self : NativeExceptionArena) -> Int32 {
  self.state.quota_denied
}

///|
#borrow(context, bridge)
extern "c" fn bind_exception_bridge(
  context : JITContext,
  bridge : ExceptionBridge,
) -> Unit = "wasmoon_exception_arena_bind"

///|
/// Bind a shared exception registry; contexts retain its native callback view.
pub fn JITContext::bind_exception_arena(
  self : JITContext,
  arena : NativeExceptionArena,
) -> Unit {
  bind_exception_bridge(self, arena.bridge)
}

///|
#borrow(context)
extern "c" fn set_exception_factory(
  context : JITContext,
  factory : FuncRef[() -> ExceptionBridge],
) -> Unit = "wasmoon_exception_arena_set_factory"

///|
fn install_exception_factory(context : JITContext) -> JITContext {
  set_exception_factory(context, fn() {
    ExceptionBridge::new(ExceptionState::new())
  })
  context
}

///|
/// Whether metadata entries, including retired entries, still exist.
pub fn NativeExceptionArena::has_entries(self : NativeExceptionArena) -> Bool {
  !self.state.entries.is_empty()
}
