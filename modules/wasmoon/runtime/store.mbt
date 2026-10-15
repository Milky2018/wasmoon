///|
/// Exception instance - represents a caught exception
pub struct ExnInstance {
  tag_addr : Int32 // Which tag was thrown
  values : Array[@types.Value] // Exception values
} derive(Debug)

///|
/// Represents the ownership status of a function in the store
pub(all) enum FuncOwner {
  HostFunc // Host function - never has an owner module
  Unowned // WASM function not yet assigned to a module
  Module(Int32) // WASM function owned by module at given index
} derive(Debug, Eq)

///|
/// The store contains all global runtime state
pub struct Store {
  nan_canonicalization : Bool
  interpreter_limits : InterpreterLimits
  priv mut next_exception : Int32
  priv mut next_wrapped_extern : Int32
  priv mut gc_tracing_depth : Int32
  priv mut gc_in_collect : Bool
  priv mut gc_trace : GcTrace?
  priv mut interpreter_reentry_depth : Int32
  funcs : Array[FuncInst]
  func_types : Array[@types.FuncType] // Type of each function
  func_type_indices : Array[Int32] // Original type index for structural comparison
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
  tags : Array[@types.FuncType] // Tag types (params only, no results)
  tag_type_indices : Array[Int32] // Original type index for each tag
  tag_owners : Array[FuncOwner] // Owner module for each tag
  mut exns : Map[Int32, ExnInstance] // Live exception snapshots, with non-reused handles
  heap : MarkSweepHeap // GC heap for struct and array instances (interpreter mode)
  // C-managed GC heap for JIT mode (None = use MarkSweepHeap)
  mut c_heap : @wasmoon_jit.CHeap?
  // Module types for CHeap type lookups (needed to decode Int64 to Value)
  mut module_types : Array[@types.SubType]
  // Module rec groups for canonical type index computation
  mut module_rec_groups : Array[Int32]
  // Internal values wrapped as externref via extern.convert_any
  // Accessed using negative ExternRef indices: ExternRef(-1-i) = wrapped_externs[i]
  mut wrapped_externs : Map[Int32, @types.Value]
  // Maps function address to its owning module instance
  // Used for cross-module call context switching
  func_owners : Array[FuncOwner]
  // Registered module instances by their address/index
  instances : Array[ModuleInstance]
  // JIT tables corresponding to runtime tables (for cross-module sharing)
  // jit_tables[i] is the JIT table for tables[i], or None if not using JIT
  jit_tables : Array[@wasmoon_jit.JITTable?]
  // Store-only destruction capabilities corresponding to jit_tables.
  priv jit_table_owners : Array[@wasmoon_jit.JITTableOwner?]
  // Current WASI module's memory address (for interpreter mode WASI callbacks)
  // WASI callbacks use this to access the correct memory instead of hardcoded index 0
  mut wasi_mem_addr : Int32?
  // Opaque WASI context handle (for WAST runner to store WASI context)
  // This avoids circular dependency between runtime and wasi packages
  mut wasi_ctx_handle : Int32
  // Native invocation/fiber lifetimes belong to the Store, not a JIT module.
  native_execution : @wasmoon_jit.NativeExecutionState
  priv funcref_registry : StoreFuncrefRegistry
  priv native_types : StoreTypeRegistry
  priv native_exception_to_store : Map[Int64, Int32]
  priv store_exception_to_native : Map[Int32, Int64]
  priv suspended_executions : Map[Int64, SuspendedExecutionCleanup]
  priv mut next_suspended_execution_id : Int64
  priv mut guest_continuations : Map[Int64, GuestContinuationBody]
  priv mut next_guest_continuation : Int64
  priv mut pinned_gc_roots : Map[Int64, PinnedGcRoots]
  priv mut next_pinned_gc_roots_id : Int64
  priv mut instantiation : RollbackRegistrar?
  priv closed : Ref[Bool]
} derive(Debug)

///|
fn Store::register_rollback(
  self : Store,
  registrar : RollbackRegistrar,
) -> Unit {
  self.instantiation = Some(registrar)
  registrar.on_finish(fn() { self.instantiation = None })
  // Heap cleanup runs last, after mutation-local rollbacks restore Store roots.
  registrar.on_rollback(
    self.heap.make_allocation_rollback(fn() { self.collect_roots([]) }),
  )
  if self.c_heap is Some(heap) {
    registrar.on_rollback(
      heap.make_allocation_rollback(fn() { self.collect_roots([]) }),
    )
  }
}

///|
fn Store::on_instantiation_rollback(
  self : Store,
  rollback : () -> Unit,
) -> Unit {
  if self.instantiation is Some(registrar) {
    registrar.on_rollback(rollback)
  }
}

///|
fn[T] Store::push_allocation(
  self : Store,
  values : Array[T],
  value : T,
) -> Int32 {
  let index = values.length()
  self.on_instantiation_rollback(fn() {
    values.truncate(index)
    values.shrink_to_fit()
  })
  values.push(value)
  index
}

