///|
/// The store contains all global runtime state
#derive(Debug)
pub struct Store {
  nan_canonicalization : Bool
  interpreter_limits : InterpreterLimits
  resource_budget : ResourceBudget?
  priv mut execution_scope : ExecutionScope?
  priv instance_leases : Array[ResourceLease]
  priv mut gc_in_collect : Bool
  priv mut interpreter_reentry_depth : Int32
  priv references : StoreReferences
  priv funcs : Array[StoredFunction]
  priv func_types : Array[@types.FuncType] // Type of each function
  priv func_type_indices : Array[Int32] // Original type index for structural comparison
  priv tables : Array[Table]
  priv mems : Array[Memory]
  priv globals : Array[GlobalInstance]
  priv tag_lifetimes : Array[Ref[Bool]]
  priv tags : Array[@types.FuncType] // Tag types (params only, no results)
  priv tag_type_indices : Array[Int32] // Original type index for each tag
  priv tag_owners : Array[FuncOwner] // Owner module for each tag
  priv heap : MarkSweepHeap // GC heap for struct and array instances (interpreter mode)
  // Module types for managed GC type equivalence
  priv mut module_types : Array[@types.SubType]
  // Module rec groups for canonical type index computation
  priv mut module_rec_groups : Array[Int32]
  // Internal values wrapped as externref via extern.convert_any
  // Accessed using negative ExternRef indices: ExternRef(-1-i) = wrapped_externs[i]
  // Maps function address to its owning module instance
  // Used for cross-module call context switching
  priv func_owners : Array[FuncOwner]
  // Registered module instances by their address/index
  priv instances : Array[ModuleInstance]
  // Current WASI module's memory address (for interpreter mode WASI callbacks)
  // WASI callbacks use this to access the correct memory instead of hardcoded index 0
  priv mut wasi_mem_addr : Int32?
  // Opaque WASI context handle (for WAST runner to store WASI context)
  // This avoids circular dependency between runtime and wasi packages
  priv mut wasi_ctx_handle : Int32
  priv funcref_registry : StoreFuncrefRegistry
  priv native_types : StoreTypeRegistry
  priv suspended_executions : Map[Int64, SuspendedExecutionCleanup]
  priv mut next_suspended_execution_id : Int64
  priv mut guest_continuations : Map[Int64, GuestContinuationBody]
  priv mut next_guest_continuation : Int64
  priv mut pinned_gc_roots : Map[Int64, PinnedGcRoots]
  priv mut next_pinned_gc_roots_id : Int64
  priv mut instantiation : RollbackRegistrar?
  priv closed : Ref[Bool]
}

///|
fn Store::register_rollback(
  self : Store,
  registrar : RollbackRegistrar,
) -> Unit {
  self.register_managed_rollback(registrar)
}

///|
pub fn Store::Store(
  nan_canonicalization~ : Bool = false,
  interpreter_limits~ : InterpreterLimits = InterpreterLimits::default(),
  resource_budget~ : ResourceBudget? = None,
) -> Store {
  let closed = Ref(false)
  let tags : Array[@types.FuncType] = []
  let managed_heap = MarkSweepHeap(resource_budget~)
  let funcref_registry = StoreFuncrefRegistry::new()
  let references = StoreReferences::new(
    resource_budget,
    closed,
    tags,
    managed_heap,
    funcref_registry,
    Empty,
  )
  {
    nan_canonicalization,
    interpreter_limits,
    resource_budget,
    execution_scope: None,
    instance_leases: [],
    interpreter_reentry_depth: 0,
    gc_in_collect: false,
    funcs: [],
    func_types: [],
    func_type_indices: [],
    tables: [],
    mems: [],
    globals: [],
    tags,
    tag_lifetimes: [],
    tag_type_indices: [],
    tag_owners: [],
    heap: managed_heap,
    module_types: [],
    module_rec_groups: [],
    func_owners: [],
    instances: [],
    wasi_mem_addr: None,
    wasi_ctx_handle: 0,
    funcref_registry,
    native_types: StoreTypeRegistry::new(),
    suspended_executions: Map([]),
    next_suspended_execution_id: 0L,
    guest_continuations: Map([]),
    next_guest_continuation: 0L,
    pinned_gc_roots: Map([]),
    next_pinned_gc_roots_id: 0L,
    instantiation: None,
    closed,
    references,
  }
}

