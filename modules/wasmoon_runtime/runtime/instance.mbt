///|
/// Runtime instance of a WebAssembly module
pub struct ModuleInstance {
  types : ReadOnlyArray[@types.SubType] // GC: now stores SubType
  type_rec_groups : ReadOnlyArray[Int32] // rec group IDs for each type
  canonical_type_indices : ReadOnlyArray[Int32] // canonical indices for structural equivalence
  priv mut store_idx : Int32 // index in the store's instances array, -1 if not registered
  mut func_addrs : ReadOnlyArray[Int32] // addresses into function store
  func_type_indices : ReadOnlyArray[Int32] // type indices for each function
  mut table_addrs : ReadOnlyArray[Int32] // indices into table store
  mut mem_addrs : ReadOnlyArray[Int32] // indices into memory store
  mut global_addrs : ReadOnlyArray[Int32] // indices into global store
  tag_addrs : ReadOnlyArray[Int32] // indices into tag store
  mut exports : ReadOnlyArray[@types.Export]
  priv elem_values : Array[Array[@types.Value]]
  elem_segments : ReadOnlyArray[@types.Element]
  data_segments : ReadOnlyArray[@types.Data]
  priv dropped_elems : FixedArray[Bool] // true if elem segment has been dropped
  priv dropped_datas : FixedArray[Bool] // true if data segment has been dropped
  priv mut owner : Ref[Bool]?
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for ModuleInstance with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
pub fn ModuleInstance::ModuleInstance() -> ModuleInstance {
  {
    owner: None,
    types: [],
    type_rec_groups: [],
    canonical_type_indices: [],
    store_idx: -1,
    func_addrs: [],
    func_type_indices: [],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    tag_addrs: [],
    exports: [],
    elem_values: [],
    elem_segments: [],
    data_segments: [],
    dropped_elems: [],
    dropped_datas: [],
  }
}

// Type-kind lookups on an instance.
//
// An instance exists only after its module passed validation, so a type
// index used as a function type names one. That is a claim about wasmoon,
// not about the input, and the names now say so: `validated_` marks every
// caller that leans on validation having run (ISS-396).
//
// The bounds check is not redundant with that claim. Reaching it means an
// index arrived from somewhere validation does not cover, and saying so
// beats dying on an array access with nothing on either stream.

///|
/// The function type at `idx`, in an instance whose module passed validation.
pub fn ModuleInstance::validated_func_type_at(
  self : ModuleInstance,
  idx : Int32,
) -> @types.FuncType {
  guard idx >= 0 && idx < self.types.length() else {
    abort("validated instance has no type at index \{idx}")
  }
  match self.types[idx].composite {
    Func(ft) => ft
    _ => abort("validated instance has no function type at index \{idx}")
  }
}

///|
/// The struct type at `idx`, in an instance whose module passed validation.
pub fn ModuleInstance::validated_struct_type_at(
  self : ModuleInstance,
  idx : Int32,
) -> @types.StructType {
  guard idx >= 0 && idx < self.types.length() else {
    abort("validated instance has no type at index \{idx}")
  }
  match self.types[idx].composite {
    Struct(st) => st
    _ => abort("validated instance has no struct type at index \{idx}")
  }
}

///|
/// The array type at `idx`, in an instance whose module passed validation.
pub fn ModuleInstance::validated_array_type_at(
  self : ModuleInstance,
  idx : Int32,
) -> @types.ArrayType {
  guard idx >= 0 && idx < self.types.length() else {
    abort("validated instance has no type at index \{idx}")
  }
  match self.types[idx].composite {
    Array(at) => at
    _ => abort("validated instance has no array type at index \{idx}")
  }
}

///|
/// Retire evaluated element values as well as their guest-visible availability.
pub fn ModuleInstance::drop_element(
  self : ModuleInstance,
  index : Int32,
) -> Unit raise RuntimeError {
  self.ensure_live()
  guard index >= 0 && index < self.dropped_elems.length() else {
    raise UndefinedElement
  }
  self.dropped_elems[index] = true
  self.elem_values[index].clear()
  self.elem_values[index].shrink_to_fit()
}

///|
pub fn ModuleInstance::store_index(self : ModuleInstance) -> Int32 {
  self.store_idx
}

///|
pub fn Store::check_instance(
  self : Store,
  instance : ModuleInstance,
) -> Unit raise RuntimeError {
  self.ensure_open()
  guard instance.owner is Some(owner) else { raise InvalidHandle }
  guard physical_equal(owner, self.closed) else { raise ForeignStore }
  guard instance.store_idx >= 0 &&
    instance.store_idx < self.instances.length() &&
    physical_equal(self.instances[instance.store_idx], instance) else {
    raise InvalidHandle
  }
}

///|
pub fn ModuleInstance::element_dropped(
  self : ModuleInstance,
  index : Int32,
) -> Bool {
  self.store_idx < 0 ||
  self.owner is Some({ val: true, }) ||
  index < 0 ||
  index >= self.dropped_elems.length() ||
  self.dropped_elems[index]
}

///|
pub fn ModuleInstance::data_dropped(
  self : ModuleInstance,
  index : Int32,
) -> Bool {
  self.store_idx < 0 ||
  self.owner is Some({ val: true, }) ||
  index < 0 ||
  index >= self.dropped_datas.length() ||
  self.dropped_datas[index]
}

///|
pub fn ModuleInstance::drop_data(
  self : ModuleInstance,
  index : Int32,
) -> Unit raise RuntimeError {
  self.ensure_live()
  guard index >= 0 && index < self.dropped_datas.length() else {
    raise UndefinedElement
  }
  self.dropped_datas[index] = true
}

///|
pub fn ModuleInstance::element_values(
  self : ModuleInstance,
  index : Int32,
) -> ReadOnlyArray[@types.Value] raise RuntimeError {
  self.ensure_live()
  guard index >= 0 && index < self.elem_values.length() else {
    raise UndefinedElement
  }
  ReadOnlyArray::from_array(self.elem_values[index])
}

///|
/// Native integration: bind the instance's drop state without exposing mutable arrays.
pub fn[T : SegmentDropBinding] ModuleInstance::bind_native_segments(
  self : ModuleInstance,
  context : T,
) -> Unit {
  context.bind_segment_drop_flags(self.dropped_datas, self.dropped_elems)
}

///|
/// Publish a validated module's address maps into this Store.
/// Addresses are Store-local low-level integration indices, checked before publication.
pub fn Store::new_instance(
  self : Store,
  validated : @validator.ValidatedModule,
  func_addrs~ : ArrayView[Int32],
  table_addrs~ : ArrayView[Int32],
  mem_addrs~ : ArrayView[Int32],
  global_addrs~ : ArrayView[Int32],
  tag_addrs~ : ArrayView[Int32],
  elem_values~ : Array[Array[@types.Value]],
  admission? : InstanceAdmission,
) -> ModuleInstance raise RuntimeError {
  self.ensure_open()
  let admission = admission.unwrap_or_else(() => self.reserve_instance())
  self.check_instance_admission(admission, validated~)
  let module_ = validated.snapshot()
  let expected_functions : Array[Int32] = []
  let mut functions = module_.codes.length()
  let mut tables = module_.tables.length()
  let mut memories = module_.memories.length()
  let mut globals = module_.globals.length()
  let mut tags = module_.tags.length()
  for import_ in module_.imports {
    match import_.desc {
      Func(index) => {
        functions += 1
        expected_functions.push(index)
      }
      Table(_) => tables += 1
      Memory(_) => memories += 1
      Global(_) => globals += 1
      Tag(_) => tags += 1
    }
  }
  for index in module_.funcs {
    expected_functions.push(index)
  }
  let func_type_indices = expected_functions
  guard func_addrs.length() == functions &&
    table_addrs.length() == tables &&
    mem_addrs.length() == memories &&
    global_addrs.length() == globals &&
    tag_addrs.length() == tags &&
    elem_values.length() == module_.elems.length() else {
    raise InvalidHandle
  }
  for address in func_addrs {
    self.get_func_inst(address) |> ignore
  }
  for address in table_addrs {
    self.get_table(address) |> ignore
  }
  for address in mem_addrs {
    self.get_mem(address) |> ignore
  }
  for address in global_addrs {
    self.get_global(address) |> ignore
  }
  for address in tag_addrs {
    self.get_tag_type(address) |> ignore
  }
  for index, type_index in func_type_indices {
    let address = func_addrs[index]
    let expected = module_.validated_func_type_at(type_index)
    let matches = match self.get_func_owner(address) {
      Some(owner) =>
        @types.SubtypingContext::cross_module(
          owner.types,
          module_.types,
          rec_groups1=owner.type_rec_groups,
          rec_groups2=module_.type_rec_groups,
        ).is_subtype(self.get_func_type_idx(address), type_index)
      None => self.get_func_type(address) == expected
    }
    guard matches else { raise TypeMismatch }
  }
  let imported_functions = functions - module_.codes.length()
  for index, code in module_.codes {
    let address = func_addrs[imported_functions + index]
    guard self.get_func_owner(address) is None &&
      physical_equal(self.get_func(address), code) else {
      raise InvalidHandle
    }
  }
  let expected_memories : Array[@types.MemoryType] = []
  let expected_tables : Array[@types.TableType] = []
  let expected_globals : Array[@types.GlobalType] = []
  let expected_tags : Array[Int32] = []
  for import_ in module_.imports {
    match import_.desc {
      Memory(type_) => expected_memories.push(type_)
      Table(type_) => expected_tables.push(type_)
      Global(type_) => expected_globals.push(type_)
      Tag(type_) => expected_tags.push(type_)
      Func(_) => ()
    }
  }
  for type_ in module_.memories {
    expected_memories.push(type_)
  }
  for table in module_.tables {
    expected_tables.push(table.type_)
  }
  for global in module_.globals {
    expected_globals.push(global.type_)
  }
  for tag in module_.tags {
    expected_tags.push(tag.type_idx)
  }
  for index, expected in expected_memories {
    let memory = self.get_mem(mem_addrs[index])
    let (minimum, maximum) = memory.get_limits64()
    guard memory.is_memory64() == expected.is_memory64 &&
      memory.is_shared() == expected.is_shared &&
      memory.page_size_bytes() == 1L << expected.page_size_log2 &&
      minimum.reinterpret_as_uint64() >=
      expected.limits.min.reinterpret_as_uint64() else {
      raise TypeMismatch
    }
    if expected.limits.max is Some(limit) {
      guard maximum is Some(actual) &&
        actual.reinterpret_as_uint64() <= limit.reinterpret_as_uint64() else {
        raise TypeMismatch
      }
    }
  }
  for index, expected in expected_tables {
    let table = self.get_table(table_addrs[index])
    let (minimum, maximum) = table.get_limits64()
    guard table.is_table64() == expected.is_table64 &&
      minimum.reinterpret_as_uint64() >=
      expected.limits.min.reinterpret_as_uint64() else {
      raise TypeMismatch
    }
    let context = self.resource_type_context(Table(table_addrs[index]), module_)
    guard context.value_type_subtype(table.get_elem_type(), expected.elem_type) &&
      reverse_type_context(context).value_type_subtype(
        expected.elem_type,
        table.get_elem_type(),
      ) else {
      raise TypeMismatch
    }
    if expected.limits.max is Some(limit) {
      guard maximum is Some(actual) &&
        actual.reinterpret_as_uint64() <= limit.reinterpret_as_uint64() else {
        raise TypeMismatch
      }
    }
  }
  for index, expected in expected_globals {
    let actual = self.get_global(global_addrs[index]).get_type()
    let context = self.resource_type_context(
      Global(global_addrs[index]),
      module_,
    )
    guard actual.mutable == expected.mutable &&
      context.value_type_subtype(actual.value_type, expected.value_type) else {
      raise TypeMismatch
    }
    if expected.mutable &&
      !reverse_type_context(context).value_type_subtype(
        expected.value_type,
        actual.value_type,
      ) {
      raise TypeMismatch
    }
  }
  for index, expected in expected_tags {
    let actual = self.get_tag_type(tag_addrs[index])
    let expected_signature = module_.validated_func_type_at(expected)
    guard actual.params.length() == expected_signature.params.length() else {
      raise TypeMismatch
    }
    let context = self.resource_type_context(Tag(tag_addrs[index]), module_)
    for parameter, actual in actual.params {
      let expected = expected_signature.params[parameter]
      guard context.value_type_subtype(actual, expected) &&
        reverse_type_context(context).value_type_subtype(expected, actual) else {
        raise TypeMismatch
      }
    }
  }
  let instance = {
    types: ReadOnlyArray::from_array(module_.types),
    type_rec_groups: ReadOnlyArray::from_array(module_.type_rec_groups),
    canonical_type_indices: ReadOnlyArray::from_array(
      @types.compute_canonical_type_indices(
        module_.types,
        type_rec_groups=module_.type_rec_groups,
      ),
    ),
    store_idx: -1,
    owner: None,
    func_addrs: ReadOnlyArray::from_array(func_addrs),
    func_type_indices: ReadOnlyArray::from_array(func_type_indices),
    table_addrs: ReadOnlyArray::from_array(table_addrs),
    mem_addrs: ReadOnlyArray::from_array(mem_addrs),
    global_addrs: ReadOnlyArray::from_array(global_addrs),
    tag_addrs: ReadOnlyArray::from_array(tag_addrs),
    exports: ReadOnlyArray::from_array(module_.exports),
    elem_values: elem_values.map(fn(values) { values.copy() }),
    elem_segments: ReadOnlyArray::from_array(module_.elems),
    data_segments: ReadOnlyArray::from_array(module_.datas),
    dropped_elems: FixedArray::make(module_.elems.length(), false),
    dropped_datas: FixedArray::make(module_.datas.length(), false),
  }
  self.register_instance(instance, admission~) |> ignore
  for index, element in module_.elems {
    if element.mode is Declarative {
      instance.drop_element(index)
    }
  }
  instance
}

///|
/// Construct a Store-owned call context for an existing host function.
pub fn Store::host_call_instance(
  self : Store,
  address : Int32,
) -> ModuleInstance raise RuntimeError {
  self.ensure_open()
  guard self.get_func_inst(address) is (HostFunc(_) | AsyncHostFunc(_)) else {
    raise TypeMismatch
  }
  let signature = self.get_func_type(address)
  let instance = {
    ..ModuleInstance(),
    types: [@types.SubType::from_func(signature)],
    canonical_type_indices: [0],
    func_addrs: [address],
    func_type_indices: [0],
  }
  self.register_instance(instance) |> ignore
  instance
}

///|
/// Publish a checked namespace of host exports in this Store.
pub fn Store::host_exports(
  self : Store,
  exports : ArrayView[(String, ExternVal)],
) -> ModuleInstance raise RuntimeError {
  self.ensure_open()
  let instance = ModuleInstance()
  let funcs : Array[Int32] = []
  let tables : Array[Int32] = []
  let memories : Array[Int32] = []
  let globals : Array[Int32] = []
  let tags : Array[Int32] = []
  let definitions : Array[@types.Export] = []
  for (name, value) in exports {
    let desc : @types.ExportDesc = match value {
      Func(address) => {
        guard self.get_func_inst(address) is (HostFunc(_) | AsyncHostFunc(_)) else {
          raise TypeMismatch
        }
        funcs.push(address)
        Func(funcs.length() - 1)
      }
      Table(address) => {
        self.get_table(address) |> ignore
        tables.push(address)
        Table(tables.length() - 1)
      }
      Memory(address) => {
        self.get_mem(address) |> ignore
        memories.push(address)
        Memory(memories.length() - 1)
      }
      Global(address) => {
        self.get_global(address) |> ignore
        globals.push(address)
        Global(globals.length() - 1)
      }
      Tag(address) => {
        self.get_tag_type(address) |> ignore
        tags.push(address)
        Tag(tags.length() - 1)
      }
    }
    definitions.push({ name, desc, })
  }
  let instance = {
    ..instance,
    func_addrs: ReadOnlyArray::from_array(funcs),
    table_addrs: ReadOnlyArray::from_array(tables),
    mem_addrs: ReadOnlyArray::from_array(memories),
    global_addrs: ReadOnlyArray::from_array(globals),
    tag_addrs: ReadOnlyArray::from_array(tags),
    exports: ReadOnlyArray::from_array(definitions),
  }
  self.register_instance(instance) |> ignore
  instance
}

///|
fn Store::resource_type_context(
  self : Store,
  value : ExternVal,
  target : @types.Module,
) -> @types.SubtypingContext {
  let owner = match value {
    Tag(address) => self.get_tag_owner(address)
    _ => {
      let mut found : ModuleInstance? = None
      for instance in self.instances {
        if instance.types.is_empty() {
          continue
        }
        let contains = match value {
          Table(address) => instance.table_addrs.contains(address)
          Global(address) => instance.global_addrs.contains(address)
          _ => false
        }
        if contains {
          found = Some(instance)
          break
        }
      }
      found
    }
  }
  match owner {
    Some(owner) =>
      @types.SubtypingContext::cross_module(
        owner.types,
        target.types,
        rec_groups1=owner.type_rec_groups,
        rec_groups2=target.type_rec_groups,
      )
    None =>
      @types.SubtypingContext::same_module(
        target.types,
        rec_groups=target.type_rec_groups,
      )
  }
}

///|
fn reverse_type_context(
  context : @types.SubtypingContext,
) -> @types.SubtypingContext {
  if !context.cross_module {
    return context
  }
  @types.SubtypingContext::cross_module(
    context.types2,
    context.types1,
    rec_groups1=context.rec_groups2,
    rec_groups2=context.rec_groups1,
    canonical1=context.canonical2,
    canonical2=context.canonical1,
  )
}

///|
/// Read one evaluated element without copying a segment during bulk initialization.
pub fn ModuleInstance::element_value(
  self : ModuleInstance,
  segment : Int32,
  index : Int32,
) -> @types.Value raise RuntimeError {
  self.ensure_live()
  guard segment >= 0 && segment < self.elem_values.length() else {
    raise UndefinedElement
  }
  guard self.elem_values[segment].get(index) is Some(value) else {
    raise UndefinedElement
  }
  value
}

///|
fn ModuleInstance::ensure_live(
  self : ModuleInstance,
) -> Unit raise RuntimeError {
  guard self.owner is Some(owner) else { raise InvalidHandle }
  if owner.val {
    raise StoreClosed
  }
  if self.store_idx < 0 {
    raise InvalidHandle
  }
}

///|
/// A call-scoped sink for the instance's authoritative segment drop flags.
pub(open) trait SegmentDropBinding {
  fn bind_segment_drop_flags(Self, FixedArray[Bool], FixedArray[Bool]) -> Unit
}
