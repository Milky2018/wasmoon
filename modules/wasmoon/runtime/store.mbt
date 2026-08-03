///|
/// Exception instance - represents a caught exception
pub struct ExnInstance {
  tag_addr : Int // Which tag was thrown
  values : Array[@types.Value] // Exception values
} derive(Debug)

///|
/// Represents the ownership status of a function in the store
pub(all) enum FuncOwner {
  HostFunc // Host function - never has an owner module
  Unowned // WASM function not yet assigned to a module
  Module(Int) // WASM function owned by module at given index
} derive(Debug, Eq)

///|
/// The store contains all global runtime state
pub struct Store {
  priv mut state : StoreState
  heap : MarkSweepHeap // GC heap for struct and array instances (interpreter mode)
  // C-managed GC heap for JIT mode (None = use MarkSweepHeap)
  mut c_heap : @wasmoon_jit.CHeap?
  // Opaque WASI context handle (for WAST runner to store WASI context)
  // This avoids circular dependency between runtime and wasi packages
  mut wasi_ctx_handle : Int
  // Native invocation/fiber lifetimes belong to the Store, not a JIT module.
  native_execution : @wasmoon_jit.NativeExecutionState
  priv funcref_registry : StoreFuncrefRegistry
  priv mut instantiation : StoreBuildState?
  priv closed : Ref[Bool]
} derive(Debug)

///|
/// Read-only allocation counts for diagnostics and failure-baseline tests.
pub struct StoreAllocationStats {
  funcs : Int
  func_types : Int
  func_type_indices : Int
  func_owners : Int
  tables : Int
  jit_tables : Int
  mems : Int
  globals : Int
  tags : Int
  tag_type_indices : Int
  tag_owners : Int
  exns : Int
  wrapped_externs : Int
  instances : Int
} derive(Debug, Eq)

///|
pub fn Store::allocation_stats(self : Store) -> StoreAllocationStats {
  let state = self.state
  {
    funcs: state.funcs.length(),
    func_types: state.func_types.length(),
    func_type_indices: state.func_type_indices.length(),
    func_owners: state.func_owners.length(),
    tables: state.tables.length(),
    jit_tables: state.jit_tables.length(),
    mems: state.mems.length(),
    globals: state.globals.length(),
    tags: state.tags.length(),
    tag_type_indices: state.tag_type_indices.length(),
    tag_owners: state.tag_owners.length(),
    exns: state.exns.length(),
    wrapped_externs: state.wrapped_externs.length(),
    instances: state.instances.length(),
  }
}

///|
pub fn Store::get_instance_opt(self : Store, index : Int) -> ModuleInstance? {
  self.current_state().instances.get(index)
}

///|
/// Return an isolated snapshot of the active module type table.
pub fn Store::module_types_snapshot(self : Store) -> Array[@types.SubType] {
  self.current_state().module_types.copy()
}

///|
/// Optional C heap initial capacity override (bytes)
const GC_HEAP_CAPACITY_ENV : String = "WASMOON_GC_HEAP_CAPACITY"

