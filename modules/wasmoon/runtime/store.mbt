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
  funcs : Array[FuncInst]
  func_types : Array[@types.FuncType] // Type of each function
  func_type_indices : Array[Int] // Original type index for structural comparison
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
  tags : Array[@types.FuncType] // Tag types (params only, no results)
  tag_type_indices : Array[Int] // Original type index for each tag
  tag_owners : Array[FuncOwner] // Owner module for each tag
  exns : Array[ExnInstance] // Exception instances for exnref
  heap : MarkSweepHeap // GC heap for struct and array instances (interpreter mode)
  // C-managed GC heap for JIT mode (None = use MarkSweepHeap)
  mut c_heap : @wasmoon_jit.CHeap?
  // Module types for CHeap type lookups (needed to decode Int64 to Value)
  mut module_types : Array[@types.SubType]
  // Module rec groups for canonical type index computation
  mut module_rec_groups : Array[Int]
  // Internal values wrapped as externref via extern.convert_any
  // Accessed using negative ExternRef indices: ExternRef(-1-i) = wrapped_externs[i]
  wrapped_externs : Array[@types.Value]
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
  mut wasi_mem_addr : Int?
  // Opaque WASI context handle (for WAST runner to store WASI context)
  // This avoids circular dependency between runtime and wasi packages
  mut wasi_ctx_handle : Int
  // Native invocation/fiber lifetimes belong to the Store, not a JIT module.
  native_execution : @wasmoon_jit.NativeExecutionState
  priv funcref_registry : StoreFuncrefRegistry
  priv closed : Ref[Bool]
} derive(Debug)

///|
priv struct StoreAllocationCheckpoint {
  funcs : Int
  func_types : Int
  func_type_indices : Int
  func_owners : Array[FuncOwner]
  tables : Int
  jit_tables : Int
  mems : Int
  globals : Int
  tags : Int
  tag_type_indices : Int
  tag_owners : Array[FuncOwner]
  exns : Int
  wrapped_externs : Int
  instances : Int
  module_types : Array[@types.SubType]
  module_rec_groups : Array[Int]
  heap : MarkSweepHeapAllocationCheckpoint
  c_heap : @wasmoon_jit.CHeapAllocationCheckpoint?
}

///|
fn Store::checkpoint_allocations(self : Store) -> StoreAllocationCheckpoint {
  {
    funcs: self.funcs.length(),
    func_types: self.func_types.length(),
    func_type_indices: self.func_type_indices.length(),
    func_owners: self.func_owners.copy(),
    tables: self.tables.length(),
    jit_tables: self.jit_tables.length(),
    mems: self.mems.length(),
    globals: self.globals.length(),
    tags: self.tags.length(),
    tag_type_indices: self.tag_type_indices.length(),
    tag_owners: self.tag_owners.copy(),
    exns: self.exns.length(),
    wrapped_externs: self.wrapped_externs.length(),
    instances: self.instances.length(),
    module_types: self.module_types,
    module_rec_groups: self.module_rec_groups,
    heap: self.heap.checkpoint_allocations(),
    c_heap: self.c_heap.map(fn(heap) { heap.checkpoint_allocations() }),
  }
}

