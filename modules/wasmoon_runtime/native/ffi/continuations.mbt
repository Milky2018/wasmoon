///|
priv type ContinuationBridge

///|
priv type ContinuationStorage

///|
#external
priv type ContinuationCreateRequest

///|
#external
priv type ContinuationRootOutput

///|
#valtype
priv struct ContinuationHandle {
  reference : Int64
  body : Int64
  marked : Bool
}

///|
priv struct ContinuationState {
  handles : Array[ContinuationHandle]
  storage : ContinuationStorage
  mut next_reference : Int32
  mut dead : Int32
  mut closed : Bool
  mut quota_bound : Bool
  mut quota : Quota
}

///|
/// Store-owned continuation identities. The bridge retains state, while state
/// owns physical storage and never retains the bridge or a native context.
pub struct NativeContinuationArena {
  priv state : ContinuationState
  priv bridge : ContinuationBridge
}

///|
extern "c" fn ContinuationStorage::new() -> ContinuationStorage = "wasmoon_continuation_storage_new"

///|
#borrow(self)
extern "c" fn ContinuationStorage::clear(self : ContinuationStorage) -> Unit = "wasmoon_continuation_storage_clear"

///|
#borrow(self)
extern "c" fn ContinuationStorage::count(self : ContinuationStorage) -> Int32 = "wasmoon_continuation_storage_count"

///|
#borrow(self)
extern "c" fn ContinuationStorage::body(
  self : ContinuationStorage,
  index : Int32,
) -> Int64 = "wasmoon_continuation_storage_body"

///|
#borrow(self)
extern "c" fn ContinuationStorage::move_to(
  self : ContinuationStorage,
  from : Int32,
  to : Int32,
) -> Unit = "wasmoon_continuation_storage_move"

///|
#borrow(self)
extern "c" fn ContinuationStorage::truncate(
  self : ContinuationStorage,
  count : Int32,
) -> Unit = "wasmoon_continuation_storage_truncate"

///|
#borrow(self, quota)
extern "c" fn ContinuationStorage::create(
  self : ContinuationStorage,
  request : ContinuationCreateRequest,
  quota : Quota,
) -> Int64 = "wasmoon_continuation_storage_create"

///|
extern "c" fn continuation_body_available(body : Int64) -> Bool = "wasmoon_continuation_body_available"

///|
extern "c" fn continuation_body_close(body : Int64) -> Unit = "wasmoon_continuation_body_close"

///|
extern "c" fn continuation_body_on_heap(body : Int64, heap : Int64) -> Bool = "wasmoon_continuation_body_on_heap"

///|
extern "c" fn continuation_body_bind_roots(
  body : Int64,
  reference : Int64,
) -> Bool = "wasmoon_continuation_body_bind_roots"

///|
extern "c" fn continuation_body_gc_roots(body : Int64) -> FixedArray[Int64] = "wasmoon_continuation_body_gc_roots"

///|
extern "c" fn ContinuationRootOutput::write(
  self : ContinuationRootOutput,
  index : Int32,
  reference : Int64,
) -> Unit = "wasmoon_continuation_root_write"

///|
fn ContinuationState::new() -> ContinuationState {
  {
    handles: [],
    storage: ContinuationStorage::new(),
    next_reference: 0,
    dead: 0,
    closed: false,
    quota_bound: false,
    quota: Quota::unlimited(),
  }
}

///|
fn ContinuationState::lookup(
  self : ContinuationState,
  reference : Int64,
) -> Int32 {
  guard !self.closed && reference < 0L && (reference & 1L) != 0L else {
    return -1
  }
  let length = self.handles.length()
  guard length > 0 else { return -1 }
  let offset = (self.handles[0].reference - reference) >> 1
  if offset >= 0L && offset < length.to_int64() {
    let index = offset.to_int()
    let handle = self.handles[index]
    if handle.reference == reference {
      return if continuation_body_available(handle.body) { index } else { -1 }
    }
  }
  let mut low = 0
  let mut high = length
  while low < high {
    let middle = low + (high - low) / 2
    if self.handles[middle].reference > reference {
      low = middle + 1
    } else {
      high = middle
    }
  }
  if low < length &&
    self.handles[low].reference == reference &&
    continuation_body_available(self.handles[low].body) {
    low
  } else {
    -1
  }
}

///|
fn ContinuationState::compact(self : ContinuationState) -> Unit {
  let mut write = 0
  for read = 0; read < self.handles.length(); read = read + 1 {
    let handle = self.handles[read]
    if handle.body != 0L {
      if write != read {
        self.handles[write] = handle
      }
      write += 1
    }
  }
  self.handles.truncate(write)
  self.dead = 0
}