///|
fn parse_decimal_int(value : String) -> Int? {
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
fn c_heap_initial_capacity() -> Int {
  match @sys.get_env_var(GC_HEAP_CAPACITY_ENV) {
    Some(raw_value) =>
      match parse_decimal_int(raw_value) {
        Some(parsed) if parsed > 0 => parsed
        _ => @types.ONE_MIB_BYTES
      }
    None => @types.ONE_MIB_BYTES
  }
}

///|
pub fn Store::Store() -> Store {
  {
    state: StoreState::new(),
    heap: MarkSweepHeap(),
    c_heap: None,
    wasi_ctx_handle: 0,
    native_execution: NativeExecutionState(),
    funcref_registry: StoreFuncrefRegistry::new(),
    instantiation: None,
    closed: Ref(false),
  }
}

///|
/// Create a store with C heap enabled (for JIT mode)
pub fn Store::with_c_heap() -> Store {
  let initial_capacity = c_heap_initial_capacity()
  {
    state: StoreState::new(),
    heap: MarkSweepHeap(), // Used only when c_heap is None.
    c_heap: Some(CHeap(capacity=initial_capacity)),
    wasi_ctx_handle: 0,
    native_execution: NativeExecutionState(),
    funcref_registry: StoreFuncrefRegistry::new(),
    instantiation: None,
    closed: Ref(false),
  }
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
  if self.instantiation is Some(frame) {
    frame.discard()
  }
  self.closed.val = true
  self.native_execution.seal()
  self.funcref_registry.clear()
  let state = self.state
  state.funcs.clear()
  state.func_types.clear()
  state.func_type_indices.clear()
  state.func_owners.clear()
  state.instances.clear()
  state.tables.clear()
  for memory in state.mems {
    memory.close()
  }
  state.mems.clear()
  state.globals.clear()
  state.tags.clear()
  state.tag_type_indices.clear()
  state.tag_owners.clear()
  state.exns.clear()
  self.heap.clear()
  if self.c_heap is Some(heap) {
    heap.free()
    self.c_heap = None
  }
  state.module_types.clear()
  state.module_rec_groups.clear()
  state.wrapped_externs.clear()
  for owner in state.jit_table_owners {
    match owner {
      Some(owner) => owner.close()
      None => ()
    }
  }
  state.jit_table_owners.clear()
  state.jit_tables.clear()
  state.wasi_mem_addr = None
  self.wasi_ctx_handle = 0
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
/// Enable C heap for this store
pub fn Store::enable_c_heap(self : Store) -> Unit raise RuntimeError {
  self.ensure_open()
  if self.c_heap is None {
    self.c_heap = Some(CHeap(capacity=c_heap_initial_capacity()))
  }
}

///|
/// Set module types and rec groups (needed for CHeap type lookups and canonical indices)
pub fn Store::set_module_types(
  self : Store,
  types : Array[@types.SubType],
  rec_groups? : Array[Int] = [],
) -> Unit raise RuntimeError {
  self.ensure_open()
  let state = self.current_state()
  state.module_types = types
  state.module_rec_groups = rec_groups
}

///|
/// Get the C heap pointer (for JIT)
pub fn Store::get_c_heap_ptr(self : Store) -> Int64 {
  match self.c_heap {
    Some(heap) => heap.get_ptr()
    None => 0L
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
  let idx = push_and_index(self.current_state().wrapped_externs, value)
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
        match self.current_state().wrapped_externs.get(wrapped_idx) {
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
/// Allocate a WASM function with its type
pub fn Store::alloc_func(
  self : Store,
  func : @types.FunctionCode,
  func_type? : @types.FuncType = { params: [], results: [] },
  type_idx? : Int = -1,
) -> Int raise RuntimeError {
  self.ensure_open()
  self.alloc_func_inst(WasmFunc(func), func_type, type_idx, Unowned)
}

///|
/// Allocate a host function with its type
pub fn Store::alloc_host_func(
  self : Store,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type? : @types.FuncType = { params: [], results: [] },
  type_idx? : Int = -1,
) -> Int raise RuntimeError {
  self.ensure_open()
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
  func_type? : @types.FuncType = { params: [], results: [] },
  type_idx? : Int = -1,
) -> Int raise RuntimeError {
  self.ensure_open()
  self.alloc_func_inst(HostFunc(func), func_type, type_idx, HostFunc)
}

///|
/// Allocate a table in the store
/// Always creates a corresponding JIT table for cross-module sharing
pub fn Store::alloc_table(
  self : Store,
  table : Table,
  use_jit? : Bool = true,
) -> Int raise RuntimeError {
  self.ensure_open()
  let (jit_table, jit_table_owner) : (
    @wasmoon_jit.JITTable?,
    @wasmoon_jit.JITTableOwner?,
    // Create corresponding JIT table (always enabled for cross-module sharing)
  ) = if use_jit {
    let (min, max) = table.get_limits()
    match @wasmoon_jit.JITTableOwner::try_alloc(min, max) {
      Some(owner) => (Some(owner.table()), Some(owner))
      None => (None, None)
    }
  } else {
    (None, None)
  }
  let state = self.current_state()
  let idx = push_and_index(state.tables, table)
  state.jit_tables.push(jit_table)
  state.jit_table_owners.push(jit_table_owner)
  idx
}

///|
pub fn Store::alloc_mem(self : Store, mem : Memory) -> Int raise RuntimeError {
  self.ensure_open()
  push_and_index(self.current_state().mems, mem)
}

///|
pub fn Store::alloc_global(
  self : Store,
  global : GlobalInstance,
) -> Int raise RuntimeError {
  self.ensure_open()
  push_and_index(self.current_state().globals, global)
}

///|
/// Allocate a tag with its type (params from FuncType, results ignored)
pub fn Store::alloc_tag(
  self : Store,
  tag_type : @types.FuncType,
  type_idx? : Int = -1,
) -> Int raise RuntimeError {
  self.ensure_open()
  let state = self.current_state()
  let idx = push_and_index(state.tags, tag_type)
  state.tag_type_indices.push(type_idx)
  state.tag_owners.push(Unowned)
  idx
}

///|
pub fn Store::get_tag_type(
  self : Store,
  idx : Int,
) -> @types.FuncType raise RuntimeError {
  match self.current_state().tags.get(idx) {
    Some(tag) => tag
    None => raise UndefinedElement
  }
}

///|
/// Get the original type index for a tag
pub fn Store::get_tag_type_idx(self : Store, tag_addr : Int) -> Int {
  match self.current_state().tag_type_indices.get(tag_addr) {
    Some(type_idx) => type_idx
    None => -1
  }
}

///|
/// Get the owner module for a tag
pub fn Store::get_tag_owner(self : Store, tag_addr : Int) -> ModuleInstance? {
  match self.tag_owner_at(tag_addr) {
    Module(idx) => self.instance_at(idx)
    _ => None
  }
}

///|
/// Allocate an exception instance and return its index
pub fn Store::alloc_exn(
  self : Store,
  tag_addr : Int,
  values : Array[@types.Value],
) -> Int raise RuntimeError {
  self.ensure_open()
  push_and_index(self.current_state().exns, { tag_addr, values })
}

///|
/// Get an exception instance by index
pub fn Store::get_exn(
  self : Store,
  idx : Int,
) -> ExnInstance raise RuntimeError {
  match self.current_state().exns.get(idx) {
    Some(exn) => exn
    None => raise UndefinedElement
  }
}

///|
/// Get the field type of a struct from module_types
fn Store::get_struct_field_type(
  self : Store,
  type_idx : Int,
  field_idx : Int,
) -> @types.ValueType {
  let module_types = self.current_state().module_types
  if type_idx < 0 || type_idx >= module_types.length() {
    return I64 // Fallback
  }
  match module_types[type_idx].composite {
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
fn Store::get_array_elem_type(self : Store, type_idx : Int) -> @types.ValueType {
  let module_types = self.current_state().module_types
  if type_idx < 0 || type_idx >= module_types.length() {
    return I64
  }
  match module_types[type_idx].composite {
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
  type_idx : Int,
  fields : Array[@types.Value],
) -> Int raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) =>
      heap.alloc_struct(type_idx, fields) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    None => self.heap.alloc_struct(type_idx, fields)
  }
}

///|
/// Allocate an array instance and return its reference index
pub fn Store::alloc_array(
  self : Store,
  type_idx : Int,
  elements : Array[@types.Value],
) -> Int raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) =>
      heap.alloc_array_from_values(type_idx, elements) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    None => self.heap.alloc_array(type_idx, elements)
  }
}

///|
/// Get a struct field value
pub fn Store::struct_get(
  self : Store,
  struct_idx : Int,
  field_idx : Int,
) -> @types.Value raise RuntimeError {
  match self.c_heap {
    Some(heap) => {
      let type_idx = heap.get_type_idx(struct_idx)
      let field_type = self.get_struct_field_type(type_idx, field_idx)
      heap.struct_get(struct_idx, field_idx, field_type)
    }
    None => self.heap.struct_get(struct_idx, field_idx)
  }
}

///|
/// Set a struct field value
pub fn Store::struct_set(
  self : Store,
  struct_idx : Int,
  field_idx : Int,
  value : @types.Value,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) => heap.struct_set(struct_idx, field_idx, value)
    None => self.heap.struct_set(struct_idx, field_idx, value)
  }
}