///|
/// Release resources owned by this store and break host-function reference
/// cycles.
///
/// This operation is idempotent and terminal. Every native invocation must
/// have returned or been cancelled before the store is closed.
pub fn Store::close(self : Store) -> Unit {
  guard self.begin_close() else { return }
  self.close_roots_and_types()
  self.native_types.native_layout_count = 0
  self.invalidate_functions()
  for lease in self.instance_leases {
    lease.release()
  }
  self.close_instances()
  self.references.exns.clear()
  for pair in self.references.auxiliary_leases.values() {
    pair.0.release()
    pair.1.release()
  }
  self.references.auxiliary_leases.clear()
  self.heap.close()

  self.clear_module_references()
  self.finish_close()
}

///|
fn Store::prepare_table_backing(
  _self : Store,
  _table : Table,
  _use_jit : Bool,
) -> Unit {
  ()
}

///|
fn Store::discard_table_backing(
  _self : Store,
  table : Table,
  _idx : Int32,
) -> Unit {
  table.close()
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
  if instance is Some(instance) {
    self.check_instance(instance)
  }
  let reference = self.heap.alloc_struct(type_idx, fields)
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
  if instance is Some(instance) {
    self.check_instance(instance)
  }
  let reference = self.heap.alloc_array(type_idx, elements)
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
  self.ensure_open()
  self.heap.struct_get(struct_idx, field_idx)
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
  self.heap.struct_set(struct_idx, field_idx, value)
}

///|
/// Get array length
pub fn Store::array_len(
  self : Store,
  array_idx : Int32,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  self.heap.array_len(array_idx)
}

///|
/// Get an array element value
pub fn Store::array_get(
  self : Store,
  array_idx : Int32,
  elem_idx : Int32,
) -> @types.Value raise RuntimeError {
  self.ensure_open()
  self.heap.array_get(array_idx, elem_idx)
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
  self.heap.array_set(array_idx, elem_idx, value)
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
  self.heap.array_fill(array_idx, offset, value, count)
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
  self.heap.array_copy(dst_idx, dst_offset, src_idx, src_offset, count)
}

///|
/// Get the type index of a GC object
pub fn Store::get_gc_type_idx(
  self : Store,
  idx : Int32,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  self.heap.get_type_idx(idx)
}

///|
/// Check if a GC object reference is valid
pub fn Store::is_gc_valid(self : Store, idx : Int32) -> Bool {
  self.heap.is_valid(idx)
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
  let trace = self.trace_gc_roots(additional_roots)
  if trace.failed {
    return -1
  }
  let collected = self.heap.collect(trace.objects)
  self.release_unreachable_handles(trace)
  collected
}

///|
/// Check if GC should be triggered based on heap usage
/// Returns true if heap usage exceeds the threshold (default 75%)
pub fn Store::should_collect(_self : Store, threshold~ : Double = 0.75) -> Bool {
  ignore(threshold)
  false
}

///|
/// Get GC statistics for the C heap
/// Returns (size, capacity, object_count, total_allocations, total_collections)
/// or (0, 0, 0, 0, 0) if no C heap is enabled
pub fn Store::get_gc_stats(
  _self : Store,
) -> (Int64, Int64, Int32, Int32, Int32) {
  (0L, 0L, 0, 0, 0)
}

///|
/// Check if C heap is enabled
pub fn Store::has_c_heap(_self : Store) -> Bool {
  false
}

///|
let _native_env_import : Unit = ignore(@env.get_env_var)