///|
fn ContinuationState::reclaim(self : ContinuationState) -> Unit {
  // Invalidate every identity before releasing a physical owner. A native scope
  // may still pin a retired body, but cannot revive its consumed identity.
  for i = 0; i < self.handles.length(); i = i + 1 {
    let handle = self.handles[i]
    if handle.body != 0L && !continuation_body_available(handle.body) {
      self.handles[i] = { ..handle, body: 0L, marked: false, }
      self.dead += 1
    }
  }
  self.compact()
  let mut write = 0
  let length = self.storage.count()
  for read = 0; read < length; read = read + 1 {
    if continuation_body_available(self.storage.body(read)) {
      if read != write {
        self.storage.move_to(read, write)
      }
      write += 1
    }
  }
  self.storage.truncate(write)
  if write == 0 {
    self.handles.shrink_to_fit()
  } else if self.handles.length() > 0 &&
    self.handles.length() <= self.handles.capacity() / 4 {
    self.handles.shrink_to_fit()
  }
}

///|
fn ContinuationState::publish(self : ContinuationState, body : Int64) -> Int64 {
  // Handles are negative; positive return values are traps raised by native
  // code only after this managed callback has returned.
  let error = if self.closed {
    8
  } else if !continuation_body_available(body) {
    23
  } else if self.next_reference == 0x7fffffff {
    9
  } else {
    0
  }
  if error != 0 {
    continuation_body_close(body)
    self.reclaim()
    return error.to_int64()
  }
  if self.handles.length() == self.handles.capacity() && self.dead > 0 {
    self.compact()
  }
  let reference = -1L - (self.next_reference.to_int64() << 1)
  guard continuation_body_bind_roots(body, reference) else {
    continuation_body_close(body)
    self.reclaim()
    return 8L
  }
  self.handles.push({ reference, body, marked: false, })
  self.next_reference += 1
  reference
}

///|
fn ContinuationState::create(
  self : ContinuationState,
  request : ContinuationCreateRequest,
) -> Int64 {
  guard !self.closed else { return 8L }
  if self.quota_bound {
    self.reclaim()
  }
  guard !self.quota_bound || self.quota.acquire(1L) else { return 27L }
  let body = self.storage.create(request, self.quota)
  guard body != 0L else {
    if self.quota_bound {
      self.quota.release(1L)
    }
    return 9L
  }
  self.publish(body)
}

///|
fn ContinuationState::take(
  self : ContinuationState,
  reference : Int64,
) -> Int64 {
  guard reference != 0L else { return -14L }
  let index = self.lookup(reference)
  guard index >= 0 else { return -23L }
  let handle = self.handles[index]
  self.handles[index] = { ..handle, body: 0L, marked: false, }
  self.dead += 1
  handle.body
}

///|
fn ContinuationState::mark(self : ContinuationState, reference : Int64) -> Unit {
  let index = self.lookup(reference)
  if index >= 0 {
    self.handles[index] = { ..self.handles[index], marked: true, }
  }
}

///|
fn ContinuationState::marked_count(self : ContinuationState) -> Int32 {
  let mut count = 0
  for i = 0; i < self.handles.length(); i = i + 1 {
    if self.handles[i].body != 0L && self.handles[i].marked {
      count += 1
    }
  }
  count
}

///|
fn ContinuationState::copy_marked(
  self : ContinuationState,
  output : ContinuationRootOutput,
) -> Unit {
  let mut write = 0
  for i = 0; i < self.handles.length(); i = i + 1 {
    let handle = self.handles[i]
    if handle.body != 0L && handle.marked {
      output.write(write, handle.reference)
      write += 1
    }
  }
}

///|
fn ContinuationState::reset_marks(self : ContinuationState) -> Unit {
  for i = 0; i < self.handles.length(); i = i + 1 {
    if self.handles[i].marked {
      self.handles[i] = { ..self.handles[i], marked: false, }
    }
  }
}

///|
fn ContinuationState::sweep(self : ContinuationState, heap : Int64) -> Unit {
  for i = 0; i < self.handles.length(); i = i + 1 {
    let handle = self.handles[i]
    if handle.body != 0L && continuation_body_on_heap(handle.body, heap) {
      if handle.marked {
        self.handles[i] = { ..handle, marked: false, }
      } else {
        self.handles[i] = { ..handle, body: 0L, marked: false, }
        self.dead += 1
        continuation_body_close(handle.body)
      }
    }
  }
  self.reclaim()
}