///|
/// Get array length
pub fn Store::array_len(
  self : Store,
  array_idx : Int,
) -> Int raise RuntimeError {
  match self.c_heap {
    Some(heap) => heap.array_len(array_idx)
    None => self.heap.array_len(array_idx)
  }
}

///|
/// Get an array element value
pub fn Store::array_get(
  self : Store,
  array_idx : Int,
  elem_idx : Int,
) -> @types.Value raise RuntimeError {
  match self.c_heap {
    Some(heap) => {
      let type_idx = heap.get_type_idx(array_idx)
      let elem_type = self.get_array_elem_type(type_idx)
      heap.array_get(array_idx, elem_idx, elem_type) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    }
    None => self.heap.array_get(array_idx, elem_idx)
  }
}

///|
/// Set an array element value
pub fn Store::array_set(
  self : Store,
  array_idx : Int,
  elem_idx : Int,
  value : @types.Value,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) =>
      heap.array_set(array_idx, elem_idx, value) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    None => self.heap.array_set(array_idx, elem_idx, value)
  }
}

///|
/// Fill array elements with a value
pub fn Store::array_fill(
  self : Store,
  array_idx : Int,
  offset : Int,
  value : @types.Value,
  count : Int,
) -> Unit raise RuntimeError {
  self.ensure_open()
  match self.c_heap {
    Some(heap) =>
      heap.array_fill(array_idx, offset, value, count) catch {
        OutOfBoundsArrayAccess => raise OutOfBoundsArrayAccess
        NullReference => raise NullReference
        OutOfMemory => raise OutOfMemory
      }
    None => self.heap.array_fill(array_idx, offset, value, count)
  }
}