///|
/// Optional C heap initial capacity override (bytes)
const GC_HEAP_CAPACITY_ENV : String = "WASMOON_GC_HEAP_CAPACITY"

///|
fn parse_decimal_int(value : String) -> Int32? {
  if value.length() == 0 {
    return None
  }
  let mut parsed = 0
  for codepoint in value {
    let digit = codepoint.to_int() - b'0'.to_int()
    if digit < 0 || digit > 9 {
      return None
    }
    parsed = parsed * 10 + digit
  }
  Some(parsed)
}

///|
fn c_heap_initial_capacity() -> Int32 {
  match @env.get_env_var(GC_HEAP_CAPACITY_ENV) {
    Some(raw_value) =>
      match parse_decimal_int(raw_value) {
        Some(parsed) if parsed > 0 => parsed
        _ => @types.ONE_MIB_BYTES
      }
    None => @types.ONE_MIB_BYTES
  }
}

///|
pub fn Store::Store(
  nan_canonicalization~ : Bool = false,
  interpreter_limits~ : InterpreterLimits = InterpreterLimits::default(),
) -> Store raise RuntimeError {
  let native_execution = @wasmoon_jit.NativeExecutionState() catch {
    _ => raise OutOfMemory
  }

  {
    nan_canonicalization,
    interpreter_limits,
    interpreter_reentry_depth: 0,
    next_exception: 0,
    next_wrapped_extern: 0,
    gc_tracing_depth: 0,
    gc_in_collect: false,
    gc_trace: None,
    funcs: [],
    func_types: [],
    func_type_indices: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    tag_type_indices: [],
    tag_owners: [],
    exns: Map([]),
    heap: MarkSweepHeap(),
    c_heap: None,
    module_types: [],
    module_rec_groups: [],
    wrapped_externs: Map([]),
    func_owners: [],
    instances: [],
    jit_tables: [],
    jit_table_owners: [],
    wasi_mem_addr: None,
    wasi_ctx_handle: 0,
    native_execution,
    funcref_registry: StoreFuncrefRegistry::new(),
    native_types: StoreTypeRegistry::new(),
    native_exception_to_store: Map([]),
    store_exception_to_native: Map([]),
    suspended_executions: Map([]),
    next_suspended_execution_id: 0L,
    guest_continuations: Map([]),
    next_guest_continuation: 0L,
    pinned_gc_roots: Map([]),
    next_pinned_gc_roots_id: 0L,
    instantiation: None,
    closed: Ref(false),
  }
}

///|
/// Create a store with C heap enabled (for JIT mode)
pub fn Store::with_c_heap(
  nan_canonicalization~ : Bool = false,
  interpreter_limits~ : InterpreterLimits = InterpreterLimits::default(),
) -> Store raise RuntimeError {
  let native_execution = @wasmoon_jit.NativeExecutionState() catch {
    _ => raise OutOfMemory
  }
  let initial_capacity = c_heap_initial_capacity()
  let heap = @wasmoon_jit.CHeap(capacity=initial_capacity) catch {
    _ => raise OutOfMemory
  }
  let store : Store = {
    nan_canonicalization,
    interpreter_limits,
    interpreter_reentry_depth: 0,
    next_exception: 0,
    next_wrapped_extern: 0,
    gc_tracing_depth: 0,
    gc_in_collect: false,
    gc_trace: None,
    funcs: [],
    func_types: [],
    func_type_indices: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    tag_type_indices: [],
    tag_owners: [],
    exns: Map([]),
    heap: MarkSweepHeap(), // Used only when c_heap is None.
    c_heap: Some(heap),
    module_types: [],
    module_rec_groups: [],
    wrapped_externs: Map([]),
    func_owners: [],
    instances: [],
    jit_tables: [],
    jit_table_owners: [],
    wasi_mem_addr: None,
    wasi_ctx_handle: 0,
    native_execution,
    funcref_registry: StoreFuncrefRegistry::new(),
    native_types: StoreTypeRegistry::new(),
    native_exception_to_store: Map([]),
    store_exception_to_native: Map([]),
    suspended_executions: Map([]),
    next_suspended_execution_id: 0L,
    guest_continuations: Map([]),
    next_guest_continuation: 0L,
    pinned_gc_roots: Map([]),
    next_pinned_gc_roots_id: 0L,
    instantiation: None,
    closed: Ref(false),
  }
  store.native_execution.exceptions().enable_reclamation()
  store
}