///|
fn Store::rollback_allocations(
  self : Store,
  checkpoint : StoreAllocationCheckpoint,
) -> Unit {
  for i in checkpoint.instances..<self.instances.length() {
    self.instances[i].store_idx = -1
  }
  for i in checkpoint.mems..<self.mems.length() {
    self.mems[i].close()
  }
  for i in checkpoint.jit_tables..<self.jit_table_owners.length() {
    match self.jit_table_owners[i] {
      Some(owner) => owner.close()
      None => ()
    }
  }
  self.funcs.truncate(checkpoint.funcs)
  self.func_types.truncate(checkpoint.func_types)
  self.func_type_indices.truncate(checkpoint.func_type_indices)
  self.func_owners.clear()
  for owner in checkpoint.func_owners {
    self.func_owners.push(owner)
  }
  self.tables.truncate(checkpoint.tables)
  self.jit_tables.truncate(checkpoint.jit_tables)
  self.jit_table_owners.truncate(checkpoint.jit_tables)
  self.mems.truncate(checkpoint.mems)
  self.globals.truncate(checkpoint.globals)
  self.tags.truncate(checkpoint.tags)
  self.tag_type_indices.truncate(checkpoint.tag_type_indices)
  self.tag_owners.clear()
  for owner in checkpoint.tag_owners {
    self.tag_owners.push(owner)
  }
  self.exns.truncate(checkpoint.exns)
  self.wrapped_externs.truncate(checkpoint.wrapped_externs)
  self.instances.truncate(checkpoint.instances)
  self.module_types = checkpoint.module_types
  self.module_rec_groups = checkpoint.module_rec_groups
  let roots = self.collect_roots([])
  self.heap.rollback_allocations(checkpoint.heap, roots)
  match (self.c_heap, checkpoint.c_heap) {
    (Some(heap), Some(heap_checkpoint)) =>
      heap.rollback_allocations(heap_checkpoint, roots) |> ignore
    _ => ()
  }
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
    funcs: [],
    func_types: [],
    func_type_indices: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    tag_type_indices: [],
    tag_owners: [],
    exns: [],
    heap: MarkSweepHeap(),
    c_heap: None,
    module_types: [],
    module_rec_groups: [],
    wrapped_externs: [],
    func_owners: [],
    instances: [],
    jit_tables: [],
    jit_table_owners: [],
    wasi_mem_addr: None,
    wasi_ctx_handle: 0,
    native_execution: NativeExecutionState(),
    funcref_registry: StoreFuncrefRegistry::new(),
    closed: Ref(false),
  }
}