///|
/// Copy elements between arrays
pub fn Store::array_copy(
  self : Store,
  dst_idx : Int,
  dst_offset : Int,
  src_idx : Int,
  src_offset : Int,
  count : Int,
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
  idx : Int,
) -> Int raise RuntimeError {
  match self.c_heap {
    Some(heap) => heap.get_type_idx(idx)
    None => self.heap.get_type_idx(idx)
  }
}

///|
/// Check if a GC object reference is valid
pub fn Store::is_gc_valid(self : Store, idx : Int) -> Bool {
  match self.c_heap {
    Some(heap) => heap.is_valid(idx)
    None => self.heap.is_valid(idx)
  }
}

///|
pub fn Store::get_func_inst(
  self : Store,
  idx : Int,
) -> FuncInst raise RuntimeError {
  match self.current_state().funcs.get(idx) {
    Some(func) => func
    None => raise UndefinedElement
  }
}

///|
/// Get function instance by store address (returns None if out of range).
///
/// This is useful for embedding/JIT callbacks that must not raise.
pub fn Store::get_func_inst_opt(self : Store, idx : Int) -> FuncInst? {
  self.current_state().funcs.get(idx)
}

///|
/// Get function type by store address
pub fn Store::get_func_type(
  self : Store,
  idx : Int,
) -> @types.FuncType raise RuntimeError {
  match self.current_state().func_types.get(idx) {
    Some(func_type) => func_type
    None => raise UndefinedElement
  }
}

