///|
/// Component runtime/linker wiring.
///
/// This implements a minimal Component Model instantiation flow and canonical
/// ABI adapters for the parsed subset of types and sections.

///|
pub(all) suberror ComponentRuntimeError {
  UnsupportedComponent(String)
  ComponentParseError(String)
  CoreModuleParseError(String)
  CoreModuleInstantiateError(String)
  InvalidUtf8
  UnknownImport(String)
  ImportTypeMismatch(String)
  UnknownExport(String)
  InvalidTypeIndex(Int)
  InvalidFuncIndex(Int)
  InvalidValueIndex(Int)
  InvalidComponentIndex(Int)
  InvalidInstanceIndex(Int)
  InvalidCoreModuleIndex(Int)
  InvalidCoreInstanceIndex(Int)
  InvalidCoreFuncIndex(Int)
  InvalidCoreTableIndex(Int)
  InvalidCoreMemoryIndex(Int)
  InvalidCoreGlobalIndex(Int)
  InvalidCoreTagIndex(Int)
  InvalidCoreTypeIndex(Int)
  InvalidTypeDef(Int)
  InvalidCanonFuncType(Int)
  MissingCanonMemory
  MissingCanonRealloc
  UnsupportedStringEncoding
  CanonCallError(String)
  HostCallError(String)
  InvalidStartResultCount(Int)
  OuterAliasOutOfRange(Int)
  AliasTargetMismatch(String)
} derive(Show, Eq)

///|
pub(all) enum ComponentValue {
  Bool(Bool)
  S8(Int)
  U8(Int)
  S16(Int)
  U16(Int)
  S32(Int)
  U32(Int)
  S64(Int64)
  U64(Int64)
  F32(Float)
  F64(Double)
  Char(Char)
  String(String)
  ErrorContext(String)
} derive(Show, Eq)

///|
pub(all) struct CoreFuncRef {
  instance : @runtime.ModuleInstance
  func_idx : Int
} derive(Show)

///|
struct CanonResources {
  mem_addr : Int?
  realloc : CoreFuncRef?
  post_return : CoreFuncRef?
  encoding : StringEncoding
} derive(Show)

///|
pub(all) enum ComponentFunc {
  Lifted(CoreFuncRef, FuncType, CanonResources)
  Host(
    FuncType,
    (Array[ComponentValue]) -> Array[ComponentValue] raise ComponentRuntimeError
  )
}

///|
pub impl Show for ComponentFunc with output(self, logger) {
  match self {
    Lifted(_, _, _) => logger.write_string("Lifted")
    Host(_, _) => logger.write_string("Host")
  }
}

///|
pub(all) struct CoreInstance {
  funcs : Map[String, CoreFuncRef]
  tables : Map[String, Int]
  memories : Map[String, Int]
  globals : Map[String, Int]
  tags : Map[String, Int]
}

///|
pub impl Show for CoreInstance with output(_self, logger) {
  logger.write_string("CoreInstance")
}

///|
/// A component value is a closure: the component binary plus the captured outer
/// environment needed to resolve `alias outer ...` when instantiated later.
pub(all) struct ComponentClosure {
  component : Component
  outer_stack : Array[ComponentInstance]
}

///|
pub impl Show for ComponentClosure with output(_self, logger) {
  logger.write_string("ComponentClosure")
}

///|
pub(all) enum ComponentExtern {
  Func(ComponentFunc)
  Value(ComponentValue)
  Type(TypeDef?)
  Component(ComponentClosure)
  Instance(ComponentInstance)
  CoreModule(@types.Module)
  CoreInstance(CoreInstance)
  CoreFunc(CoreFuncRef)
  CoreTable(Int)
  CoreMemory(Int)
  CoreGlobal(Int)
  CoreTag(Int)
  CoreType(Bytes)
}

///|
pub impl Show for ComponentExtern with output(self, logger) {
  match self {
    Func(_) => logger.write_string("Func")
    Value(_) => logger.write_string("Value")
    Type(_) => logger.write_string("Type")
    Component(_) => logger.write_string("Component")
    Instance(_) => logger.write_string("Instance")
    CoreModule(_) => logger.write_string("CoreModule")
    CoreInstance(_) => logger.write_string("CoreInstance")
    CoreFunc(_) => logger.write_string("CoreFunc")
    CoreTable(_) => logger.write_string("CoreTable")
    CoreMemory(_) => logger.write_string("CoreMemory")
    CoreGlobal(_) => logger.write_string("CoreGlobal")
    CoreTag(_) => logger.write_string("CoreTag")
    CoreType(_) => logger.write_string("CoreType")
  }
}

///|
pub(all) struct ComponentInstance {
  name : String
  types : Array[TypeDef?]
  funcs : Array[ComponentFunc]
  values : Array[ComponentValue]
  components : Array[ComponentClosure]
  instances : Array[ComponentInstance]
  core_modules : Array[@types.Module]
  core_instances : Array[CoreInstance]
  core_funcs : Array[CoreFuncRef]
  core_types : Array[Bytes]
  core_tables : Array[Int]
  core_mems : Array[Int]
  core_globals : Array[Int]
  core_tags : Array[Int]
  exports : Map[String, ComponentExtern]
  store : @runtime.Store
}

///|
pub fn ComponentInstance::get_export(
  self : ComponentInstance,
  name : String,
) -> ComponentExtern? {
  self.exports.get(name)
}

///|
pub fn ComponentInstance::call_exported_func(
  self : ComponentInstance,
  name : String,
  args : Array[ComponentValue],
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match self.exports.get(name) {
    Some(ComponentExtern::Func(func)) =>
      call_component_func(func, args, self.types, self.store)
    Some(_) => raise UnknownExport(name)
    None => raise UnknownExport(name)
  }
}

///|
pub fn ComponentInstance::get_core_instance(
  self : ComponentInstance,
  idx : Int,
) -> CoreInstance? {
  if idx < 0 || idx >= self.core_instances.length() {
    None
  } else {
    Some(self.core_instances[idx])
  }
}

///|
struct ComponentLinker {
  core_linker : @runtime.Linker
  components : Array[(String, ComponentInstance)]
  imports : Map[String, ComponentExtern]
  // Mutable counter stored in a 1-element array so methods can bump it without
  // requiring `mut self`.
  resource_id_counter : Array[Int]
}

///|
pub fn ComponentLinker::new() -> ComponentLinker {
  {
    core_linker: @runtime.Linker::new(),
    components: [],
    imports: {},
    resource_id_counter: [0],
  }
}

///|
fn ComponentLinker::alloc_resource_id(self : ComponentLinker) -> Int {
  let id = self.resource_id_counter[0]
  self.resource_id_counter[0] = id + 1
  id
}

///|
pub fn ComponentLinker::get_store(self : ComponentLinker) -> @runtime.Store {
  self.core_linker.get_store()
}

///|
pub fn ComponentLinker::register(
  self : ComponentLinker,
  name : String,
  instance : ComponentInstance,
) -> Unit {
  self.components.push((name, instance))
}

///|
pub fn ComponentLinker::get_component(
  self : ComponentLinker,
  name : String,
) -> ComponentInstance? {
  for entry in self.components {
    let (component_name, instance) = entry
    if component_name == name {
      return Some(instance)
    }
  }
  None
}

///|
pub fn ComponentLinker::add_import(
  self : ComponentLinker,
  name : String,
  ext : ComponentExtern,
) -> Unit {
  self.imports.set(name, ext)
}

///|
pub fn ComponentLinker::add_func(
  self : ComponentLinker,
  name : String,
  func_type : FuncType,
  func : (Array[ComponentValue]) -> Array[ComponentValue] raise ComponentRuntimeError,
) -> Unit {
  self.add_import(
    name,
    ComponentExtern::Func(ComponentFunc::Host(func_type, func)),
  )
}

///|
pub fn ComponentLinker::add_value(
  self : ComponentLinker,
  name : String,
  value : ComponentValue,
) -> Unit {
  self.add_import(name, ComponentExtern::Value(value))
}