///|
/// Release resources owned by this store and break host-function reference
/// cycles.
///
/// This operation is idempotent and terminal. Every native invocation must
/// have returned or been cancelled before the store is closed.
pub fn Store::close(self : Store) -> Unit {
  if self.closed.val {
    return
  }
  self.closed.val = true
  let suspended = self.suspended_executions.values().to_array()
  self.suspended_executions.clear()
  for cleanup in suspended {
    (cleanup.run)()
  }
  let guest_bodies = self.guest_continuations.values().to_array()
  self.guest_continuations.clear()
  for body in guest_bodies {
    (body.cancel)()
  }
  // Clear logical contents and release retained backing slots to break cycles.
  // Array.clear alone can retain references beyond the new length.
  self.guest_continuations.clear()
  self.native_execution.seal()
  for roots in self.pinned_gc_roots.values() {
    roots.active.val = false
  }
  self.pinned_gc_roots.clear()
  self.funcref_registry.clear()
  self.native_types.representatives.clear()
  self.native_types.representatives.shrink_to_fit()
  self.native_types.mappings.clear()
  self.native_types.parents.clear()
  self.native_types.parents.shrink_to_fit()
  self.native_types.views.clear()
  self.native_types.views.shrink_to_fit()
  self.native_types.entries.clear()
  if self.native_types.native_registry is Some(registry) {
    registry.clear()
    self.native_types.native_registry = None
  }
  self.native_types.heap_types.clear()
  self.funcs.clear()
  self.funcs.shrink_to_fit()
  self.func_types.clear()
  self.func_types.shrink_to_fit()
  self.func_type_indices.clear()
  self.func_type_indices.shrink_to_fit()
  self.func_owners.clear()
  self.func_owners.shrink_to_fit()
  self.instances.clear()
  self.instances.shrink_to_fit()
  self.tables.clear()
  self.tables.shrink_to_fit()
  for memory in self.mems {
    memory.close()
  }
  self.mems.clear()
  self.mems.shrink_to_fit()
  for global in self.globals {
    global.close()
  }
  self.globals.clear()
  self.globals.shrink_to_fit()
  self.tags.clear()
  self.tags.shrink_to_fit()
  self.tag_type_indices.clear()
  self.tag_type_indices.shrink_to_fit()
  self.tag_owners.clear()
  self.tag_owners.shrink_to_fit()
  self.native_exception_to_store.clear()
  self.store_exception_to_native.clear()
  self.exns.clear()
  self.heap.clear()
  if self.c_heap is Some(heap) {
    heap.free()
    self.c_heap = None
  }
  // These arrays are borrowed from the parsed module and may be reused by
  // other stores. Closing a store must only drop its own references.
  self.module_types = []
  self.module_rec_groups = []
  self.wrapped_externs.clear()
  for owner in self.jit_table_owners {
    match owner {
      Some(owner) => owner.close()
      None => ()
    }
  }
  self.jit_table_owners.clear()
  self.jit_table_owners.shrink_to_fit()
  self.jit_tables.clear()
  self.jit_tables.shrink_to_fit()
  self.wasi_mem_addr = None
  self.wasi_ctx_handle = 0
  self.instantiation = None
}

///|
fn Store::ensure_open(self : Store) -> Unit raise RuntimeError {
  if self.closed.val {
    raise StoreClosed
  }
}

///|
/// Return the Store-owned native invocation registry.
pub fn Store::native_execution_state(
  self : Store,
) -> @wasmoon_jit.NativeExecutionState {
  self.native_execution
}

///|
/// One Store-owned lease that keeps a snapshot of GC references alive.
///
/// Executors use this while an invocation is parked outside an active Wasm
/// stack. Releasing a lease is idempotent.
pub struct GcRootLease {
  priv mut store : Store?
  priv id : Int64
  priv active : Ref[Bool]
}

///|
pub fn Store::pin_gc_roots(
  self : Store,
  values : Array[@types.Value],
) -> GcRootLease {
  let id = self.next_pinned_gc_roots_id
  let active = Ref(true)
  self.next_pinned_gc_roots_id = self.next_pinned_gc_roots_id + 1L
  if self.closed.val {
    return { store: None, id, active: Ref(false), }
  }
  self.pinned_gc_roots.set(id, {
    values: values.copy(),
    active,
    guest_owned: false,
  })
  { store: Some(self), id, active, }
}

///|
pub fn GcRootLease::release(self : GcRootLease) -> Unit {
  self.active.val = false
  if self.store is Some(store) {
    store.pinned_gc_roots.remove(self.id)
  }
  self.store = None
}

///|
priv struct PinnedGcRoots {
  values : Array[@types.Value]
  active : Ref[Bool]
  mut guest_owned : Bool
} derive(Debug)

///|
fn GcRootLease::delegate_to_guest(self : GcRootLease) -> Unit {
  if self.store is Some(store) &&
    store.pinned_gc_roots.get(self.id) is Some(roots) {
    roots.guest_owned = true
  }
}

///|
/// Copy the explicit roots owned by this lease for continuation transfer.
pub fn GcRootLease::snapshot(self : GcRootLease) -> Array[@types.Value] {
  if self.store is Some(store) &&
    store.pinned_gc_roots.get(self.id) is Some(roots) {
    roots.values.copy()
  } else {
    []
  }
}

///|
/// Enable C heap for this store
pub fn Store::enable_c_heap(self : Store) -> Unit raise RuntimeError {
  self.ensure_open()
  if self.c_heap is None {
    guard self.heap.stats().live_objects == 0 else {
      raise HeapRepresentationInUse
    }
    let heap = @wasmoon_jit.CHeap(capacity=c_heap_initial_capacity()) catch {
      _ => raise OutOfMemory
    }
    self.c_heap = Some(heap)
    self.native_execution.exceptions().enable_reclamation()
  }
}