///|
/// Get function type by store address (returns None if out of range).
///
/// This is useful for embedding/JIT callbacks that must not raise.
pub fn Store::get_func_type_opt(self : Store, idx : Int) -> @types.FuncType? {
  self.current_state().func_types.get(idx)
}

///|
/// Get function type index by store address (for structural comparison)
pub fn Store::get_func_type_idx(self : Store, idx : Int) -> Int {
  match self.current_state().func_type_indices.get(idx) {
    Some(type_idx) => type_idx
    None => -1
  }
}

///|
/// Get canonical type index for a function by store address
/// Returns the canonical type index from the function's owning module
/// Returns -1 if the function or owner is not found
pub fn Store::get_func_canonical_type_idx(self : Store, func_addr : Int) -> Int {
  let owner_idx = match self.func_owner_at(func_addr) {
    Module(idx) => idx
    _ => return -1
  }
  guard self.instance_at(owner_idx) is Some(instance) else { return -1 }
  let type_idx = self.get_func_type_idx(func_addr)
  if type_idx < 0 || type_idx >= instance.canonical_type_indices.length() {
    return -1
  }
  instance.canonical_type_indices[type_idx]
}

///|
/// Get function code for a store address that is known to refer to a Wasm function.
pub fn Store::get_func(
  self : Store,
  idx : Int,
) -> @types.FunctionCode raise RuntimeError {
  match self.get_func_inst(idx) {
    WasmFunc(code) => code
    HostFunc(_) => raise TypeMismatch // Cannot get code from host function
  }
}

///|
pub fn Store::get_table(self : Store, idx : Int) -> Table raise RuntimeError {
  match self.current_state().tables.get(idx) {
    Some(table) => table
    None => raise UndefinedElement
  }
}

///|
/// Get the JIT table corresponding to a runtime table (if exists)
pub fn Store::get_jit_table(self : Store, idx : Int) -> @wasmoon_jit.JITTable? {
  match self.current_state().jit_tables.get(idx) {
    Some(table) => table
    None => None
  }
}

///|
pub fn Store::get_mem(self : Store, idx : Int) -> Memory raise RuntimeError {
  match self.current_state().mems.get(idx) {
    Some(memory) => memory
    None => raise UndefinedElement
  }
}

///|
/// Get memory by index (returns None if not found)
/// This is useful for WASI functions that need memory access
pub fn Store::get_memory(self : Store, idx : Int) -> Memory {
  match self.current_state().mems.get(idx) {
    Some(memory) => memory
    None => Memory(0, None)
  }
}

///|
/// Get WASI module's memory
/// Uses the stored wasi_mem_addr if set, otherwise falls back to index 0
pub fn Store::get_wasi_memory(self : Store) -> Memory {
  match self.current_state().wasi_mem_addr {
    Some(addr) => self.get_memory(addr)
    None => self.get_memory(0)
  }
}

///|
/// Set the current WASI module's memory address
/// Should be called after instantiating a module that uses WASI
pub fn Store::set_wasi_mem_addr(
  self : Store,
  addr : Int,
) -> Unit raise RuntimeError {
  self.ensure_open()
  self.current_state().wasi_mem_addr = Some(addr)
}

///|
/// Get the WASI context handle (for WAST runner to retrieve WASI context)
pub fn Store::get_wasi_ctx_handle(self : Store) -> Int {
  self.wasi_ctx_handle
}

///|
/// Set the WASI context handle (for WAST runner to store WASI context)
pub fn Store::set_wasi_ctx_handle(
  self : Store,
  handle : Int,
) -> Unit raise RuntimeError {
  self.ensure_open()
  self.wasi_ctx_handle = handle
}

///|
pub fn Store::get_global(
  self : Store,
  idx : Int,
) -> GlobalInstance raise RuntimeError {
  match self.current_state().globals.get(idx) {
    Some(global) => global
    None => raise UndefinedElement
  }
}