///|
pub fn ComponentLinker::add_component(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> Unit {
  self.add_import(
    name,
    ComponentExtern::Component({ component, outer_stack: [] }),
  )
}

///|
pub fn ComponentLinker::add_instance(
  self : ComponentLinker,
  name : String,
  instance : ComponentInstance,
) -> Unit {
  self.add_import(name, ComponentExtern::Instance(instance))
}

///|
pub fn ComponentLinker::add_core_module(
  self : ComponentLinker,
  name : String,
  module_ : @types.Module,
) -> Unit {
  self.add_import(name, ComponentExtern::CoreModule(module_))
}

///|
pub fn ComponentLinker::add_core_instance(
  self : ComponentLinker,
  name : String,
  instance : CoreInstance,
) -> Unit {
  self.add_import(name, ComponentExtern::CoreInstance(instance))
}

///|
pub fn ComponentLinker::instantiate(
  self : ComponentLinker,
  name : String,
  component : Component,
) -> ComponentInstance raise ComponentRuntimeError {
  instantiate_component(self, name, component, {}, [])
}

///|
priv struct BuildState {
  types : Array[TypeDef?]
  funcs : Array[ComponentFunc]
  values : Array[ComponentValue]
  components : Array[ComponentClosure]
  instances : Array[ComponentInstance]
  core_modules : Array[@types.Module]
  core_instances : Array[CoreInstance]
  core_funcs : Array[CoreFuncRef]
  core_types : Array[Bytes]
  core_tables : Array[Int]
  core_mems : Array[Int]
  core_globals : Array[Int]
  core_tags : Array[Int]
  exports : Map[String, ComponentExtern]
}

///|
fn BuildState::new() -> BuildState {
  {
    types: [],
    funcs: [],
    values: [],
    components: [],
    instances: [],
    core_modules: [],
    core_instances: [],
    core_funcs: [],
    core_types: [],
    core_tables: [],
    core_mems: [],
    core_globals: [],
    core_tags: [],
    exports: {},
  }
}

///|
fn decode_utf8_runtime(bytes : Bytes) -> String raise ComponentRuntimeError {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      raise InvalidUtf8
    } else if b < 0xE0 {
      if i + 1 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      if (b2 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
      if cp < 0x80 {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      if i + 2 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 {
      if i + 3 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      let b4 = bytes[i + 3].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      raise InvalidUtf8
    }
  }
  buf.to_string()
}

///|
fn encode_utf8_string(s : String) -> Bytes {
  let bytes : Array[Byte] = []
  for c in s {
    let cp = c.to_int()
    if cp < 0x80 {
      bytes.push(cp.to_byte())
    } else if cp < 0x800 {
      bytes.push((0xC0 | (cp >> 6)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      bytes.push((0xE0 | (cp >> 12)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 | (cp >> 18)).to_byte())
      bytes.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(bytes)
}

///|
fn decode_import_name(name : ImportName) -> String raise ComponentRuntimeError {
  match name {
    Plain(bytes) => decode_utf8_runtime(bytes)
    WithVersion(bytes, ver) =>
      decode_utf8_runtime(bytes) + "@" + decode_utf8_runtime(ver)
  }
}

///|
fn decode_export_name(name : ExportName) -> String raise ComponentRuntimeError {
  match name {
    Plain(bytes) => decode_utf8_runtime(bytes)
    WithVersion(bytes, ver) =>
      decode_utf8_runtime(bytes) + "@" + decode_utf8_runtime(ver)
  }
}

///|
fn resolve_import(
  linker : ComponentLinker,
  overrides : Map[String, ComponentExtern],
  name : ImportName,
  desc : ExternDesc,
  types : Array[TypeDef?],
  core_types : Array[Bytes],
  store : @runtime.Store,
) -> ComponentExtern raise ComponentRuntimeError {
  let key = decode_import_name(name)
  let ext_opt = match overrides.get(key) {
    Some(v) => Some(v)
    None => linker.imports.get(key)
  }
  let expected = match desc {
    CoreModuleType(_) => "module"
    FuncType(_) => "function"
    Value(_) => "value"
    Type(_) => "type"
    ComponentType(_) => "component"
    InstanceType(_) => "instance"
  }
  match ext_opt {
    Some(ext) =>
      match (desc, ext) {
        (CoreModuleType(_), ComponentExtern::CoreModule(_))
        | (FuncType(_), ComponentExtern::Func(_))
        | (Value(_), ComponentExtern::Value(_))
        | (Type(_), ComponentExtern::Type(_))
        | (ComponentType(_), ComponentExtern::Component(_))
        | (InstanceType(_), ComponentExtern::Instance(_)) =>
          match (desc, ext) {
            (InstanceType(tyidx), ComponentExtern::Instance(inst)) => {
              validate_instance_import_type(key, tyidx, inst, types, core_types)
              ext
            }
            _ => ext
          }
        _ => {
          let actual = match ext {
            ComponentExtern::Func(_) => "func"
            ComponentExtern::Value(_) => "value"
            ComponentExtern::Type(_) => "type"
            ComponentExtern::Component(_) => "component"
            ComponentExtern::Instance(_) => "instance"
            ComponentExtern::CoreModule(_) => "module"
            ComponentExtern::CoreInstance(_) => "instance"
            ComponentExtern::CoreFunc(_) => "func"
            ComponentExtern::CoreTable(_) => "table"
            ComponentExtern::CoreMemory(_) => "memory"
            ComponentExtern::CoreGlobal(_) => "global"
            ComponentExtern::CoreTag(_) => "tag"
            ComponentExtern::CoreType(_) => "type"
          }
          raise ImportTypeMismatch("expected \{expected} found \{actual}")
        }
      }
    None =>
      match desc {
        InstanceType(tyidx) =>
          if tyidx >= 0 && tyidx < types.length() {
            match types[tyidx] {
              Some(TypeDef::InstanceTypeEmpty) => {
                let empty : ComponentInstance = {
                  name: "\{key}::empty",
                  types: [],
                  funcs: [],
                  values: [],
                  components: [],
                  instances: [],
                  core_modules: [],
                  core_instances: [],
                  core_funcs: [],
                  core_types: [],
                  core_tables: [],
                  core_mems: [],
                  core_globals: [],
                  core_tags: [],
                  exports: {},
                  store,
                }
                ComponentExtern::Instance(empty)
              }
              _ => raise UnknownImport(key)
            }
          } else {
            raise UnknownImport(key)
          }
        _ => raise UnknownImport(key)
      }
  }
}

///|
fn validate_instance_import_type(
  import_key : String,
  tyidx : Int,
  inst : ComponentInstance,
  types : Array[TypeDef?],
  core_types : Array[Bytes],
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= types.length() {
    raise UnknownImport(import_key)
  }
  match types[tyidx] {
    Some(TypeDef::InstanceTypeEmpty) => ()
    Some(TypeDef::InstanceType(decls)) => {
      // Instance type decls have their own local type space; we interpret a
      // minimal subset needed for resource type bounds and (alias outer ...).
      let local_types : Array[TypeDef?] = []
      let local_core_types : Array[Bytes] = []
      for d in decls {
        match d {
          InstanceDecl::CoreType(bytes) => local_core_types.push(bytes)
          InstanceDecl::AliasOuter(kind, count, idx) => {
            if count != 1 {
              raise OuterAliasOutOfRange(count)
            }
            // Alias kinds use `parse_alias_kind` encoding:
            // - Type = 0x03
            // - Core sorts are encoded as 0x100 + <core_sort>
            if kind == 0x03 {
              if idx < 0 || idx >= types.length() {
                raise InvalidTypeIndex(idx)
              }
              local_types.push(types[idx])
            } else if (kind & 0x100) != 0 {
              if idx < 0 || idx >= core_types.length() {
                raise InvalidCoreTypeIndex(idx)
              }
              local_core_types.push(core_types[idx])
            } else {
              ()
            }
          }
          InstanceDecl::AliasInstanceExport(kind, _instance_idx, _name) =>
            if kind == 0x03 {
              // Not needed for current component-spec coverage; keep the local
              // type space aligned for later indices.
              local_types.push(None)
            }
          InstanceDecl::Type(t) => local_types.push(Some(t))
          InstanceDecl::Export(name, desc) =>
            match inst.get_export(name) {
              None => raise UnknownImport(import_key)
              Some(ext) =>
                match (desc, ext) {
                  (
                    ExternDesc::CoreModuleType(tyidx),
                    ComponentExtern::CoreModule(m),
                  ) => {
                    if tyidx < 0 || tyidx >= local_core_types.length() {
                      raise ImportTypeMismatch("invalid core module type index")
                    }
                    check_core_module_against_type(m, local_core_types[tyidx])
                  }
                  (ExternDesc::FuncType(_), ComponentExtern::Func(_))
                  | (ExternDesc::Value(_), ComponentExtern::Value(_))
                  | (ExternDesc::ComponentType(_), ComponentExtern::Component(_)
                  )
                  | (ExternDesc::InstanceType(_), ComponentExtern::Instance(_)) =>
                    ()
                  (ExternDesc::Type(bound), ComponentExtern::Type(actual)) =>
                    match bound {
                      TypeBound::SubResource =>
                        match actual {
                          Some(TypeDef::ResourceType(_, _, _)) => ()
                          _ =>
                            raise ImportTypeMismatch(
                              "mismatched resource types",
                            )
                        }
                      TypeBound::Eq(ti) => {
                        if ti < 0 || ti >= local_types.length() {
                          raise ImportTypeMismatch("invalid type bound index")
                        }
                        let expected = local_types[ti]
                        match (expected, actual) {
                          (
                            Some(TypeDef::ResourceType(id1, _, _)),
                            Some(TypeDef::ResourceType(id2, _, _)),
                          ) =>
                            if id1 != id2 {
                              raise ImportTypeMismatch(
                                "mismatched resource types",
                              )
                            }
                          _ =>
                            if expected != actual {
                              raise ImportTypeMismatch(
                                "instance export type mismatch",
                              )
                            }
                        }
                      }
                    }
                  _ => raise ImportTypeMismatch("instance export type mismatch")
                }
            }
        }
      }
    }
    _ => ()
  }
}

///|
fn resolve_valtype(
  ty : ValType,
  types : Array[TypeDef?],
) -> ValType raise ComponentRuntimeError {
  match ty {
    Prim(p) => Prim(p)
    TypeIdx(idx) => {
      if idx < 0 || idx >= types.length() {
        raise InvalidTypeIndex(idx)
      }
      match types[idx] {
        Some(TypeDef::DefValType(p)) => Prim(p)
        _ => raise InvalidTypeDef(idx)
      }
    }
  }
}

///|
fn core_types_for_valtype(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Array[@types.ValueType] raise ComponentRuntimeError {
  match resolve_valtype(ty, types) {
    Prim(p) =>
      match p {
        Bool | S8 | U8 | S16 | U16 | S32 | U32 | Char => [@types.ValueType::I32]
        S64 | U64 => [@types.ValueType::I64]
        F32 => [@types.ValueType::F32]
        F64 => [@types.ValueType::F64]
        String | ErrorContext =>
          if mem_is_64 {
            [@types.ValueType::I64, @types.ValueType::I64]
          } else {
            [@types.ValueType::I32, @types.ValueType::I32]
          }
      }
    _ => raise InvalidTypeDef(-1)
  }
}

///|
fn func_type_needs_memory(
  func_type : FuncType,
  types : Array[TypeDef?],
) -> Bool raise ComponentRuntimeError {
  fn needs_memory(val_type : ValType) -> Bool raise ComponentRuntimeError {
    match resolve_valtype(val_type, types) {
      Prim(p) =>
        match p {
          String | ErrorContext => true
          _ => false
        }
      _ => false
    }
  }

  for p in func_type.params {
    if needs_memory(p.ty) {
      return true
    }
  }
  match func_type.result {
    Some(r) => needs_memory(r)
    None => false
  }
}

///|
fn resolve_canon_resources(
  opts : Array[CanonOpt],
  state : BuildState,
) -> CanonResources raise ComponentRuntimeError {
  let mut mem : Int? = None
  let mut realloc : CoreFuncRef? = None
  let mut post_return : CoreFuncRef? = None
  let mut encoding = StringEncoding::Utf8
  for opt in opts {
    match opt {
      CanonOpt::Memory(idx) => {
        if idx < 0 || idx >= state.core_mems.length() {
          raise InvalidCoreMemoryIndex(idx)
        }
        mem = Some(state.core_mems[idx])
      }
      CanonOpt::Realloc(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        realloc = Some(state.core_funcs[idx])
      }
      CanonOpt::PostReturn(idx) => {
        if idx < 0 || idx >= state.core_funcs.length() {
          raise InvalidCoreFuncIndex(idx)
        }
        post_return = Some(state.core_funcs[idx])
      }
      CanonOpt::StringEncoding(enc) => encoding = enc
      _ => ()
    }
  }
  if encoding != StringEncoding::Utf8 {
    raise UnsupportedStringEncoding
  }
  { mem_addr: mem, realloc, post_return, encoding }
}

///|
fn core_func_type_from_component(
  func_type : FuncType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> @types.FuncType raise ComponentRuntimeError {
  let params : Array[@types.ValueType] = []
  for p in func_type.params {
    for t in core_types_for_valtype(p.ty, types, mem_is_64) {
      params.push(t)
    }
  }
  let results : Array[@types.ValueType] = match func_type.result {
    Some(r) => core_types_for_valtype(r, types, mem_is_64)
    None => []
  }
  { params, results }
}

///|
fn call_core_func(
  store : @runtime.Store,
  core_func : CoreFuncRef,
  args : Array[@types.Value],
) -> Array[@types.Value] raise ComponentRuntimeError {
  @executor.call_func_by_index(
    store,
    core_func.instance,
    core_func.func_idx,
    args,
  ) catch {
    e => raise CanonCallError(e.to_string())
  }
}

///|
fn read_string_from_memory(
  mem : @runtime.Memory,
  ptr : Int,
  len : Int,
) -> String raise ComponentRuntimeError {
  let mem_len = mem.byte_len()
  if ptr < 0 || len < 0 || ptr.to_int64() + len.to_int64() > mem_len {
    raise CanonCallError("string pointer/length out of bounds of memory")
  }
  let bytes : Array[Byte] = []
  for i in 0..<len {
    let b = mem.load_byte(ptr + i) catch {
      e => raise CanonCallError(e.to_string())
    }
    bytes.push(b)
  }
  decode_utf8_runtime(Bytes::from_array(bytes))
}

///|
fn write_bytes_to_memory(
  store : @runtime.Store,
  mem : @runtime.Memory,
  realloc : CoreFuncRef,
  mem_is_64 : Bool,
  bytes : Bytes,
) -> Int raise ComponentRuntimeError {
  let len = bytes.length()
  let args : Array[@types.Value] = if mem_is_64 {
    [
      @types.Value::I64(0L),
      @types.Value::I64(0L),
      @types.Value::I64(1L),
      @types.Value::I64(len.to_int64()),
    ]
  } else {
    [
      @types.Value::I32(0),
      @types.Value::I32(0),
      @types.Value::I32(1),
      @types.Value::I32(len),
    ]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [@types.Value::I32(n)] => n
    [@types.Value::I64(n)] => n.to_int()
    _ => raise CanonCallError("invalid realloc result")
  }
  for i in 0..<bytes.length() {
    mem.store_byte(ptr + i, bytes[i]) catch {
      e => raise CanonCallError(e.to_string())
    }
  }
  ptr
}

///|
fn require_memory(
  resources : CanonResources,
  store : @runtime.Store,
) -> @runtime.Memory raise ComponentRuntimeError {
  match resources.mem_addr {
    Some(addr) =>
      store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
    None => raise MissingCanonMemory
  }
}

///|
fn trunc_u8(n : Int) -> Int {
  (n.reinterpret_as_uint() & 0xFFU).reinterpret_as_int()
}

///|
fn trunc_s8(n : Int) -> Int {
  let masked = n.reinterpret_as_uint() & 0xFFU
  if masked >= 0x80U {
    masked.reinterpret_as_int() - 0x100
  } else {
    masked.reinterpret_as_int()
  }
}

///|
fn trunc_u16(n : Int) -> Int {
  (n.reinterpret_as_uint() & 0xFFFFU).reinterpret_as_int()
}

///|
fn trunc_s16(n : Int) -> Int {
  let masked = n.reinterpret_as_uint() & 0xFFFFU
  if masked >= 0x8000U {
    masked.reinterpret_as_int() - 0x10000
  } else {
    masked.reinterpret_as_int()
  }
}

///|
fn trunc_u32(n : Int) -> Int {
  n.reinterpret_as_uint().reinterpret_as_int()
}

///|
fn component_args_to_core(
  args : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
) -> Array[@types.Value] raise ComponentRuntimeError {
  let core_args : Array[@types.Value] = []
  for i, param in func_type.params {
    let val = if i < args.length() {
      args[i]
    } else {
      raise InvalidValueIndex(i)
    }
    match resolve_valtype(param.ty, types) {
      Prim(p) =>
        match (p, val) {
          (Bool, ComponentValue::Bool(b)) =>
            core_args.push(@types.Value::I32(if b { 1 } else { 0 }))
          (S8, ComponentValue::S8(n))
          | (U8, ComponentValue::U8(n))
          | (S16, ComponentValue::S16(n))
          | (U16, ComponentValue::U16(n))
          | (S32, ComponentValue::S32(n))
          | (U32, ComponentValue::U32(n)) =>
            core_args.push(@types.Value::I32(n))
          (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
            core_args.push(@types.Value::I64(n))
          (F32, ComponentValue::F32(f)) => core_args.push(@types.Value::F32(f))
          (F64, ComponentValue::F64(f)) => core_args.push(@types.Value::F64(f))
          (Char, ComponentValue::Char(c)) =>
            core_args.push(@types.Value::I32(c.to_int()))
          (String, ComponentValue::String(s))
          | (ErrorContext, ComponentValue::ErrorContext(s)) => {
            let mem = require_memory(resources, store)
            let mem_is_64 = mem.is_memory64()
            let realloc = match resources.realloc {
              Some(r) => r
              None => raise MissingCanonRealloc
            }
            let bytes = encode_utf8_string(s)
            let ptr = write_bytes_to_memory(
              store, mem, realloc, mem_is_64, bytes,
            )
            let len = bytes.length()
            if mem_is_64 {
              core_args.push(@types.Value::I64(ptr.to_int64()))
              core_args.push(@types.Value::I64(len.to_int64()))
            } else {
              core_args.push(@types.Value::I32(ptr))
              core_args.push(@types.Value::I32(len))
            }
          }
          _ => raise HostCallError("argument type mismatch")
        }
      _ => raise HostCallError("unsupported param type")
    }
  }
  core_args
}

///|
fn core_results_to_component(
  results : Array[@types.Value],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match func_type.result {
    None => []
    Some(r) =>
      match resolve_valtype(r, types) {
        Prim(p) =>
          match p {
            Bool =>
              match results {
                [@types.Value::I32(n)] => [ComponentValue::Bool(n != 0)]
                _ => raise HostCallError("result type mismatch")
              }
            S8 | U8 | S16 | U16 | S32 | U32 | Char =>
              match results {
                [@types.Value::I32(n)] =>
                  match p {
                    Char => [ComponentValue::Char(n.unsafe_to_char())]
                    S8 => [ComponentValue::S8(trunc_s8(n))]
                    U8 => [ComponentValue::U8(trunc_u8(n))]
                    S16 => [ComponentValue::S16(trunc_s16(n))]
                    U16 => [ComponentValue::U16(trunc_u16(n))]
                    S32 => [ComponentValue::S32(n)]
                    U32 => [ComponentValue::U32(trunc_u32(n))]
                    _ => raise HostCallError("result type mismatch")
                  }
                _ => raise HostCallError("result type mismatch")
              }
            S64 | U64 =>
              match results {
                [@types.Value::I64(n)] =>
                  if p == S64 {
                    [ComponentValue::S64(n)]
                  } else {
                    [ComponentValue::U64(n)]
                  }
                _ => raise HostCallError("result type mismatch")
              }
            F32 =>
              match results {
                [@types.Value::F32(n)] => [ComponentValue::F32(n)]
                _ => raise HostCallError("result type mismatch")
              }
            F64 =>
              match results {
                [@types.Value::F64(n)] => [ComponentValue::F64(n)]
                _ => raise HostCallError("result type mismatch")
              }
            String | ErrorContext => {
              let mem = match resources.mem_addr {
                Some(addr) =>
                  store.get_mem(addr) catch {
                    e => raise CanonCallError(e.to_string())
                  }
                None => raise MissingCanonMemory
              }
              let mem_is_64 = mem.is_memory64()
              let (ptr, len) = if mem_is_64 {
                match results {
                  [@types.Value::I64(p), @types.Value::I64(l)] =>
                    (p.to_int(), l.to_int())
                  [@types.Value::I64(p)] => {
                    let base = p.to_int()
                    let ptr64 = mem.load_i64(base) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    let len64 = mem.load_i64(base + 8) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    (ptr64.to_int(), len64.to_int())
                  }
                  _ => raise HostCallError("result type mismatch")
                }
              } else {
                match results {
                  [@types.Value::I32(p), @types.Value::I32(l)] => (p, l)
                  [@types.Value::I32(p)] => {
                    let ptr32 = mem.load_i32(p) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    let len32 = mem.load_i32(p + 4) catch {
                      e => raise CanonCallError(e.to_string())
                    }
                    (ptr32, len32)
                  }
                  _ => raise HostCallError("result type mismatch")
                }
              }
              let s = read_string_from_memory(mem, ptr, len)
              if p == String {
                [ComponentValue::String(s)]
              } else {
                [ComponentValue::ErrorContext(s)]
              }
            }
          }
        _ => raise HostCallError("unsupported result type")
      }
  }
}

///|
fn core_args_to_component(
  args : Array[@types.Value],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let values : Array[ComponentValue] = []
  let mut idx = 0
  for p in func_type.params {
    match resolve_valtype(p.ty, types) {
      Prim(prim) =>
        match prim {
          Bool =>
            match args.get(idx) {
              Some(@types.Value::I32(n)) => {
                values.push(ComponentValue::Bool(n != 0))
                idx += 1
              }
              _ => raise HostCallError("argument type mismatch")
            }
          S8 | U8 | S16 | U16 | S32 | U32 | Char =>
            match args.get(idx) {
              Some(@types.Value::I32(n)) => {
                values.push(
                  match prim {
                    Char => ComponentValue::Char(n.unsafe_to_char())
                    S8 => ComponentValue::S8(trunc_s8(n))
                    U8 => ComponentValue::U8(trunc_u8(n))
                    S16 => ComponentValue::S16(trunc_s16(n))
                    U16 => ComponentValue::U16(trunc_u16(n))
                    S32 => ComponentValue::S32(n)
                    U32 => ComponentValue::U32(trunc_u32(n))
                    _ => ComponentValue::S32(n)
                  },
                )
                idx += 1
              }
              _ => raise HostCallError("argument type mismatch")
            }
          S64 | U64 =>
            match args.get(idx) {
              Some(@types.Value::I64(n)) => {
                values.push(
                  if prim == S64 {
                    ComponentValue::S64(n)
                  } else {
                    ComponentValue::U64(n)
                  },
                )
                idx += 1
              }
              _ => raise HostCallError("argument type mismatch")
            }
          F32 =>
            match args.get(idx) {
              Some(@types.Value::F32(n)) => {
                values.push(ComponentValue::F32(n))
                idx += 1
              }
              _ => raise HostCallError("argument type mismatch")
            }
          F64 =>
            match args.get(idx) {
              Some(@types.Value::F64(n)) => {
                values.push(ComponentValue::F64(n))
                idx += 1
              }
              _ => raise HostCallError("argument type mismatch")
            }
          String | ErrorContext => {
            let mem = require_memory(resources, store)
            let mem_is_64 = mem.is_memory64()
            let (ptr, len) = if mem_is_64 {
              match (args.get(idx), args.get(idx + 1)) {
                (Some(@types.Value::I64(p)), Some(@types.Value::I64(l))) =>
                  (p.to_int(), l.to_int())
                _ => raise HostCallError("argument type mismatch")
              }
            } else {
              match (args.get(idx), args.get(idx + 1)) {
                (Some(@types.Value::I32(p)), Some(@types.Value::I32(l))) =>
                  (p, l)
                _ => raise HostCallError("argument type mismatch")
              }
            }
            let s = read_string_from_memory(mem, ptr, len)
            if prim == String {
              values.push(ComponentValue::String(s))
            } else {
              values.push(ComponentValue::ErrorContext(s))
            }
            idx += 2
          }
        }
      _ => raise HostCallError("unsupported param type")
    }
  }
  values
}

///|
fn component_results_to_core(
  results : Array[ComponentValue],
  func_type : FuncType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
) -> Array[@types.Value] raise ComponentRuntimeError {
  match func_type.result {
    None => []
    Some(r) => {
      if results.length() == 0 {
        raise HostCallError("missing result")
      }
      let val = results[0]
      match resolve_valtype(r, types) {
        Prim(p) =>
          match (p, val) {
            (Bool, ComponentValue::Bool(b)) =>
              [@types.Value::I32(if b { 1 } else { 0 })]
            (S8, ComponentValue::S8(n))
            | (U8, ComponentValue::U8(n))
            | (S16, ComponentValue::S16(n))
            | (U16, ComponentValue::U16(n))
            | (S32, ComponentValue::S32(n))
            | (U32, ComponentValue::U32(n)) => [@types.Value::I32(n)]
            (S64, ComponentValue::S64(n)) | (U64, ComponentValue::U64(n)) =>
              [@types.Value::I64(n)]
            (F32, ComponentValue::F32(n)) => [@types.Value::F32(n)]
            (F64, ComponentValue::F64(n)) => [@types.Value::F64(n)]
            (Char, ComponentValue::Char(c)) => [@types.Value::I32(c.to_int())]
            (String, ComponentValue::String(s))
            | (ErrorContext, ComponentValue::ErrorContext(s)) => {
              let mem = require_memory(resources, store)
              let mem_is_64 = mem.is_memory64()
              let realloc = match resources.realloc {
                Some(rf) => rf
                None => raise MissingCanonRealloc
              }
              let bytes = encode_utf8_string(s)
              let ptr = write_bytes_to_memory(
                store, mem, realloc, mem_is_64, bytes,
              )
              let len = bytes.length()
              if mem_is_64 {
                [
                  @types.Value::I64(ptr.to_int64()),
                  @types.Value::I64(len.to_int64()),
                ]
              } else {
                [@types.Value::I32(ptr), @types.Value::I32(len)]
              }
            }
            _ => raise HostCallError("result type mismatch")
          }
        _ => raise HostCallError("unsupported result type")
      }
    }
  }
}

///|
fn call_component_func(
  func : ComponentFunc,
  args : Array[ComponentValue],
  types : Array[TypeDef?],
  store : @runtime.Store,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match func {
    ComponentFunc::Host(_func_type, host) =>
      host(args) catch {
        e => raise HostCallError(e.to_string())
      }
    ComponentFunc::Lifted(core_func, func_type, resources) => {
      if func_type_needs_memory(func_type, types) && resources.mem_addr is None {
        raise MissingCanonMemory
      }
      let core_args = component_args_to_core(
        args, func_type, types, resources, store,
      )
      let core_results = call_core_func(store, core_func, core_args)
      let component_results = core_results_to_component(
        core_results, func_type, types, resources, store,
      )
      match resources.post_return {
        Some(pr) => call_core_func(store, pr, core_results) |> ignore
        None => ()
      }
      component_results
    }
  }
}

///|
fn core_instance_from_module(
  instance : @runtime.ModuleInstance,
) -> CoreInstance {
  let funcs : Map[String, CoreFuncRef] = {}
  let tables : Map[String, Int] = {}
  let memories : Map[String, Int] = {}
  let globals : Map[String, Int] = {}
  let tags : Map[String, Int] = {}
  for exp in instance.exports {
    match exp.desc {
      @types.ExportDesc::Func(idx) =>
        funcs.set(exp.name, { instance, func_idx: idx })
      @types.ExportDesc::Table(idx) =>
        tables.set(exp.name, instance.table_addrs[idx])
      @types.ExportDesc::Memory(idx) =>
        memories.set(exp.name, instance.mem_addrs[idx])
      @types.ExportDesc::Global(idx) =>
        globals.set(exp.name, instance.global_addrs[idx])
      @types.ExportDesc::Tag(idx) => tags.set(exp.name, instance.tag_addrs[idx])
    }
  }
  { funcs, tables, memories, globals, tags }
}

///|
priv enum CoreExternType {
  Func(@types.FuncType)
  Table(@types.TableType)
  Memory(@types.MemoryType)
  Global(@types.GlobalType)
}

///|
priv struct CoreModuleTypeSpec {
  imports : Map[String, CoreExternType] // key: "<module>::<name>"
  exports : Map[String, CoreExternType] // key: "<name>"
}

///|
fn bytes_sub(bytes : Bytes, start : Int, end : Int) -> Bytes {
  let out : Array[Byte] = []
  for i in start..<end {
    out.push(bytes[i])
  }
  Bytes::from_array(out)
}

///|
fn parse_core_valtype(
  reader : Reader,
) -> @types.ValueType raise ComponentRuntimeError {
  let b = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  match b {
    0x7f => @types.ValueType::I32
    0x7e => @types.ValueType::I64
    0x7d => @types.ValueType::F32
    0x7c => @types.ValueType::F64
    0x7b => @types.ValueType::V128
    0x70 => @types.ValueType::FuncRef
    0x6f => @types.ValueType::ExternRef
    _ => raise ImportTypeMismatch("unsupported core valtype \{b}")
  }
}

///|
fn parse_limits_u32(
  reader : Reader,
) -> @types.Limits raise ComponentRuntimeError {
  let flags = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let min = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let max = if (flags & 0x01) != 0 {
    Some(
      reader.read_leb_u32() catch {
        e => raise ComponentParseError(e.to_string())
      },
    )
  } else {
    None
  }
  { min: min.to_int64(), max: max.map(fn(x) { x.to_int64() }) }
}

///|
fn parse_core_functype(
  reader : Reader,
) -> @types.FuncType raise ComponentRuntimeError {
  let form = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  if form != 0x60 {
    raise ImportTypeMismatch("invalid core functype form")
  }
  let nparams = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let params : Array[@types.ValueType] = []
  for _i in 0..<nparams {
    params.push(parse_core_valtype(reader))
  }
  let nresults = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let results : Array[@types.ValueType] = []
  for _i in 0..<nresults {
    results.push(parse_core_valtype(reader))
  }
  { params, results }
}

///|
fn parse_core_extern_type_in_moduletype(
  reader : Reader,
  kind : Int,
  func_types : Array[@types.FuncType],
) -> CoreExternType raise ComponentRuntimeError {
  match kind {
    0x00 => {
      let idx = reader.read_leb_u32() catch {
        e => raise ComponentParseError(e.to_string())
      }
      if idx < 0 || idx >= func_types.length() {
        raise ImportTypeMismatch("invalid module type func index")
      }
      CoreExternType::Func(func_types[idx])
    }
    0x01 => {
      let elem = parse_core_valtype(reader)
      let limits = parse_limits_u32(reader)
      CoreExternType::Table({ elem_type: elem, limits, is_table64: false })
    }
    0x02 => {
      let limits = parse_limits_u32(reader)
      CoreExternType::Memory({ limits, is_memory64: false, page_size_log2: 16 })
    }
    0x03 => {
      let vt = parse_core_valtype(reader)
      let mutability = reader.read_u8() catch {
        e => raise ComponentParseError(e.to_string())
      }
      CoreExternType::Global({ value_type: vt, mutable: mutability != 0 })
    }
    _ => raise ImportTypeMismatch("unsupported module type extern kind")
  }
}

///|
fn parse_core_moduletype_spec(
  core_type : Bytes,
) -> CoreModuleTypeSpec raise ComponentRuntimeError {
  let reader = Reader::new(core_type)
  let op = reader.read_u8() catch {
    e => raise ComponentParseError(e.to_string())
  }
  if op != 0x50 {
    raise ImportTypeMismatch("expected core module type")
  }
  let ndecls = reader.read_leb_u32() catch {
    e => raise ComponentParseError(e.to_string())
  }
  let func_types : Array[@types.FuncType] = []
  let imports : Map[String, CoreExternType] = {}
  let exports : Map[String, CoreExternType] = {}
  for _i in 0..<ndecls {
    let tag = reader.read_u8() catch {
      e => raise ComponentParseError(e.to_string())
    }
    match tag {
      0x00 => {
        let mod_name = reader.read_name() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let name = reader.read_name() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let kind = reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let ty = parse_core_extern_type_in_moduletype(reader, kind, func_types)
        imports.set("\{mod_name}::\{name}", ty)
      }
      0x01 => func_types.push(parse_core_functype(reader))
      0x02 => {
        // alias decl: sort + target + indices (skip)
        (reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        })
        |> ignore
        let target = reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        }
        if target == 0x01 {
          (reader.read_leb_u32() catch {
            e => raise ComponentParseError(e.to_string())
          })
          |> ignore
          (reader.read_leb_u32() catch {
            e => raise ComponentParseError(e.to_string())
          })
          |> ignore
        } else {
          raise ImportTypeMismatch("unsupported module type alias target")
        }
      }
      0x03 => {
        let name = reader.read_name() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let kind = reader.read_u8() catch {
          e => raise ComponentParseError(e.to_string())
        }
        let ty = parse_core_extern_type_in_moduletype(reader, kind, func_types)
        exports.set(name, ty)
      }
      _ => raise ImportTypeMismatch("invalid module type declaration")
    }
  }
  if !reader.is_eof() {
    raise ImportTypeMismatch("invalid module type")
  }
  { imports, exports }
}

///|
fn core_extern_kind_name(ty : CoreExternType) -> String {
  match ty {
    Func(_) => "func"
    Table(_) => "table"
    Memory(_) => "memory"
    Global(_) => "global"
  }
}

///|
fn fmt_valtype(vt : @types.ValueType) -> String {
  match vt {
    @types.ValueType::I32 => "i32"
    @types.ValueType::I64 => "i64"
    @types.ValueType::F32 => "f32"
    @types.ValueType::F64 => "f64"
    @types.ValueType::V128 => "v128"
    @types.ValueType::FuncRef => "funcref"
    @types.ValueType::ExternRef => "externref"
    _ => "unknown"
  }
}

///|
fn fmt_functype(ft : @types.FuncType) -> String {
  let buf = StringBuilder::new()
  buf.write_string("(func")
  if ft.params.length() > 0 {
    buf.write_string(" (param")
    for p in ft.params {
      buf.write_string(" ")
      buf.write_string(fmt_valtype(p))
    }
    buf.write_string(")")
  }
  if ft.results.length() > 0 {
    buf.write_string(" (result")
    for r in ft.results {
      buf.write_string(" ")
      buf.write_string(fmt_valtype(r))
    }
    buf.write_string(")")
  }
  buf.write_string(")")
  buf.to_string()
}

///|
fn module_export_type(m : @types.Module, name : String) -> CoreExternType? {
  for e in m.exports {
    if e.name == name {
      match e.desc {
        @types.ExportDesc::Func(func_idx) => {
          let tyidx = m.funcs[func_idx]
          return Some(CoreExternType::Func(m.get_func_type(tyidx)))
        }
        @types.ExportDesc::Table(table_idx) =>
          return Some(CoreExternType::Table(m.tables[table_idx].type_))
        @types.ExportDesc::Memory(mem_idx) =>
          return Some(CoreExternType::Memory(m.memories[mem_idx]))
        @types.ExportDesc::Global(global_idx) =>
          return Some(CoreExternType::Global(m.globals[global_idx].type_))
        _ => return None
      }
    }
  }
  None
}

///|
fn module_import_type(
  m : @types.Module,
  mod_name : String,
  name : String,
) -> CoreExternType? {
  for imp in m.imports {
    if imp.mod_name == mod_name && imp.name == name {
      match imp.desc {
        @types.ImportDesc::Func(tyidx) =>
          return Some(CoreExternType::Func(m.get_func_type(tyidx)))
        @types.ImportDesc::Table(tt) => return Some(CoreExternType::Table(tt))
        @types.ImportDesc::Memory(mt) => return Some(CoreExternType::Memory(mt))
        @types.ImportDesc::Global(gt) => return Some(CoreExternType::Global(gt))
        _ => return None
      }
    }
  }
  None
}

///|
fn table_import_compatible(
  actual : @types.TableType,
  expected : @types.TableType,
) -> Bool {
  // Imports are contravariant in limits: requiring fewer is a subtype.
  actual.elem_type == expected.elem_type &&
  actual.limits.min <= expected.limits.min
}

///|
fn table_export_compatible(
  actual : @types.TableType,
  expected : @types.TableType,
) -> Bool {
  // Exports are covariant in limits: providing more is a subtype.
  actual.elem_type == expected.elem_type &&
  actual.limits.min >= expected.limits.min
}

///|
fn memory_import_compatible(
  actual : @types.MemoryType,
  expected : @types.MemoryType,
) -> Bool {
  actual.is_memory64 == expected.is_memory64 &&
  actual.page_size_log2 == expected.page_size_log2 &&
  actual.limits.min <= expected.limits.min
}

///|
fn memory_export_compatible(
  actual : @types.MemoryType,
  expected : @types.MemoryType,
) -> Bool {
  actual.is_memory64 == expected.is_memory64 &&
  actual.page_size_log2 == expected.page_size_log2 &&
  actual.limits.min >= expected.limits.min
}

///|
fn check_core_module_against_type(
  actual : @types.Module,
  core_type : Bytes,
) -> Unit raise ComponentRuntimeError {
  let spec = parse_core_moduletype_spec(core_type)
  // Actual module imports must all be declared in the module type.
  for imp in actual.imports {
    let key = "\{imp.mod_name}::\{imp.name}"
    match spec.imports.get(key) {
      None => raise ImportTypeMismatch("module import `\{key}` not defined")
      Some(expected) => {
        let actual_ty = match
          module_import_type(actual, imp.mod_name, imp.name) {
          Some(t) => t
          None =>
            raise ImportTypeMismatch(
              "module import `\{key}` has the wrong type",
            )
        }
        match (expected, actual_ty) {
          (CoreExternType::Func(ft1), CoreExternType::Func(ft2)) =>
            if ft1 != ft2 {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (CoreExternType::Global(gt1), CoreExternType::Global(gt2)) =>
            if gt1 != gt2 {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (CoreExternType::Table(tt1), CoreExternType::Table(tt2)) =>
            if !table_import_compatible(tt2, tt1) {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (CoreExternType::Memory(mt1), CoreExternType::Memory(mt2)) =>
            if !memory_import_compatible(mt2, mt1) {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          _ =>
            raise ImportTypeMismatch(
              // For module imports, the module's actual import requirement is
              // the "expected" shape, and the module type describes what was
              // actually specified.
              "expected \{core_extern_kind_name(actual_ty)} found \{core_extern_kind_name(expected)}",
            )
        }
      }
    }
  }
  // Module type exports must all exist in the actual module.
  for entry in spec.exports {
    let (name, expected) = entry
    match module_export_type(actual, name) {
      None => raise ImportTypeMismatch("module export `\{name}` not defined")
      Some(actual_ty) =>
        match (expected, actual_ty) {
          (CoreExternType::Func(ft1), CoreExternType::Func(ft2)) =>
            if ft1 != ft2 {
              raise ImportTypeMismatch(
                "export `\{name}` has the wrong type (expected type `\{fmt_functype(ft1)}`, found type `\{fmt_functype(ft2)}`)",
              )
            }
          (CoreExternType::Global(gt1), CoreExternType::Global(gt2)) =>
            if gt1 != gt2 {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          (CoreExternType::Table(tt1), CoreExternType::Table(tt2)) =>
            if !table_export_compatible(tt2, tt1) {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          (CoreExternType::Memory(mt1), CoreExternType::Memory(mt2)) =>
            if !memory_export_compatible(mt2, mt1) {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          _ =>
            raise ImportTypeMismatch(
              "expected \{core_extern_kind_name(expected)} found \{core_extern_kind_name(actual_ty)}",
            )
        }
    }
  }
}

///|
fn resolve_sortidx(
  sortidx : SortIdx,
  state : BuildState,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Sort::Func =>
      if idx < 0 || idx >= state.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        ComponentExtern::Func(state.funcs[idx])
      }
    Sort::Value =>
      if idx < 0 || idx >= state.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        ComponentExtern::Value(state.values[idx])
      }
    Sort::Type =>
      if idx < 0 || idx >= state.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        ComponentExtern::Type(state.types[idx])
      }
    Sort::Component =>
      if idx < 0 || idx >= state.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        ComponentExtern::Component(state.components[idx])
      }
    Sort::Instance =>
      if idx < 0 || idx >= state.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        ComponentExtern::Instance(state.instances[idx])
      }
    Sort::Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= state.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            ComponentExtern::CoreFunc(state.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= state.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            ComponentExtern::CoreTable(state.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= state.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            ComponentExtern::CoreMemory(state.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= state.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            ComponentExtern::CoreGlobal(state.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= state.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            ComponentExtern::CoreTag(state.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= state.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            ComponentExtern::CoreType(state.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= state.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            ComponentExtern::CoreModule(state.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= state.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            ComponentExtern::CoreInstance(state.core_instances[idx])
          }
        _ => raise AliasTargetMismatch("unsupported core sort")
      }
  }
}

///|
fn resolve_sortidx_in_instance(
  sortidx : SortIdx,
  inst : ComponentInstance,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Sort::Func =>
      if idx < 0 || idx >= inst.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        ComponentExtern::Func(inst.funcs[idx])
      }
    Sort::Value =>
      if idx < 0 || idx >= inst.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        ComponentExtern::Value(inst.values[idx])
      }
    Sort::Type =>
      if idx < 0 || idx >= inst.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        ComponentExtern::Type(inst.types[idx])
      }
    Sort::Component =>
      if idx < 0 || idx >= inst.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        ComponentExtern::Component(inst.components[idx])
      }
    Sort::Instance =>
      if idx < 0 || idx >= inst.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        ComponentExtern::Instance(inst.instances[idx])
      }
    Sort::Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= inst.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            ComponentExtern::CoreFunc(inst.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= inst.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            ComponentExtern::CoreTable(inst.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= inst.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            ComponentExtern::CoreMemory(inst.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= inst.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            ComponentExtern::CoreGlobal(inst.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= inst.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            ComponentExtern::CoreTag(inst.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= inst.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            ComponentExtern::CoreType(inst.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= inst.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            ComponentExtern::CoreModule(inst.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= inst.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            ComponentExtern::CoreInstance(inst.core_instances[idx])
          }
        _ => raise AliasTargetMismatch("unsupported core sort")
      }
  }
}

///|
fn append_alias(
  sort : Sort,
  ext : ComponentExtern,
  state : BuildState,
) -> Unit raise ComponentRuntimeError {
  match (sort, ext) {
    (Sort::Func, ComponentExtern::Func(f)) => state.funcs.push(f)
    (Sort::Value, ComponentExtern::Value(v)) => state.values.push(v)
    (Sort::Type, ComponentExtern::Type(t)) => state.types.push(t)
    (Sort::Component, ComponentExtern::Component(c)) => state.components.push(c)
    (Sort::Instance, ComponentExtern::Instance(i)) => state.instances.push(i)
    (Sort::Core(core_sort), ComponentExtern::CoreFunc(f)) =>
      if core_sort == 0x00 {
        state.core_funcs.push(f)
      } else {
        raise AliasTargetMismatch("core func")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreTable(t)) =>
      if core_sort == 0x01 {
        state.core_tables.push(t)
      } else {
        raise AliasTargetMismatch("core table")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreMemory(m)) =>
      if core_sort == 0x02 {
        state.core_mems.push(m)
      } else {
        raise AliasTargetMismatch("core memory")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreGlobal(g)) =>
      if core_sort == 0x03 {
        state.core_globals.push(g)
      } else {
        raise AliasTargetMismatch("core global")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreTag(t)) =>
      if core_sort == 0x04 {
        state.core_tags.push(t)
      } else {
        raise AliasTargetMismatch("core tag")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreType(t)) =>
      if core_sort == 0x05 || core_sort == 0x10 {
        state.core_types.push(t)
      } else {
        raise AliasTargetMismatch("core type")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreModule(m)) =>
      if core_sort == 0x11 {
        state.core_modules.push(m)
      } else {
        raise AliasTargetMismatch("core module")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreInstance(i)) =>
      if core_sort == 0x12 {
        state.core_instances.push(i)
      } else {
        raise AliasTargetMismatch("core instance")
      }
    _ => raise AliasTargetMismatch("sort mismatch")
  }
}

///|
fn resolve_outer_alias(
  outer_stack : Array[ComponentInstance],
  depth : Int,
  sort : Sort,
  idx : Int,
) -> ComponentExtern raise ComponentRuntimeError {
  if depth < 0 || depth >= outer_stack.length() {
    raise OuterAliasOutOfRange(depth)
  }
  let outer = outer_stack[outer_stack.length() - 1 - depth]
  resolve_sortidx_in_instance({ sort, idx }, outer)
}

///|
fn extend_outer_stack(
  outer_stack : Array[ComponentInstance],
  env : ComponentInstance,
) -> Array[ComponentInstance] {
  let stack : Array[ComponentInstance] = []
  for s in outer_stack {
    stack.push(s)
  }
  stack.push(env)
  stack
}

///|
fn env_instance_from_state(
  name : String,
  state : BuildState,
  store : @runtime.Store,
) -> ComponentInstance {
  {
    name,
    types: state.types,
    funcs: state.funcs,
    values: state.values,
    components: state.components,
    instances: state.instances,
    core_modules: state.core_modules,
    core_instances: state.core_instances,
    core_funcs: state.core_funcs,
    core_types: state.core_types,
    core_tables: state.core_tables,
    core_mems: state.core_mems,
    core_globals: state.core_globals,
    core_tags: state.core_tags,
    exports: state.exports,
    store,
  }
}

///|
fn build_inline_core_instance(
  exports : Array[CoreInlineExport],
  state : BuildState,
) -> CoreInstance raise ComponentRuntimeError {
  let funcs : Map[String, CoreFuncRef] = {}
  let tables : Map[String, Int] = {}
  let memories : Map[String, Int] = {}
  let globals : Map[String, Int] = {}
  let tags : Map[String, Int] = {}
  for ex in exports {
    match resolve_sortidx(ex.sortidx, state) {
      ComponentExtern::CoreFunc(f) => funcs.set(ex.name, f)
      ComponentExtern::CoreTable(t) => tables.set(ex.name, t)
      ComponentExtern::CoreMemory(m) => memories.set(ex.name, m)
      ComponentExtern::CoreGlobal(g) => globals.set(ex.name, g)
      ComponentExtern::CoreTag(t) => tags.set(ex.name, t)
      _ => raise AliasTargetMismatch("inline core export")
    }
  }
  { funcs, tables, memories, globals, tags }
}

///|
fn split_core_import_name(name : String) -> (String, String) {
  let mut sep_idx = -1
  for i in 0..<name.length() {
    if i + 1 < name.length() &&
      name.code_unit_at(i) == ':' &&
      name.code_unit_at(i + 1) == ':' {
      sep_idx = i
    }
  }
  if sep_idx >= 0 {
    let mod_name = try! name[0:sep_idx].to_string()
    let field = try! name[sep_idx + 2:].to_string()
    (mod_name, field)
  } else {
    ("", name)
  }
}

///|
fn core_imports_from_args(
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> @runtime.Imports raise ComponentRuntimeError {
  let imports = @runtime.Imports::new()
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      ComponentExtern::CoreInstance(inst) => {
        // `with "mod" (instance ...)` supplies a whole namespace for core imports.
        let mod_name = arg.name
        for kv in inst.funcs.iter() {
          let (field, f) = kv
          imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
        }
        for kv in inst.tables.iter() {
          let (field, t) = kv
          imports.add_table(mod_name, field, t)
        }
        for kv in inst.memories.iter() {
          let (field, m) = kv
          imports.add_memory(mod_name, field, m)
        }
        for kv in inst.globals.iter() {
          let (field, g) = kv
          imports.add_global(mod_name, field, g)
        }
        for kv in inst.tags.iter() {
          let (field, t) = kv
          imports.add_tag(mod_name, field, t)
        }
      }
      ComponentExtern::CoreFunc(f) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
      }
      ComponentExtern::CoreTable(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_table(mod_name, field, t)
      }
      ComponentExtern::CoreMemory(m) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_memory(mod_name, field, m)
      }
      ComponentExtern::CoreGlobal(g) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_global(mod_name, field, g)
      }
      ComponentExtern::CoreTag(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_tag(mod_name, field, t)
      }
      _ => raise AliasTargetMismatch("core instantiate arg")
    }
  }
  imports
}

///|
fn instantiate_component(
  linker : ComponentLinker,
  name : String,
  component : Component,
  overrides : Map[String, ComponentExtern],
  outer_stack : Array[ComponentInstance],
) -> ComponentInstance raise ComponentRuntimeError {
  let state = BuildState::new()
  let store = linker.get_store()
  for section in component.binary.sections {
    match section.id {
      1 => {
        let core_module = @parser.parse_module(section.payload) catch {
          e => raise CoreModuleParseError(e.to_string())
        }
        state.core_modules.push(core_module)
      }
      2 => {
        let core_instances = parse_core_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in core_instances {
          match inst.expr {
            CoreInstanceExpr::Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= state.core_modules.length() {
                raise InvalidCoreModuleIndex(module_idx)
              }
              let imports = core_imports_from_args(args, state)
              let mod_ = state.core_modules[module_idx]
              let module_name = "\{name}::coreinst\{state.core_instances.length()}"
              let instance = @executor.instantiate_module_with_imports(
                store, mod_, imports,
              ) catch {
                e => raise CoreModuleInstantiateError(e.to_string())
              }
              linker.core_linker.register(module_name, instance)
              state.core_instances.push(core_instance_from_module(instance))
            }
            CoreInstanceExpr::InlineExports(exports) =>
              state.core_instances.push(
                build_inline_core_instance(exports, state),
              )
          }
        }
      }
      3 => {
        // Core type section payload is a vec of core typedefs; store each
        // typedef's raw bytes so core:typeidx references work correctly.
        let reader = Reader::new(section.payload)
        let n = reader.read_leb_u32() catch {
          e => raise ComponentParseError(e.to_string())
        }
        for _i in 0..<n {
          let start = reader.pos
          skip_core_typedef(reader) catch {
            e => raise ComponentParseError(e.to_string())
          }
          let end = reader.pos
          state.core_types.push(bytes_sub(section.payload, start, end))
        }
        if !reader.is_eof() {
          raise ComponentParseError("invalid core type section")
        }
      }
      4 => {
        let nested = parse_component(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        let env = env_instance_from_state("\{name}::env", state, store)
        state.components.push({
          component: nested,
          outer_stack: extend_outer_stack(outer_stack, env),
        })
      }
      5 => {
        let instances = parse_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in instances {
          match inst.expr {
            InstanceExpr::Instantiate(component_idx, args) => {
              if component_idx < 0 || component_idx >= state.components.length() {
                raise InvalidComponentIndex(component_idx)
              }
              let closure = state.components[component_idx]
              let overrides_for_child : Map[String, ComponentExtern] = {}
              for arg in args {
                let ext = resolve_sortidx(arg.sortidx, state)
                overrides_for_child.set(arg.name, ext)
              }
              let nested = instantiate_component(
                linker,
                "\{name}::component\{component_idx}",
                closure.component,
                overrides_for_child,
                closure.outer_stack,
              )
              state.instances.push(nested)
            }
            InstanceExpr::InlineExports(exports) => {
              let export_map : Map[String, ComponentExtern] = {}
              for ex in exports {
                let ext = resolve_sortidx(ex.sortidx, state)
                export_map.set(ex.name, ext)
              }
              let inline_inst : ComponentInstance = {
                name: "\{name}::inline\{state.instances.length()}",
                types: state.types,
                funcs: state.funcs,
                values: state.values,
                components: state.components,
                instances: [],
                core_modules: state.core_modules,
                core_instances: state.core_instances,
                core_funcs: state.core_funcs,
                core_types: state.core_types,
                core_tables: state.core_tables,
                core_mems: state.core_mems,
                core_globals: state.core_globals,
                core_tags: state.core_tags,
                exports: export_map,
                store,
              }
              state.instances.push(inline_inst)
            }
          }
        }
      }
      6 => {
        let aliases = parse_alias_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for alias_decl in aliases {
          let ext = match alias_decl.target {
            AliasTarget::Export(instance_idx, name) => {
              if instance_idx < 0 || instance_idx >= state.instances.length() {
                raise InvalidInstanceIndex(instance_idx)
              }
              match state.instances[instance_idx].exports.get(name) {
                Some(v) => v
                None => raise UnknownExport(name)
              }
            }
            AliasTarget::CoreExport(core_inst_idx, name) => {
              if core_inst_idx < 0 ||
                core_inst_idx >= state.core_instances.length() {
                raise InvalidCoreInstanceIndex(core_inst_idx)
              }
              let core_inst = state.core_instances[core_inst_idx]
              match alias_decl.sort {
                Sort::Core(0x00) =>
                  match core_inst.funcs.get(name) {
                    Some(v) => ComponentExtern::CoreFunc(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x01) =>
                  match core_inst.tables.get(name) {
                    Some(v) => ComponentExtern::CoreTable(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x02) =>
                  match core_inst.memories.get(name) {
                    Some(v) => ComponentExtern::CoreMemory(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x03) =>
                  match core_inst.globals.get(name) {
                    Some(v) => ComponentExtern::CoreGlobal(v)
                    None => raise UnknownExport(name)
                  }
                Sort::Core(0x04) =>
                  match core_inst.tags.get(name) {
                    Some(v) => ComponentExtern::CoreTag(v)
                    None => raise UnknownExport(name)
                  }
                _ => raise AliasTargetMismatch("core export sort")
              }
            }
            AliasTarget::Outer(ct, idx) =>
              resolve_outer_alias(
                extend_outer_stack(
                  outer_stack,
                  env_instance_from_state("\{name}::env", state, store),
                ),
                ct,
                alias_decl.sort,
                idx,
              )
          }
          append_alias(alias_decl.sort, ext, state)
        }
      }
      7 => {
        let types = parse_type_section(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        for t in types {
          let t2 = match t {
            TypeDef::ResourceType(id, rep, dtor) =>
              if id < 0 {
                TypeDef::ResourceType(linker.alloc_resource_id(), rep, dtor)
              } else {
                t
              }
            _ => t
          }
          state.types.push(Some(t2))
        }
      }
      8 => {
        let canons = parse_canon_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for c in canons {
          match c {
            Canon::Lift(core_func_idx, opts, type_idx) => {
              if core_func_idx < 0 || core_func_idx >= state.core_funcs.length() {
                raise InvalidCoreFuncIndex(core_func_idx)
              }
              if type_idx < 0 || type_idx >= state.types.length() {
                raise InvalidTypeIndex(type_idx)
              }
              let td = state.types[type_idx]
              let func_type = match td {
                Some(TypeDef::FuncType(ft)) => ft
                _ => raise InvalidCanonFuncType(type_idx)
              }
              let resources = resolve_canon_resources(opts, state)
              state.funcs.push(
                ComponentFunc::Lifted(
                  state.core_funcs[core_func_idx],
                  func_type,
                  resources,
                ),
              )
            }
            Canon::Lower(func_idx, opts) => {
              if func_idx < 0 || func_idx >= state.funcs.length() {
                raise InvalidFuncIndex(func_idx)
              }
              let func = state.funcs[func_idx]
              let func_type = match func {
                ComponentFunc::Host(ft, _) => ft
                ComponentFunc::Lifted(_, ft, _) => ft
              }
              let resources = resolve_canon_resources(opts, state)
              if func_type_needs_memory(func_type, state.types) &&
                resources.mem_addr is None {
                raise MissingCanonMemory
              }
              let mem = match resources.mem_addr {
                Some(addr) =>
                  store.get_mem(addr) catch {
                    e => raise CanonCallError(e.to_string())
                  }
                None => @runtime.Memory::new(0, None)
              }
              let core_type = core_func_type_from_component(
                func_type,
                state.types,
                mem.is_memory64(),
              )
              let host = fn(
                args : Array[@types.Value],
              ) -> Array[@types.Value] raise @runtime.RuntimeError {
                let component_args = core_args_to_component(
                  args,
                  func_type,
                  state.types,
                  resources,
                  store,
                ) catch {
                  _ => raise @runtime.RuntimeError::Unreachable
                }
                let results = call_component_func(
                  func,
                  component_args,
                  state.types,
                  store,
                ) catch {
                  _ => raise @runtime.RuntimeError::Unreachable
                }
                component_results_to_core(
                  results,
                  func_type,
                  state.types,
                  resources,
                  store,
                ) catch {
                  _ => raise @runtime.RuntimeError::Unreachable
                }
              }
              let func_addr = store.alloc_host_func(
                host,
                func_type=core_type,
                type_idx=0,
              )
              let instance : @runtime.ModuleInstance = {
                types: [@types.SubType::from_func(core_type)],
                type_rec_groups: [],
                canonical_type_indices: [0],
                store_idx: -1,
                func_addrs: [func_addr],
                func_type_indices: [0],
                table_addrs: [],
                mem_addrs: [],
                global_addrs: [],
                tag_addrs: [],
                exports: [],
                elem_segments: [],
                data_segments: [],
                dropped_elems: [],
                dropped_datas: [],
              }
              state.core_funcs.push({ instance, func_idx: 0 })
            }
            _ => ()
          }
        }
      }
      9 => {
        let start = parse_start_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        if start.func_idx < 0 || start.func_idx >= state.funcs.length() {
          raise InvalidFuncIndex(start.func_idx)
        }
        let args : Array[ComponentValue] = []
        for idx in start.args {
          if idx < 0 || idx >= state.values.length() {
            raise InvalidValueIndex(idx)
          }
          args.push(state.values[idx])
        }
        let results = call_component_func(
          state.funcs[start.func_idx],
          args,
          state.types,
          store,
        )
        if results.length() != start.results {
          raise InvalidStartResultCount(results.length())
        }
        for r in results {
          state.values.push(r)
        }
      }
      10 => {
        let imports = parse_import_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for imp in imports {
          let ext = resolve_import(
            linker,
            overrides,
            imp.name,
            imp.desc,
            state.types,
            state.core_types,
            store,
          )
          match imp.desc {
            ExternDesc::CoreModuleType(_) =>
              match ext {
                ComponentExtern::CoreModule(m) => state.core_modules.push(m)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::FuncType(_) =>
              match ext {
                ComponentExtern::Func(f) => state.funcs.push(f)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::Value(_) =>
              match ext {
                ComponentExtern::Value(v) => state.values.push(v)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::Type(_) =>
              match ext {
                ComponentExtern::Type(t) => state.types.push(t)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::ComponentType(_) =>
              match ext {
                ComponentExtern::Component(c) => state.components.push(c)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ExternDesc::InstanceType(_) =>
              match ext {
                ComponentExtern::Instance(i) => state.instances.push(i)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
          }
        }
      }
      11 => {
        let exports = parse_export_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for exp in exports {
          let name = decode_export_name(exp.name)
          let ext = resolve_sortidx(exp.sortidx, state)
          state.exports.set(name, ext)
          append_alias(exp.sortidx.sort, ext, state)
        }
      }
      _ => ()
    }
  }
  let instance : ComponentInstance = {
    name,
    types: state.types,
    funcs: state.funcs,
    values: state.values,
    components: state.components,
    instances: state.instances,
    core_modules: state.core_modules,
    core_instances: state.core_instances,
    core_funcs: state.core_funcs,
    core_types: state.core_types,
    core_tables: state.core_tables,
    core_mems: state.core_mems,
    core_globals: state.core_globals,
    core_tags: state.core_tags,
    exports: state.exports,
    store,
  }
  linker.register(name, instance)
  instance
}