///|
/// Set module types and rec groups (needed for CHeap type lookups and canonical indices)
pub fn Store::set_module_types(
  self : Store,
  types : Array[@types.SubType],
  rec_groups~ : Array[Int32] = [],
) -> Unit raise RuntimeError {
  self.ensure_open()
  let old_types = self.module_types
  let old_rec_groups = self.module_rec_groups
  self.on_instantiation_rollback(fn() {
    self.module_types = old_types
    self.module_rec_groups = old_rec_groups
  })
  self.module_types = types
  self.module_rec_groups = rec_groups
}

///|
/// Get the C heap pointer (for JIT)
pub fn Store::get_c_heap_ptr(self : Store) -> @wasmoon_jit.GCHeapHandle {
  match self.c_heap {
    Some(heap) => heap.get_ptr()
    None => @wasmoon_jit.GCHeapHandle::null()
  }
}

///|
/// Check if C heap is enabled
pub fn Store::has_c_heap(self : Store) -> Bool {
  self.c_heap is Some(_)
}

///|
/// Wrap an internal GC value as an externref
/// Returns ExternRef with negative index pointing to wrapped_externs
pub fn Store::wrap_as_extern(
  self : Store,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  self.ensure_open()
  if self.next_wrapped_extern == 2147483647 {
    raise AllocationTooLarge
  }
  let idx = self.next_wrapped_extern
  self.next_wrapped_extern += 1
  self.wrapped_externs.set(idx, value)
  self.on_instantiation_rollback(fn() { self.wrapped_externs.remove(idx) })
  ExternRef(-1 - idx) // -1 for index 0, -2 for index 1, etc.
}

///|
/// Unwrap an externref back to its internal value
/// For host externrefs (positive index), returns the ExternRef unchanged
/// For wrapped internals (negative index), returns the original value
pub fn Store::unwrap_extern(
  self : Store,
  value : @types.Value,
) -> @types.Value raise RuntimeError {
  match value {
    ExternRef(idx) =>
      if idx < 0 {
        // Wrapped internal value
        let wrapped_idx = -1 - idx
        match self.wrapped_externs.get(wrapped_idx) {
          Some(value) => value
          None => raise UndefinedElement
        }
      } else {
        // Host externref - return as-is (it's already an internal representation)
        value
      }
    Null => Null
    _ => value
  }
}

///|
fn Store::alloc_func_inst(
  self : Store,
  func : FuncInst,
  func_type : @types.FuncType,
  type_idx : Int32,
  owner : FuncOwner,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let idx = self.push_allocation(self.funcs, func)
  self.push_allocation(self.func_types, func_type) |> ignore
  self.push_allocation(self.func_type_indices, type_idx) |> ignore
  self.push_allocation(self.func_owners, owner) |> ignore
  idx
}

///|
/// Allocate a WASM function with its type
pub fn Store::alloc_func(
  self : Store,
  func : @types.FunctionCode,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  self.alloc_func_inst(WasmFunc(func), func_type, type_idx, Unowned)
}

///|
/// Allocate a host function with its type
pub fn Store::alloc_host_func(
  self : Store,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  // Back-compat: old-style host funcs don't take a Caller.
  let wrapped : (Caller, Array[@types.Value]) -> Array[@types.Value] raise RuntimeError = (
    _caller,
    args,
  ) => func(args)
  self.alloc_func_inst(HostFunc(wrapped), func_type, type_idx, HostFunc)
}