///|
/// Register a module instance and set ownership for its functions
/// Only sets ownership for functions that don't already have an owner
/// (imported functions already belong to their original module)
pub fn Store::register_instance(
  self : Store,
  instance : ModuleInstance,
) -> Int raise RuntimeError {
  self.ensure_open()
  let state = self.current_state()
  let instance_idx = state.instances.length()
  instance.store_idx = instance_idx
  state.instances.push(instance)
  // Set ownership only for unowned WASM functions
  // HostFunc and already-owned functions are not changed
  for func_addr in instance.func_addrs {
    if self.func_owner_at(func_addr) == Unowned {
      self.set_func_owner(func_addr, Module(instance_idx))
    }
  }
  // Set ownership for unowned tags
  for tag_addr in instance.tag_addrs {
    if self.tag_owner_at(tag_addr) == Unowned {
      self.set_tag_owner(tag_addr, Module(instance_idx))
    }
  }
  instance_idx
}

///|
/// Get the owning module instance for a function address
pub fn Store::get_func_owner(self : Store, func_addr : Int) -> ModuleInstance? {
  match self.func_owner_at(func_addr) {
    Module(idx) => self.instance_at(idx)
    _ => None
  }
}

///|
/// Get the owning module instance index for a function address
/// Returns -1 if no owner (host function or unowned)
pub fn Store::get_func_owner_idx(self : Store, func_addr : Int) -> Int {
  match self.func_owner_at(func_addr) {
    Module(idx) => idx
    _ => -1
  }
}

// ============================================================
// Garbage Collection
// ============================================================

///|
/// Check if a value is a GC reference (struct, array, or i31)
fn is_gc_ref(value : @types.Value) -> Bool {
  match value {
    StructRef(_) | ArrayRef(_) | I31(_) => true
    _ => false
  }
}

///|
/// Collect all GC roots from the store (globals, tables, exns, wrapped_externs)
/// Additional roots can be passed in (e.g., from the interpreter stack)
pub fn Store::collect_roots(
  self : Store,
  additional_roots : Array[@types.Value],
) -> Array[@types.Value] {
  let roots : Array[@types.Value] = []
  let state = self.current_state()

  // Collect from globals
  for global in state.globals {
    if is_gc_ref(global.value) {
      roots.push(global.value)
    }
  }

  // Collect from tables
  for table in state.tables {
    for i in 0..<table.size {
      let value = table.elements[i]
      if is_gc_ref(value) {
        roots.push(value)
      }
    }
  }

  // Collect from exception instances
  for exn in state.exns {
    for value in exn.values {
      if is_gc_ref(value) {
        roots.push(value)
      }
    }
  }

  // Collect from wrapped externrefs
  for value in state.wrapped_externs {
    if is_gc_ref(value) {
      roots.push(value)
    }
  }

  // Add additional roots (e.g., from interpreter stack)
  for value in additional_roots {
    if is_gc_ref(value) {
      roots.push(value)
    }
  }
  roots
}

///|
/// Perform garbage collection on the C heap
/// Returns the number of objects collected, or 0 if no C heap is enabled
/// The additional_roots parameter allows passing in roots from the interpreter stack
pub fn Store::collect_garbage(
  self : Store,
  additional_roots? : Array[@types.Value] = [],
) -> Int {
  match self.c_heap {
    Some(heap) => {
      let roots = self.collect_roots(additional_roots)
      heap.collect(roots)
    }
    None => 0 // No C heap, nothing to collect
  }
}

///|
/// Check if GC should be triggered based on heap usage
/// Returns true if heap usage exceeds the threshold (default 75%)
pub fn Store::should_collect(self : Store, threshold? : Double = 0.75) -> Bool {
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
  additional_roots? : Array[@types.Value] = [],
  threshold? : Double = 0.75,
) -> Int {
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
pub fn Store::get_gc_stats(self : Store) -> (Int64, Int64, Int, Int, Int) {
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