///|
#borrow(state)
extern "c" fn ContinuationBridge::allocate(
  state : ContinuationState,
  create : FuncRef[(ContinuationState, ContinuationCreateRequest) -> Int64],
  publish : FuncRef[(ContinuationState, Int64) -> Int64],
  take : FuncRef[(ContinuationState, Int64) -> Int64],
  mark : FuncRef[(ContinuationState, Int64) -> Unit],
  marked_count : FuncRef[(ContinuationState) -> Int32],
  copy_marked : FuncRef[(ContinuationState, ContinuationRootOutput) -> Unit],
  reset_marks : FuncRef[(ContinuationState) -> Unit],
  sweep : FuncRef[(ContinuationState, Int64) -> Unit],
) -> ContinuationBridge = "wasmoon_continuation_arena_new"

///|
#borrow(self)
extern "c" fn ContinuationBridge::is_available(
  self : ContinuationBridge,
) -> Bool = "wasmoon_continuation_arena_is_available"

///|
pub fn NativeContinuationArena::new() -> NativeContinuationArena raise NativeAllocationError {
  let state = ContinuationState::new()
  let bridge = ContinuationBridge::allocate(
    state,
    fn(state, request) { state.create(request) },
    fn(state, body) { state.publish(body) },
    fn(state, reference) { state.take(reference) },
    fn(state, reference) { state.mark(reference) },
    fn(state) { state.marked_count() },
    fn(state, output) { state.copy_marked(output) },
    fn(state) { state.reset_marks() },
    fn(state, heap) { state.sweep(heap) },
  )
  guard bridge.is_available() else { raise OutOfMemory }
  { state, bridge, }
}

///|
pub fn NativeContinuationArena::clear(self : NativeContinuationArena) -> Unit {
  self.state.closed = true
  self.state.handles.clear()
  self.state.handles.shrink_to_fit()
  self.state.dead = 0
  self.state.storage.clear()
}

///|
pub fn NativeContinuationArena::gc_roots(
  self : NativeContinuationArena,
  reference : Int64,
) -> FixedArray[Int64] {
  let index = self.state.lookup(reference)
  if index < 0 {
    []
  } else {
    continuation_body_gc_roots(self.state.handles[index].body)
  }
}

///|
pub fn NativeContinuationArena::reclaim_retired(
  self : NativeContinuationArena,
) -> Unit {
  self.state.reclaim()
}

///|
pub fn NativeContinuationArena::is_live(
  self : NativeContinuationArena,
  reference : Int64,
) -> Bool {
  self.state.lookup(reference) >= 0
}

///|
pub fn NativeContinuationArena::bind_quota(
  self : NativeContinuationArena,
  quota : Quota,
) -> Bool {
  guard !self.state.closed &&
    !self.state.quota_bound &&
    self.state.storage.count() == 0 else {
    return false
  }
  self.state.quota = quota
  self.state.quota_bound = true
  true
}

///|
#borrow(self, bridge)
extern "c" fn JITContext::bind_continuation_bridge(
  self : JITContext,
  bridge : ContinuationBridge,
) -> Unit = "wasmoon_continuation_arena_bind"

///|
pub fn JITContext::bind_continuation_arena(
  self : JITContext,
  arena : NativeContinuationArena,
) -> Unit {
  self.bind_continuation_bridge(arena.bridge)
}

///|
#borrow(self)
extern "c" fn JITContext::has_continuation_arena(self : JITContext) -> Bool = "wasmoon_continuation_arena_is_bound"

///|
#borrow(self, roots)
extern "c" fn JITContext::define_continuation_type_raw(
  self : JITContext,
  index : Int32,
  trampoline : Int64,
  params : Int32,
  results : Int32,
  roots : FixedArray[Int32],
) -> Bool = "wasmoon_continuation_define_type"

///|
pub fn JITContext::define_continuation_type(
  self : JITContext,
  index : Int32,
  trampoline : Int64,
  params : Int32,
  results : Int32,
  roots : FixedArray[Int32],
) -> Bool {
  guard index >= 0 &&
    params >= 0 &&
    results >= 0 &&
    params <= 0x7fffffff - results &&
    roots.length() == params else {
    return false
  }
  if !self.has_continuation_arena() {
    let arena = NativeContinuationArena::new() catch { _ => return false }
    self.bind_continuation_arena(arena)
  }
  self.define_continuation_type_raw(index, trampoline, params, results, roots)
}