///|
/// Allocate a host function that receives the caller context.
pub fn Store::alloc_host_func_with_caller(
  self : Store,
  func : (Caller, Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  self.alloc_func_inst(HostFunc(func), func_type, type_idx, HostFunc)
}

///|
/// Allocate an asynchronous host function with its type.
pub fn Store::alloc_async_host_func(
  self : Store,
  func : async (Array[@types.Value]) -> Array[@types.Value] raise Error,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  let wrapped : AsyncHostFunction = async fn(_caller, args) {
    try func(args) catch {
      error => Err(error)
    } noraise {
      values => Ok(values)
    }
  }
  self.alloc_func_inst(AsyncHostFunc(wrapped), func_type, type_idx, HostFunc)
}

///|
/// Allocate an asynchronous host function that receives the caller context.
pub fn Store::alloc_async_host_func_with_caller(
  self : Store,
  func : async (Caller, Array[@types.Value]) -> Array[@types.Value] raise Error,
  func_type~ : @types.FuncType = { params: [], results: [], },
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  let wrapped : AsyncHostFunction = async fn(caller, args) {
    try func(caller, args) catch {
      error => Err(error)
    } noraise {
      values => Ok(values)
    }
  }
  self.alloc_func_inst(AsyncHostFunc(wrapped), func_type, type_idx, HostFunc)
}

///|
/// Allocate a table in the store
/// Always creates a corresponding JIT table for cross-module sharing
pub fn Store::alloc_table(
  self : Store,
  table : Table,
  use_jit~ : Bool = true,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let owner = if use_jit {
    match
      @wasmoon_jit.JITTableOwner::try_alloc(
        table.size(),
        table.get_limits64().1,
      ) {
      Some(owner) => Some(owner)
      None => raise TableAllocationFailed
    }
  } else {
    None
  }
  let idx = self.tables.length()
  self.on_instantiation_rollback(fn() {
    if idx < self.jit_table_owners.length() {
      match self.jit_table_owners[idx] {
        Some(owner) => owner.close()
        None => ()
      }
    }
    self.tables.truncate(idx)
    self.tables.shrink_to_fit()
    self.jit_tables.truncate(idx)
    self.jit_tables.shrink_to_fit()
    self.jit_table_owners.truncate(idx)
    self.jit_table_owners.shrink_to_fit()
  })
  self.tables.push(table)

  self.jit_tables.push(owner.map(fn(owner) { owner.table() }))
  self.jit_table_owners.push(owner)
  idx
}

///|
pub fn Store::alloc_mem(self : Store, mem : Memory) -> Int32 raise RuntimeError {
  self.ensure_open()
  mem.require_desc_ptr() |> ignore
  let idx = self.mems.length()
  self.on_instantiation_rollback(fn() {
    if idx < self.mems.length() {
      self.mems[idx].close()
    }
    self.mems.truncate(idx)
    self.mems.shrink_to_fit()
  })
  self.mems.push(mem)
  idx
}

///|
pub fn Store::alloc_global(
  self : Store,
  global : GlobalInstance,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  self.push_allocation(self.globals, global)
}

///|
/// Allocate a tag with its type (params from FuncType, results ignored)
pub fn Store::alloc_tag(
  self : Store,
  tag_type : @types.FuncType,
  type_idx~ : Int32 = -1,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let idx = self.push_allocation(self.tags, tag_type)
  self.push_allocation(self.tag_type_indices, type_idx) |> ignore
  self.push_allocation(self.tag_owners, Unowned) |> ignore
  idx
}

///|
pub fn Store::get_tag_type(
  self : Store,
  idx : Int32,
) -> @types.FuncType raise RuntimeError {
  if idx < 0 || idx >= self.tags.length() {
    raise UndefinedElement
  }
  self.tags[idx]
}

///|
/// Get the original type index for a tag
pub fn Store::get_tag_type_idx(self : Store, tag_addr : Int32) -> Int32 {
  if tag_addr < 0 || tag_addr >= self.tag_type_indices.length() {
    return -1
  }
  self.tag_type_indices[tag_addr]
}

///|
/// Get the owner module for a tag
pub fn Store::get_tag_owner(self : Store, tag_addr : Int32) -> ModuleInstance? {
  if tag_addr < 0 || tag_addr >= self.tag_owners.length() {
    return None
  }
  match self.tag_owners[tag_addr] {
    Module(idx) =>
      if idx >= 0 && idx < self.instances.length() {
        Some(self.instances[idx])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Allocate an exception instance and return its index
pub fn Store::alloc_exn(
  self : Store,
  tag_addr : Int32,
  values : Array[@types.Value],
) -> Int32 raise RuntimeError {
  self.ensure_open()
  if self.next_exception == 2147483647 {
    raise AllocationTooLarge
  }
  let index = self.next_exception
  self.next_exception += 1
  self.exns.set(index, { tag_addr, values: values.copy(), })
  self.on_instantiation_rollback(fn() { self.exns.remove(index) })
  index
}

///|
/// Get an exception instance by index
pub fn Store::get_exn(
  self : Store,
  idx : Int32,
) -> ExnInstance raise RuntimeError {
  match self.exns.get(idx) {
    Some(exception) => exception
    None => raise UndefinedElement
  }
}

///|
/// Get the field type of a struct from module_types
fn Store::get_struct_field_type(
  self : Store,
  type_idx : Int32,
  field_idx : Int32,
  reference : Int32,
) -> @types.ValueType {
  guard self.gc_type_definition(reference, type_idx) is Some(definition) else {
    return I64
  }
  match definition.composite {
    Struct(st) =>
      if field_idx >= 0 && field_idx < st.fields.length() {
        match st.fields[field_idx].storage_type {
          Val(vt) => vt
          Packed(I8) | Packed(I16) => I32
        }
      } else {
        I64
      }
    _ => I64
  }
}

///|
/// Get the element type of an array from module_types
fn Store::get_array_elem_type(
  self : Store,
  type_idx : Int32,
  reference : Int32,
) -> @types.ValueType {
  guard self.gc_type_definition(reference, type_idx) is Some(definition) else {
    return I64
  }
  match definition.composite {
    Array(at) =>
      match at.element.storage_type {
        Val(vt) => vt
        Packed(I8) | Packed(I16) => I32
      }
    _ => I64
  }
}

///|
/// Allocate a struct instance and return its reference index
pub fn Store::alloc_struct(
  self : Store,
  type_idx : Int32,
  fields : Array[@types.Value],
  instance? : ModuleInstance,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let reference = match self.c_heap {
    Some(heap) => {
      let encoded = fields.map(value => self.encode_heap_value(value))
      heap.alloc_struct(type_idx, encoded) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    }
    None => self.heap.alloc_struct(type_idx, fields)
  }
  self.record_gc_type(reference, instance, type_idx)
  reference
}

///|
/// Allocate an array instance and return its reference index
pub fn Store::alloc_array(
  self : Store,
  type_idx : Int32,
  elements : Array[@types.Value],
  instance? : ModuleInstance,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let reference = match self.c_heap {
    Some(heap) => {
      let encoded = elements.map(value => self.encode_heap_value(value))
      heap.alloc_array_from_values(type_idx, encoded) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    }
    None => self.heap.alloc_array(type_idx, elements)
  }
  self.record_gc_type(reference, instance, type_idx)
  reference
}

///|
/// Get a struct field value
pub fn Store::struct_get(
  self : Store,
  struct_idx : Int32,
  field_idx : Int32,
) -> @types.Value raise RuntimeError {
  match self.c_heap {
    Some(heap) => {
      let type_idx = heap.get_type_idx(struct_idx)
      let field_type = self.get_struct_field_type(
        type_idx, field_idx, struct_idx,
      )
      self.decode_heap_value(
        field_type,
        heap.struct_get(struct_idx, field_idx, field_type),
      )
    }
    None => self.heap.struct_get(struct_idx, field_idx)
  }
}

///|
/// Set a struct field value
pub fn Store::struct_set(
  self : Store,
  struct_idx : Int32,
  field_idx : Int32,
  value : @types.Value,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) =>
      heap.struct_set(struct_idx, field_idx, self.encode_heap_value(value))
    None => self.heap.struct_set(struct_idx, field_idx, value)
  }
}

///|
/// Get array length
pub fn Store::array_len(
  self : Store,
  array_idx : Int32,
) -> Int32 raise RuntimeError {
  match self.c_heap {
    Some(heap) => heap.array_len(array_idx)
    None => self.heap.array_len(array_idx)
  }
}

///|
/// Get an array element value
pub fn Store::array_get(
  self : Store,
  array_idx : Int32,
  elem_idx : Int32,
) -> @types.Value raise RuntimeError {
  match self.c_heap {
    Some(heap) => {
      let type_idx = heap.get_type_idx(array_idx)
      let elem_type = self.get_array_elem_type(type_idx, array_idx)
      let value = heap.array_get(array_idx, elem_idx, elem_type) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
      self.decode_heap_value(elem_type, value)
    }
    None => self.heap.array_get(array_idx, elem_idx)
  }
}

///|
/// Set an array element value
pub fn Store::array_set(
  self : Store,
  array_idx : Int32,
  elem_idx : Int32,
  value : @types.Value,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) => {
      let encoded = self.encode_heap_value(value)
      heap.array_set(array_idx, elem_idx, encoded) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    }
    None => self.heap.array_set(array_idx, elem_idx, value)
  }
}

