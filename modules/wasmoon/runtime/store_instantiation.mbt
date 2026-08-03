///|
/// All Store state whose identity grows during core-module instantiation.
/// Imported tables, memories, globals, and instances are reference values, so
/// a fork shares their observable mutations while owning its array topology.
priv struct StoreState {
  funcs : Array[FuncInst]
  func_types : Array[@types.FuncType]
  func_type_indices : Array[Int]
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
  tags : Array[@types.FuncType]
  tag_type_indices : Array[Int]
  tag_owners : Array[FuncOwner]
  exns : Array[ExnInstance]
  mut module_types : Array[@types.SubType]
  mut module_rec_groups : Array[Int]
  wrapped_externs : Array[@types.Value]
  func_owners : Array[FuncOwner]
  instances : Array[ModuleInstance]
  jit_tables : Array[@wasmoon_jit.JITTable?]
  jit_table_owners : Array[@wasmoon_jit.JITTableOwner?]
  mut wasi_mem_addr : Int?
} derive(Debug)

///|
fn StoreState::new() -> StoreState {
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
    module_types: [],
    module_rec_groups: [],
    wrapped_externs: [],
    func_owners: [],
    instances: [],
    jit_tables: [],
    jit_table_owners: [],
    wasi_mem_addr: None,
  }
}

///|
fn StoreState::fork(self : StoreState) -> StoreState {
  {
    funcs: self.funcs.copy(),
    func_types: self.func_types.copy(),
    func_type_indices: self.func_type_indices.copy(),
    tables: self.tables.copy(),
    mems: self.mems.copy(),
    globals: self.globals.copy(),
    tags: self.tags.copy(),
    tag_type_indices: self.tag_type_indices.copy(),
    tag_owners: self.tag_owners.copy(),
    exns: self.exns.copy(),
    module_types: self.module_types,
    module_rec_groups: self.module_rec_groups,
    wrapped_externs: self.wrapped_externs.copy(),
    func_owners: self.func_owners.copy(),
    instances: self.instances.copy(),
    jit_tables: self.jit_tables.copy(),
    jit_table_owners: self.jit_table_owners.copy(),
    wasi_mem_addr: self.wasi_mem_addr,
  }
}

///|
/// Owner-bound frame containing one unpublished Store state.
priv struct StoreBuildState {
  owner : Store
  state : StoreState
  abort_heap_allocations : () -> Unit
  abort_c_heap_allocations : (() -> Unit)?
  mut active : Bool
}

///|
impl Debug for StoreBuildState with fn to_repr(_self) {
  Repr::literal("<store-build-state>")
}

///|
fn Store::current_state(self : Store) -> StoreState {
  match self.instantiation {
    Some(frame) => frame.state
    None => self.state
  }
}

///|
fn[T] push_and_index(values : Array[T], value : T) -> Int {
  let index = values.length()
  values.push(value)
  index
}

///|
fn Store::alloc_func_inst(
  self : Store,
  func : FuncInst,
  func_type : @types.FuncType,
  type_idx : Int,
  owner : FuncOwner,
) -> Int {
  let state = self.current_state()
  let index = state.funcs.length()
  state.funcs.push(func)
  state.func_types.push(func_type)
  state.func_type_indices.push(type_idx)
  state.func_owners.push(owner)
  index
}

///|
fn Store::func_owner_at(self : Store, index : Int) -> FuncOwner {
  self.current_state().func_owners.get(index).unwrap_or(Unowned)
}

///|
fn Store::tag_owner_at(self : Store, index : Int) -> FuncOwner {
  self.current_state().tag_owners.get(index).unwrap_or(Unowned)
}

///|
fn Store::instance_at(self : Store, index : Int) -> ModuleInstance? {
  self.current_state().instances.get(index)
}

///|
fn Store::set_func_owner(self : Store, index : Int, owner : FuncOwner) -> Unit {
  let func_owners = self.current_state().func_owners
  if index >= 0 && index < func_owners.length() {
    func_owners[index] = owner
  }
}

///|
fn Store::set_tag_owner(self : Store, index : Int, owner : FuncOwner) -> Unit {
  let tag_owners = self.current_state().tag_owners
  if index >= 0 && index < tag_owners.length() {
    tag_owners[index] = owner
  }
}

///|
fn Store::begin_instantiation(
  self : Store,
) -> StoreBuildState raise RuntimeError {
  self.ensure_open()
  if self.instantiation is Some(_) {
    raise LinkErrorDetail("store instantiation is already active")
  }
  let frame : StoreBuildState = {
    owner: self,
    state: self.state.fork(),
    abort_heap_allocations: self.heap.make_instantiation_abort(fn() {
      self.collect_roots([])
    }),
    abort_c_heap_allocations: self.c_heap.map(fn(heap) {
      heap.make_instantiation_abort(fn() { self.collect_roots([]) })
    }),
    active: true,
  }
  self.instantiation = Some(frame)
  frame
}

///|
fn StoreBuildState::commit(self : StoreBuildState) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  self.owner.instantiation = None
  self.owner.state = self.state
}

///|
fn StoreBuildState::discard(self : StoreBuildState) -> Unit {
  if !self.active {
    return
  }
  self.active = false
  let baseline = self.owner.state
  self.owner.instantiation = None
  for i in baseline.instances.length()..<self.state.instances.length() {
    self.state.instances[i].store_idx = -1
  }
  for i in baseline.mems.length()..<self.state.mems.length() {
    self.state.mems[i].close()
  }
  for
    i in baseline.jit_table_owners.length()..<self.state.jit_table_owners.length() {
    if self.state.jit_table_owners[i] is Some(owner) {
      owner.close()
    }
  }
  (self.abort_heap_allocations)()
  if self.abort_c_heap_allocations is Some(abort) {
    abort()
  }
}
