///|
/// Label information for control flow validation
priv struct LabelInfo {
  kind : LabelKind // block or loop
  block_type : @types.BlockType
}

///|
/// Kind of control structure for label resolution
priv enum LabelKind {
  BlockLabel // br jumps to end, uses results
  LoopLabel // br jumps to start, uses params
}

///|
/// Validation context for a module
priv struct ValidationContext {
  types : Array[@types.SubType] // GC: now stores SubType
  funcs : Array[Int] // type indices
  tables : Array[@types.TableType]
  mems : Array[@types.MemoryType]
  globals : Array[@types.GlobalType]
  tags : Array[@types.FuncType] // tag types (params only, results always empty)
  elems : Array[@types.ValueType] // element segment types
  data_count : Int // number of data segments
  locals : Array[@types.ValueType] // current function's locals
  labels : Array[LabelInfo] // label stack for control flow
  returns : Array[@types.ValueType] // current function's return types
  local_init : Array[Bool] // tracks which locals have been initialized (for non-nullable refs)
  declared_funcs : @hashset.HashSet[Int] // functions declared in elem/global (for ref.func validation)
  subtyping_ctx : @types.SubtypingContext // for subtype checking
}

///|
/// Helper to get FuncType from types array at given index
fn ValidationContext::get_func_type(
  self : ValidationContext,
  idx : Int,
) -> @types.FuncType {
  match self.types[idx].composite {
    Func(ft) => ft
    _ => abort("Type at index \{idx} is not a function type")
  }
}

///|
/// Helper to get StructType from types array at given index
fn ValidationContext::get_struct_type(
  self : ValidationContext,
  idx : Int,
) -> @types.StructType {
  match self.types[idx].composite {
    Struct(st) => st
    _ => abort("Type at index \{idx} is not a struct type")
  }
}

///|
/// Helper to get ArrayType from types array at given index
fn ValidationContext::get_array_type(
  self : ValidationContext,
  idx : Int,
) -> @types.ArrayType {
  match self.types[idx].composite {
    Array(at) => at
    _ => abort("Type at index \{idx} is not an array type")
  }
}

///|
/// Convert StorageType to ValueType for validation
fn storage_type_to_value_type(
  storage_type : @types.StorageType,
) -> @types.ValueType {
  match storage_type {
    Val(vt) => vt
    Packed(_) => @types.ValueType::I32 // Packed types are accessed as i32
  }
}

///|
/// Collect all value types referenced in a SubType (for validation)
fn collect_value_types_from_subtype(
  subtype : @types.SubType,
) -> Array[@types.ValueType] {
  let result : Array[@types.ValueType] = []
  match subtype.composite {
    Func(ft) => {
      for p in ft.params {
        result.push(p)
      }
      for r in ft.results {
        result.push(r)
      }
    }
    Struct(st) =>
      for field in st.fields {
        match field.storage_type {
          Val(vt) => result.push(vt)
          Packed(_) => () // i8/i16 don't contain type indices
        }
      }
    Array(at) =>
      match at.element.storage_type {
        Val(vt) => result.push(vt)
        Packed(_) => ()
      }
  }
  result
}

///|
/// Collect function indices referenced by ref.func in an instruction sequence
fn collect_declared_funcs(
  instrs : Array[@types.Instruction],
  declared : @hashset.HashSet[Int],
) -> Unit {
  for instr in instrs {
    if instr is RefFunc(func_idx) {
      declared.add(func_idx)
    }
  }
}