///|
/// Fill array elements with a value
pub fn Store::array_fill(
  self : Store,
  array_idx : Int32,
  offset : Int32,
  value : @types.Value,
  count : Int32,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) => {
      let encoded = self.encode_heap_value(value)
      heap.array_fill(array_idx, offset, encoded, count) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    }
    None => self.heap.array_fill(array_idx, offset, value, count)
  }
}

///|
/// Copy elements between arrays
pub fn Store::array_copy(
  self : Store,
  dst_idx : Int32,
  dst_offset : Int32,
  src_idx : Int32,
  src_offset : Int32,
  count : Int32,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) =>
      heap.array_copy(dst_idx, dst_offset, src_idx, src_offset, count) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    None =>
      self.heap.array_copy(dst_idx, dst_offset, src_idx, src_offset, count)
  }
}

///|
/// Get the type index of a GC object
pub fn Store::get_gc_type_idx(
  self : Store,
  idx : Int32,
) -> Int32 raise RuntimeError {
  match self.c_heap {
    Some(heap) => heap.get_type_idx(idx)
    None => self.heap.get_type_idx(idx)
  }
}

///|
/// Check if a GC object reference is valid
pub fn Store::is_gc_valid(self : Store, idx : Int32) -> Bool {
  match self.c_heap {
    Some(heap) => heap.is_valid(idx)
    None => self.heap.is_valid(idx)
  }
}

///|
pub fn Store::get_func_inst(
  self : Store,
  idx : Int32,
) -> FuncInst raise RuntimeError {
  if idx < 0 || idx >= self.funcs.length() {
    raise UndefinedElement
  }
  self.funcs[idx]
}

///|
/// Get function instance by store address (returns None if out of range).
///
/// This is useful for embedding/JIT callbacks that must not raise.
pub fn Store::get_func_inst_opt(self : Store, idx : Int32) -> FuncInst? {
  if idx < 0 || idx >= self.funcs.length() {
    None
  } else {
    Some(self.funcs[idx])
  }
}

///|
/// Get function type by store address
pub fn Store::get_func_type(
  self : Store,
  idx : Int32,
) -> @types.FuncType raise RuntimeError {
  if idx < 0 || idx >= self.func_types.length() {
    raise UndefinedElement
  }
  self.func_types[idx]
}