///|
/// Create a store with C heap enabled (for JIT mode)
pub fn Store::with_c_heap() -> Store {
  let initial_capacity = c_heap_initial_capacity()
  {
    funcs: [],
    func_types: [],
    func_type_indices: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    tag_type_indices: [],
    tag_owners: [],
    exns: [],
    heap: MarkSweepHeap(), // Used only when c_heap is None.
    c_heap: Some(CHeap(capacity=initial_capacity)),
    module_types: [],
    module_rec_groups: [],
    wrapped_externs: [],
    func_owners: [],
    instances: [],
    jit_tables: [],
    jit_table_owners: [],
    wasi_mem_addr: None,
    wasi_ctx_handle: 0,
    native_execution: NativeExecutionState(),
    funcref_registry: StoreFuncrefRegistry::new(),
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
  self.closed.val = true
  self.native_execution.seal()
  self.funcref_registry.clear()
  self.funcs.clear()
  self.func_types.clear()
  self.func_type_indices.clear()
  self.func_owners.clear()
  self.instances.clear()
  self.tables.clear()
  for memory in self.mems {
    memory.close()
  }
  self.mems.clear()
  self.globals.clear()
  self.tags.clear()
  self.tag_type_indices.clear()
  self.tag_owners.clear()
  self.exns.clear()
  self.heap.clear()
  if self.c_heap is Some(heap) {
    heap.free()
    self.c_heap = None
  }
  self.module_types.clear()
  self.module_rec_groups.clear()
  self.wrapped_externs.clear()
  for owner in self.jit_table_owners {
    match owner {
      Some(owner) => owner.close()
      None => ()
    }
  }
  self.jit_table_owners.clear()
  self.jit_tables.clear()
  self.wasi_mem_addr = None
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
  self.module_types = types
  self.module_rec_groups = rec_groups
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
  let idx = self.wrapped_externs.length()
  self.wrapped_externs.push(value)
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
        if wrapped_idx >= self.wrapped_externs.length() {
          raise UndefinedElement
        }
        self.wrapped_externs[wrapped_idx]
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
  let idx = self.funcs.length()
  self.funcs.push(WasmFunc(func))
  self.func_types.push(func_type)
  self.func_type_indices.push(type_idx)
  self.func_owners.push(Unowned)
  idx
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
  let idx = self.funcs.length()
  // Back-compat: old-style host funcs don't take a Caller.
  let wrapped : (Caller, Array[@types.Value]) -> Array[@types.Value] raise RuntimeError = (
    _caller,
    args,
  ) => func(args)
  self.funcs.push(HostFunc(wrapped))
  self.func_types.push(func_type)
  self.func_type_indices.push(type_idx)
  self.func_owners.push(HostFunc)
  idx
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
  let idx = self.funcs.length()
  self.funcs.push(HostFunc(func))
  self.func_types.push(func_type)
  self.func_type_indices.push(type_idx)
  self.func_owners.push(HostFunc)
  idx
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
  let idx = self.tables.length()
  self.tables.push(table)

  // Create corresponding JIT table (always enabled for cross-module sharing)
  if use_jit {
    let (min, max) = table.get_limits()
    match @wasmoon_jit.JITTableOwner::try_alloc(min, max) {
      Some(owner) => {
        self.jit_tables.push(Some(owner.table()))
        self.jit_table_owners.push(Some(owner))
      }
      None => {
        self.jit_tables.push(None)
        self.jit_table_owners.push(None)
      }
    }
  } else {
    self.jit_tables.push(None)
    self.jit_table_owners.push(None)
  }
  idx
}

///|
pub fn Store::alloc_mem(self : Store, mem : Memory) -> Int raise RuntimeError {
  self.ensure_open()
  let idx = self.mems.length()
  self.mems.push(mem)
  idx
}

///|
pub fn Store::alloc_global(
  self : Store,
  global : GlobalInstance,
) -> Int raise RuntimeError {
  self.ensure_open()
  let idx = self.globals.length()
  self.globals.push(global)
  idx
}

///|
/// Allocate a tag with its type (params from FuncType, results ignored)
pub fn Store::alloc_tag(
  self : Store,
  tag_type : @types.FuncType,
  type_idx? : Int = -1,
) -> Int raise RuntimeError {
  self.ensure_open()
  let idx = self.tags.length()
  self.tags.push(tag_type)
  self.tag_type_indices.push(type_idx)
  self.tag_owners.push(Unowned)
  idx
}

///|
pub fn Store::get_tag_type(
  self : Store,
  idx : Int,
) -> @types.FuncType raise RuntimeError {
  if idx < 0 || idx >= self.tags.length() {
    raise UndefinedElement
  }
  self.tags[idx]
}

///|
/// Get the original type index for a tag
pub fn Store::get_tag_type_idx(self : Store, tag_addr : Int) -> Int {
  if tag_addr < 0 || tag_addr >= self.tag_type_indices.length() {
    return -1
  }
  self.tag_type_indices[tag_addr]
}

///|
/// Get the owner module for a tag
pub fn Store::get_tag_owner(self : Store, tag_addr : Int) -> ModuleInstance? {
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
  tag_addr : Int,
  values : Array[@types.Value],
) -> Int raise RuntimeError {
  self.ensure_open()
  let idx = self.exns.length()
  self.exns.push({ tag_addr, values })
  idx
}

///|
/// Get an exception instance by index
pub fn Store::get_exn(
  self : Store,
  idx : Int,
) -> ExnInstance raise RuntimeError {
  if idx < 0 || idx >= self.exns.length() {
    raise UndefinedElement
  }
  self.exns[idx]
}

///|
/// Get the field type of a struct from module_types
fn Store::get_struct_field_type(
  self : Store,
  type_idx : Int,
  field_idx : Int,
) -> @types.ValueType {
  if type_idx < 0 || type_idx >= self.module_types.length() {
    return I64 // Fallback
  }
  match self.module_types[type_idx].composite {
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
  if type_idx < 0 || type_idx >= self.module_types.length() {
    return I64
  }
  match self.module_types[type_idx].composite {
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
  if idx < 0 || idx >= self.funcs.length() {
    raise UndefinedElement
  }
  self.funcs[idx]
}

///|
/// Get function instance by store address (returns None if out of range).
///
/// This is useful for embedding/JIT callbacks that must not raise.
pub fn Store::get_func_inst_opt(self : Store, idx : Int) -> FuncInst? {
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
  idx : Int,
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
pub fn Store::get_func_type_opt(self : Store, idx : Int) -> @types.FuncType? {
  if idx < 0 || idx >= self.func_types.length() {
    None
  } else {
    Some(self.func_types[idx])
  }
}

///|
/// Get function type index by store address (for structural comparison)
pub fn Store::get_func_type_idx(self : Store, idx : Int) -> Int {
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
pub fn Store::get_func_canonical_type_idx(self : Store, func_addr : Int) -> Int {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return -1
  }
  let owner_idx = match self.func_owners[func_addr] {
    Module(idx) => idx
    _ => return -1
  }
  if owner_idx >= self.instances.length() {
    return -1
  }
  let instance = self.instances[owner_idx]
  let type_idx = self.func_type_indices[func_addr]
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
  if idx < 0 || idx >= self.tables.length() {
    raise UndefinedElement
  }
  self.tables[idx]
}

///|
/// Get the JIT table corresponding to a runtime table (if exists)
pub fn Store::get_jit_table(self : Store, idx : Int) -> @wasmoon_jit.JITTable? {
  if idx < 0 || idx >= self.jit_tables.length() {
    return None
  }
  self.jit_tables[idx]
}

///|
pub fn Store::get_mem(self : Store, idx : Int) -> Memory raise RuntimeError {
  if idx < 0 || idx >= self.mems.length() {
    raise UndefinedElement
  }
  self.mems[idx]
}

///|
/// Get memory by index (returns None if not found)
/// This is useful for WASI functions that need memory access
pub fn Store::get_memory(self : Store, idx : Int) -> Memory {
  if idx < 0 || idx >= self.mems.length() {
    // Return a dummy empty memory if not found
    Memory(0, None)
  } else {
    self.mems[idx]
  }
}

///|
/// Get WASI module's memory
/// Uses the stored wasi_mem_addr if set, otherwise falls back to index 0
pub fn Store::get_wasi_memory(self : Store) -> Memory {
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
  addr : Int,
) -> Unit raise RuntimeError {
  self.ensure_open()
  self.wasi_mem_addr = Some(addr)
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
) -> Int raise RuntimeError {
  self.ensure_open()
  let instance_idx = self.instances.length()
  instance.store_idx = instance_idx
  self.instances.push(instance)
  // Set ownership only for unowned WASM functions
  // HostFunc and already-owned functions are not changed
  for func_addr in instance.func_addrs {
    if func_addr >= 0 &&
      func_addr < self.func_owners.length() &&
      self.func_owners[func_addr] == Unowned {
      self.func_owners[func_addr] = Module(instance_idx)
    }
  }
  // Set ownership for unowned tags
  for tag_addr in instance.tag_addrs {
    if tag_addr >= 0 &&
      tag_addr < self.tag_owners.length() &&
      self.tag_owners[tag_addr] == Unowned {
      self.tag_owners[tag_addr] = Module(instance_idx)
    }
  }
  instance_idx
}

///|
/// Get the owning module instance for a function address
pub fn Store::get_func_owner(self : Store, func_addr : Int) -> ModuleInstance? {
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
pub fn Store::get_func_owner_idx(self : Store, func_addr : Int) -> Int {
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

  // Collect from globals
  for global in self.globals {
    if is_gc_ref(global.value) {
      roots.push(global.value)
    }
  }

  // Collect from tables
  for table in self.tables {
    for i in 0..<table.size {
      let value = table.elements[i]
      if is_gc_ref(value) {
        roots.push(value)
      }
    }
  }

  // Collect from exception instances
  for exn in self.exns {
    for value in exn.values {
      if is_gc_ref(value) {
        roots.push(value)
      }
    }
  }

  // Collect from wrapped externrefs
  for value in self.wrapped_externs {
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