///|
fn ValidationContext::new(mod : @types.Module) -> ValidationContext {
  // Collect function types (imports + defined functions)
  let funcs : Array[Int] = []
  for imp in mod.imports {
    if imp.desc is Func(type_idx) {
      funcs.push(type_idx)
    }
  }
  for type_idx in mod.funcs {
    funcs.push(type_idx)
  }
  // Collect tables
  let tables : Array[@types.TableType] = []
  for imp in mod.imports {
    if imp.desc is Table(table_type) {
      tables.push(table_type)
    }
  }
  for table in mod.tables {
    tables.push(table.type_)
  }
  // Collect memories
  let mems : Array[@types.MemoryType] = []
  for imp in mod.imports {
    if imp.desc is Memory(mem_type) {
      mems.push(mem_type)
    }
  }
  for mem in mod.memories {
    mems.push(mem)
  }
  // Collect globals
  let globals : Array[@types.GlobalType] = []
  for imp in mod.imports {
    if imp.desc is Global(global_type) {
      globals.push(global_type)
    }
  }
  for global in mod.globals {
    globals.push(global.type_)
  }
  // Collect elem segment types
  let elems : Array[@types.ValueType] = []
  for elem in mod.elems {
    elems.push(elem.type_)
  }
  // Collect tags (imports + defined tags)
  let tags : Array[@types.FuncType] = []
  for imp in mod.imports {
    if imp.desc is Tag(type_idx) {
      tags.push(mod.get_func_type(type_idx))
    }
  }
  for tag in mod.tags {
    tags.push(mod.get_func_type(tag.type_idx))
  }

  // Collect declared functions from elem segments and global inits
  let declared_funcs : @hashset.HashSet[Int] = @hashset.new()
  // Functions referenced in element segments
  for elem in mod.elems {
    for init in elem.init {
      collect_declared_funcs(init, declared_funcs)
    }
  }
  // Functions referenced in global initializers
  for global in mod.globals {
    collect_declared_funcs(global.init, declared_funcs)
  }
  {
    types: mod.types,
    funcs,
    tables,
    mems,
    globals,
    tags,
    elems,
    data_count: mod.datas.length(),
    locals: [],
    labels: [],
    returns: [],
    local_init: [],
    declared_funcs,
    subtyping_ctx: @types.SubtypingContext::same_module(mod.types),
  }
}

///|
/// Check if a value type is a non-nullable reference type
fn is_non_nullable_ref(ty : @types.ValueType) -> Bool {
  match ty {
    RefFunc | RefExtern | RefFuncTyped(_) => true
    _ => false
  }
}

///|
/// Check if a value type is any reference type (nullable or non-nullable)
fn is_ref_type(ty : @types.ValueType) -> Bool {
  match ty {
    FuncRef
    | ExternRef
    | RefFunc
    | RefExtern
    | RefFuncTyped(_)
    | RefNullFuncTyped(_) => true
    _ => false
  }
}

///|
/// Validate that any type indices in a value type are valid
fn validate_value_type(
  ty : @types.ValueType,
  num_types : Int,
) -> Unit raise ValidationError {
  let idx : Int? = match ty {
    RefFuncTyped(i) | RefNullFuncTyped(i) => Some(i)
    RefStruct(i) | RefNullStruct(i) => Some(i)
    RefArray(i) | RefNullArray(i) => Some(i)
    _ => None
  }
  if idx is Some(i) && (i < 0 || i >= num_types) {
    raise InvalidTypeIndex(i)
  }
}

///|
/// Validate that forward type references are only allowed within rec groups.
/// For a type at index `type_idx`, any reference to a type with higher index
/// must be in the same rec group.
fn validate_type_forward_refs(
  ty : @types.ValueType,
  type_idx : Int,
  type_rec_groups : Array[Int],
) -> Unit raise ValidationError {
  let ref_idx : Int? = match ty {
    RefFuncTyped(i) | RefNullFuncTyped(i) => Some(i)
    RefStruct(i) | RefNullStruct(i) => Some(i)
    RefArray(i) | RefNullArray(i) => Some(i)
    _ => None
  }
  guard ref_idx is Some(ref_idx) else { return }
  // Forward reference: ref_idx > type_idx
  if ref_idx > type_idx {
    // Must be in the same rec group
    if type_idx < type_rec_groups.length() && ref_idx < type_rec_groups.length() {
      if type_rec_groups[type_idx] != type_rec_groups[ref_idx] {
        raise UnknownType(ref_idx)
      }
    } else {
      // Type index out of bounds - this is an unknown type
      raise UnknownType(ref_idx)
    }
  }
}