///|
/// Get function type by store address (returns None if out of range).
///
/// This is useful for embedding/JIT callbacks that must not raise.
pub fn Store::get_func_type_opt(self : Store, idx : Int32) -> @types.FuncType? {
  if idx < 0 || idx >= self.func_types.length() {
    None
  } else {
    Some(self.func_types[idx])
  }
}

///|
/// Get function type index by store address (for structural comparison)
pub fn Store::get_func_type_idx(self : Store, idx : Int32) -> Int32 {
  if idx < 0 || idx >= self.func_type_indices.length() {
    -1
  } else {
    self.func_type_indices[idx]
  }
}

///|
/// Get canonical type index for a function by store address
/// Returns the canonical type index from the function's owning module
/// Returns -1 if the function or owner is not found
pub fn Store::get_func_canonical_type_idx(
  self : Store,
  func_addr : Int32,
) -> Int32 {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return -1
  }
  let owner_idx = match self.func_owners[func_addr] {
    Module(idx) => idx
    HostFunc => {
      // Host function types are declared in the importing module's type graph.
      for instance in self.instances {
        for index, address in instance.func_addrs {
          if address == func_addr && index < instance.func_type_indices.length() {
            let type_index = instance.func_type_indices[index]
            return self.native_types.register(instance)[type_index]
          }
        }
      }
      return -1
    }
    Unowned => return -1
  }
  if owner_idx >= self.instances.length() {
    return -1
  }
  let instance = self.instances[owner_idx]
  let type_idx = self.func_type_indices[func_addr]
  if type_idx < 0 || type_idx >= instance.canonical_type_indices.length() {
    return -1
  }
  self.native_types.register(instance)[type_idx]
}

///|
/// Get function code for a store address that is known to refer to a Wasm function.
pub fn Store::get_func(
  self : Store,
  idx : Int32,
) -> @types.FunctionCode raise RuntimeError {
  match self.get_func_inst(idx) {
    WasmFunc(code) => code
    HostFunc(_) | AsyncHostFunc(_) => raise TypeMismatch // Cannot get code from host function
  }
}

///|
pub fn Store::get_table(self : Store, idx : Int32) -> Table raise RuntimeError {
  if idx < 0 || idx >= self.tables.length() {
    raise UndefinedElement
  }
  self.tables[idx]
}

///|
/// Get the JIT table corresponding to a runtime table (if exists)
pub fn Store::get_jit_table(
  self : Store,
  idx : Int32,
) -> @wasmoon_jit.JITTable? {
  if idx < 0 || idx >= self.jit_tables.length() {
    return None
  }
  self.jit_tables[idx]
}

///|
pub fn Store::get_mem(self : Store, idx : Int32) -> Memory raise RuntimeError {
  if idx < 0 || idx >= self.mems.length() {
    raise UndefinedElement
  }
  self.mems[idx]
}

///|
/// Get memory by index, rejecting missing memories without fabricating a handle.
pub fn Store::get_memory(
  self : Store,
  idx : Int32,
) -> Memory raise RuntimeError {
  self.get_mem(idx)
}

///|
/// Get WASI module's memory
/// Uses the stored wasi_mem_addr if set, otherwise falls back to index 0
pub fn Store::get_wasi_memory(self : Store) -> Memory raise RuntimeError {
  match self.wasi_mem_addr {
    Some(addr) => self.get_memory(addr)
    None => self.get_memory(0)
  }
}

///|
/// Set the current WASI module's memory address
/// Should be called after instantiating a module that uses WASI
pub fn Store::set_wasi_mem_addr(
  self : Store,
  addr : Int32,
) -> Unit raise RuntimeError {
  self.ensure_open()
  let old_addr = self.wasi_mem_addr
  self.on_instantiation_rollback(fn() { self.wasi_mem_addr = old_addr })
  self.wasi_mem_addr = Some(addr)
}

///|
/// Get the WASI context handle (for WAST runner to retrieve WASI context)
pub fn Store::get_wasi_ctx_handle(self : Store) -> Int32 {
  self.wasi_ctx_handle
}

///|
/// Set the WASI context handle (for WAST runner to store WASI context)
pub fn Store::set_wasi_ctx_handle(
  self : Store,
  handle : Int32,
) -> Unit raise RuntimeError {
  self.ensure_open()
  self.wasi_ctx_handle = handle
}

///|
pub fn Store::get_global(
  self : Store,
  idx : Int32,
) -> GlobalInstance raise RuntimeError {
  if idx < 0 || idx >= self.globals.length() {
    raise UndefinedElement
  }
  self.globals[idx]
}

///|
/// Register a module instance and set ownership for its functions
/// Only sets ownership for functions that don't already have an owner
/// (imported functions already belong to their original module)
pub fn Store::register_instance(
  self : Store,
  instance : ModuleInstance,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let instance_idx = self.instances.length()
  let owned_funcs : Array[Int32] = []
  let owned_tags : Array[Int32] = []
  instance.store_idx = instance_idx
  self.instances.push(instance)
  // Set ownership only for unowned WASM functions
  // HostFunc and already-owned functions are not changed
  for func_addr in instance.func_addrs {
    if func_addr >= 0 &&
      func_addr < self.func_owners.length() &&
      self.func_owners[func_addr] == Unowned {
      self.func_owners[func_addr] = Module(instance_idx)
      owned_funcs.push(func_addr)
    }
  }
  // Set ownership for unowned tags
  for tag_addr in instance.tag_addrs {
    if tag_addr >= 0 &&
      tag_addr < self.tag_owners.length() &&
      self.tag_owners[tag_addr] == Unowned {
      self.tag_owners[tag_addr] = Module(instance_idx)
      owned_tags.push(tag_addr)
    }
  }
  self.on_instantiation_rollback(fn() {
    for func_addr in owned_funcs {
      if func_addr < self.func_owners.length() {
        self.func_owners[func_addr] = Unowned
      }
    }
    for tag_addr in owned_tags {
      if tag_addr < self.tag_owners.length() {
        self.tag_owners[tag_addr] = Unowned
      }
    }
    instance.store_idx = -1
    self.native_types.mappings.remove(instance_idx)
    self.instances.truncate(instance_idx)
    self.instances.shrink_to_fit()
  })
  instance_idx
}

///|
/// Get the owning module instance for a function address
pub fn Store::get_func_owner(
  self : Store,
  func_addr : Int32,
) -> ModuleInstance? {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return None
  }
  match self.func_owners[func_addr] {
    Module(idx) =>
      if idx < self.instances.length() {
        Some(self.instances[idx])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Get the owning module instance index for a function address
/// Returns -1 if no owner (host function or unowned)
pub fn Store::get_func_owner_idx(self : Store, func_addr : Int32) -> Int32 {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return -1
  }
  match self.func_owners[func_addr] {
    Module(idx) => idx
    _ => -1
  }
}

// ============================================================
// Garbage Collection
// ============================================================

///|
/// Collect the transitive object roots of this Store and explicit host roots.
pub fn Store::collect_roots(
  self : Store,
  additional_roots : Array[@types.Value],
) -> Array[@types.Value] {
  self.trace_gc_roots(additional_roots).objects
}

///|
/// Reclaim unreachable objects and temporary reference handles.
/// Host Values held outside guest execution must be pinned or supplied here.
pub fn Store::collect_garbage(
  self : Store,
  additional_roots~ : Array[@types.Value] = [],
) -> Int32 {
  if self.gc_in_collect {
    return -1
  }
  self.gc_in_collect = true
  defer {
    self.gc_in_collect = false
  }
  match self.c_heap {
    Some(heap) => {
      self.begin_gc_tracing()
      defer self.end_gc_tracing()
      let trace = self.trace_gc_roots(additional_roots)
      self.gc_trace = Some(trace)
      let roots = self.native_trace_roots(trace) catch {
        _ => {
          self.gc_trace = None
          return -1
        }
      }
      heap.collect_raw(roots)
    }
    None => {
      let trace = self.trace_gc_roots(additional_roots)
      if trace.failed {
        return -1
      }
      let collected = self.heap.collect(trace.objects)
      self.release_unreachable_handles(trace)
      collected
    }
  }
}

///|
/// Check if GC should be triggered based on heap usage
/// Returns true if heap usage exceeds the threshold (default 75%)
pub fn Store::should_collect(self : Store, threshold~ : Double = 0.75) -> Bool {
  match self.c_heap {
    Some(heap) => heap.should_collect(threshold~)
    None => false
  }
}

///|
/// Perform garbage collection if heap usage exceeds the threshold
/// Returns the number of objects collected, or 0 if GC was not triggered
pub fn Store::maybe_collect(
  self : Store,
  additional_roots~ : Array[@types.Value] = [],
  threshold~ : Double = 0.75,
) -> Int32 {
  if self.should_collect(threshold~) {
    self.collect_garbage(additional_roots~)
  } else {
    0
  }
}

///|
/// Get GC statistics for the C heap
/// Returns (size, capacity, object_count, total_allocations, total_collections)
/// or (0, 0, 0, 0, 0) if no C heap is enabled
pub fn Store::get_gc_stats(self : Store) -> (Int64, Int64, Int32, Int32, Int32) {
  match self.c_heap {
    Some(heap) =>
      (
        heap.get_size(),
        heap.get_capacity(),
        heap.get_object_count(),
        heap.get_total_allocations(),
        heap.get_total_collections(),
      )
    None => (0L, 0L, 0, 0, 0)
  }
}

///|
/// Import shared memory with ownership independent of the source Store.
/// Closing either Store invalidates only its own Memory handle.
pub fn Store::alloc_shared_mem(
  self : Store,
  memory : Memory,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  let owned = memory.share()
  errdefer owned.close()
  self.alloc_mem(owned)
}

///|
fn GcRootLease::retain_for_host(self : GcRootLease) -> Unit {
  if self.store is Some(store) &&
    store.pinned_gc_roots.get(self.id) is Some(roots) {
    roots.guest_owned = false
  }
}
