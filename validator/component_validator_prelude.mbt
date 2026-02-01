///|
/// WebAssembly Component Model validator (partial).
///
/// This currently focuses on:
/// - basic typeidx bounds checks for parsed component types/imports/exports/canon
/// - basic index-space bounds checks for export/alias/instance references
///
/// It is intentionally incomplete; as runtime/linker work lands we can grow this
/// into a full spec-compliant validator.

///|
pub(all) suberror ComponentValidationError {
  InvalidTypeIndex(Int)
  TypeIndexNotFuncType(Int)
  TypeIndexNotComponentType(Int)
  TypeIndexNotInstanceType(Int)
  TypeIndexNotDefinedType(Int)
  TypeIndexNotResourceType(Int)
  InvalidFuncIndex(Int)
  InvalidValueIndex(Int)
  InvalidComponentIndex(Int)
  InvalidInstanceIndex(Int)
  InvalidCoreFuncIndex(Int)
  InvalidCoreModuleIndex(Int)
  InvalidCoreInstanceIndex(Int)
  InvalidCoreTypeIndex(Int)
  CoreTypeIndexNotModuleType(Int)
  InvalidCoreTableIndex(Int)
  InvalidCoreMemoryIndex(Int)
  InvalidCoreGlobalIndex(Int)
  InvalidCoreTagIndex(Int)
  DuplicateCanonOption(String)
  MissingCanonOption(String)
  CanonExpectedFuncType(Int)
  CanonAsyncTypeMismatch(Int)
  CanonMemoryNot32Bit(Int)
  CanonCoreFuncTypeMismatch(String)
  CanonOptionNotAllowed(String)
  UnsupportedCoreSort(Int)
  UnsupportedComponentImport
  UnsupportedComponentExport
  ExportedImportedFunc(Int)
  InvalidKebabName(String)
  DuplicateImportName(String)
  DuplicateExportName(String)
  FuncParamNameConflict(String, String)
  DuplicateInstantiationArg(String)
  MissingInstanceExport(Int, String)
  MissingCoreInstanceExport(Int, String)
  MissingComponentImport(String)
  ComponentImportTypeMismatch(String)
  MissingExpectedExport(String)
  AscribedExportTypeIncompatible
  AliasTargetMismatch(String)
  SectionParseError(Int, String)
  CoreModuleError(String)
} derive(Show, Eq)

///|
/// Validation knobs for component-model validation.
///
/// This validator currently mixes:
/// - generic component-model structural validation, and
/// - wasm-tools' WIT-encoding-specific name rules (kebab-case / package names).
///
/// Some upstream suites (e.g. wasmtime) use non-kebab import names like "I1".
/// Keep this configurable so we can validate both suites.
pub struct ComponentValidationConfig {
  wit_names : Bool
}

///|
pub fn ComponentValidationConfig::new(
  wit_names : Bool,
) -> ComponentValidationConfig {
  { wit_names, }
}

///|
pub fn ComponentValidationConfig::default() -> ComponentValidationConfig {
  { wit_names: true }
}

///|
priv struct Counts {
  mut func : Int
  mut value : Int
  mut component : Int
  mut instance : Int
  mut core_func : Int
  mut core_module : Int
  mut core_instance : Int
  mut core_type : Int
  mut core_table : Int
  mut core_memory : Int
  mut core_global : Int
  mut core_tag : Int
}

///|
priv enum CoreExternType {
  Func(@types.FuncType)
  Table(@types.TableType)
  Memory(@types.MemoryType)
  Global(@types.GlobalType)
}

///|
/// Core module type import signature extracted from the component core-type section.
priv struct CoreModuleTypeImport {
  mod_name : String
  name : String
  ty : CoreExternType
}

///|
priv struct InstanceSig {
  exports : Map[String, @component.Sort]
  nested : Map[String, InstanceSig]
}

///|
priv struct ParamShape {
  name : String
  ty : TypeSig
} derive(Eq)

///|
priv struct FuncSigShape {
  params : Array[ParamShape]
  result : TypeSig?
} derive(Eq)

///|
priv enum ExportedTypeInfo {
  Existing(Int)
  Resource(Int)
  Opaque
}

///|
/// Structural signature for type imports (used to validate instantiation args).
priv enum TypeSig {
  Prim(@component.PrimValType)
  Tuple(Array[TypeSig])
  Record(Array[TypeFieldSig])
  Variant(Array[TypeCaseSig])
  Option(TypeSig)
  Result(TypeSig?, TypeSig?)
  List(TypeSig)
  Flags(Array[String])
  Enum(Array[String])
  Resource(Int)
  Other
} derive(Show, Eq)

///|
priv struct TypeFieldSig {
  name : String
  ty : TypeSig
} derive(Show, Eq)

///|
priv struct TypeCaseSig {
  name : String
  ty : TypeSig?
} derive(Show, Eq)

///|
fn typeidx_of_typesig(
  sig : TypeSig,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
) -> Int? {
  for i in 0..<type_table.length() {
    if type_sig_of_typeidx(i, type_table, resource_ids) == sig {
      return Some(i)
    }
  }
  None
}

///|
fn valtype_of_typesig(
  sig : TypeSig,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
) -> @component.ValType? {
  match sig {
    TypeSig::Prim(p) => Some(@component.ValType::Prim(p))
    _ =>
      match typeidx_of_typesig(sig, type_table, resource_ids) {
        Some(idx) => Some(@component.ValType::TypeIdx(idx))
        None => None
      }
  }
}

///|
fn typedef_of_typesig(
  sig : TypeSig,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
) -> @component.TypeDef? {
  match sig {
    TypeSig::Prim(p) => Some(@component.TypeDef::DefValType(p))
    TypeSig::Tuple(ts) => {
      let out : Array[@component.ValType] = []
      for t in ts {
        match valtype_of_typesig(t, type_table, resource_ids) {
          Some(v) => out.push(v)
          None => return None
        }
      }
      Some(@component.TypeDef::Tuple(out))
    }
    TypeSig::Record(fields) => {
      let out : Array[@component.RecordField] = []
      for f in fields {
        match valtype_of_typesig(f.ty, type_table, resource_ids) {
          Some(v) => out.push({ label: f.name, ty: v })
          None => return None
        }
      }
      Some(@component.TypeDef::Record(out))
    }
    TypeSig::Variant(cases) => {
      let out : Array[@component.VariantCase] = []
      for c in cases {
        let ty = match c.ty {
          None => None
          Some(t) =>
            match valtype_of_typesig(t, type_table, resource_ids) {
              Some(v) => Some(v)
              None => return None
            }
        }
        out.push({ label: c.name, ty, refines: None })
      }
      Some(@component.TypeDef::Variant(out))
    }
    TypeSig::Option(t) =>
      match valtype_of_typesig(t, type_table, resource_ids) {
        Some(v) => Some(@component.TypeDef::Option(v))
        None => None
      }
    TypeSig::Result(ok, err) => {
      let ok_v = match ok {
        None => None
        Some(t) =>
          match valtype_of_typesig(t, type_table, resource_ids) {
            Some(v) => Some(v)
            None => return None
          }
      }
      let err_v = match err {
        None => None
        Some(t) =>
          match valtype_of_typesig(t, type_table, resource_ids) {
            Some(v) => Some(v)
            None => return None
          }
      }
      Some(@component.TypeDef::Result(ok_v, err_v))
    }
    TypeSig::List(t) =>
      match valtype_of_typesig(t, type_table, resource_ids) {
        Some(v) => Some(@component.TypeDef::List(v))
        None => None
      }
    TypeSig::Flags(labels) => Some(@component.TypeDef::Flags(labels))
    TypeSig::Enum(labels) => Some(@component.TypeDef::Enum(labels))
    _ => None
  }
}

///|
fn typesig_contains(sig : TypeSig, hay : Array[TypeSig]) -> Bool {
  for s in hay {
    if s == sig {
      return true
    }
  }
  false
}

///|
fn typesig_valid_in_interface(sig : TypeSig, named : Array[TypeSig]) -> Bool {
  match sig {
    TypeSig::Prim(_) | TypeSig::Other => true
    TypeSig::Resource(_) | TypeSig::Flags(_) | TypeSig::Enum(_) =>
      typesig_contains(sig, named)
    TypeSig::Record(fields) =>
      if !typesig_contains(sig, named) {
        false
      } else {
        for f in fields {
          if !typesig_valid_in_interface(f.ty, named) {
            return false
          }
        }
        true
      }
    TypeSig::Variant(cases) =>
      if !typesig_contains(sig, named) {
        false
      } else {
        for c in cases {
          match c.ty {
            None => ()
            Some(t) => if !typesig_valid_in_interface(t, named) { return false }
          }
        }
        true
      }
    TypeSig::Tuple(ts) => {
      for t in ts {
        if !typesig_valid_in_interface(t, named) {
          return false
        }
      }
      true
    }
    TypeSig::Option(t) => typesig_valid_in_interface(t, named)
    TypeSig::Result(ok, err) => {
      match ok {
        None => ()
        Some(t) => if !typesig_valid_in_interface(t, named) { return false }
      }
      match err {
        None => ()
        Some(t) => if !typesig_valid_in_interface(t, named) { return false }
      }
      true
    }
    TypeSig::List(t) => typesig_valid_in_interface(t, named)
  }
}

///|
fn funcsig_valid_in_interface(
  sig : FuncSigShape,
  named : Array[TypeSig],
) -> Bool {
  for p in sig.params {
    if !typesig_valid_in_interface(p.ty, named) {
      return false
    }
  }
  match sig.result {
    None => true
    Some(r) => typesig_valid_in_interface(r, named)
  }
}

///|
fn InstanceSig::empty() -> InstanceSig {
  { exports: {}, nested: {} }
}

///|
/// Convert a core index-space (including imports) into a type for validation.
/// Returns None when the index is out of bounds or for kinds we don't model yet.
fn core_func_type_of_idx(m : @types.Module, func_idx : Int) -> @types.FuncType? {
  let mut imported = 0
  for imp in m.imports {
    match imp.desc {
      @types.ImportDesc::Func(tyidx) => {
        if imported == func_idx {
          return Some(m.get_func_type(tyidx))
        }
        imported += 1
      }
      _ => ()
    }
  }
  let local_idx = func_idx - imported
  if local_idx < 0 || local_idx >= m.funcs.length() {
    return None
  }
  let tyidx = m.funcs[local_idx]
  Some(m.get_func_type(tyidx))
}

///|
fn core_table_type_of_idx(
  m : @types.Module,
  table_idx : Int,
) -> @types.TableType? {
  let mut imported = 0
  for imp in m.imports {
    match imp.desc {
      @types.ImportDesc::Table(tt) => {
        if imported == table_idx {
          return Some(tt)
        }
        imported += 1
      }
      _ => ()
    }
  }
  let local_idx = table_idx - imported
  if local_idx < 0 || local_idx >= m.tables.length() {
    return None
  }
  Some(m.tables[local_idx].type_)
}

///|
fn core_memory_type_of_idx(
  m : @types.Module,
  mem_idx : Int,
) -> @types.MemoryType? {
  let mut imported = 0
  for imp in m.imports {
    match imp.desc {
      @types.ImportDesc::Memory(mt) => {
        if imported == mem_idx {
          return Some(mt)
        }
        imported += 1
      }
      _ => ()
    }
  }
  let local_idx = mem_idx - imported
  if local_idx < 0 || local_idx >= m.memories.length() {
    return None
  }
  Some(m.memories[local_idx])
}

///|
fn core_global_type_of_idx(
  m : @types.Module,
  global_idx : Int,
) -> @types.GlobalType? {
  let mut imported = 0
  for imp in m.imports {
    match imp.desc {
      @types.ImportDesc::Global(gt) => {
        if imported == global_idx {
          return Some(gt)
        }
        imported += 1
      }
      _ => ()
    }
  }
  let local_idx = global_idx - imported
  if local_idx < 0 || local_idx >= m.globals.length() {
    return None
  }
  Some(m.globals[local_idx].type_)
}

///|
fn core_export_type_of_module(
  m : @types.Module,
  ex : @types.Export,
) -> CoreExternType? {
  match ex.desc {
    @types.ExportDesc::Func(func_idx) =>
      match core_func_type_of_idx(m, func_idx) {
        Some(ft) => Some(CoreExternType::Func(ft))
        None => None
      }
    @types.ExportDesc::Table(table_idx) =>
      core_table_type_of_idx(m, table_idx).map(fn(tt) {
        CoreExternType::Table(tt)
      })
    @types.ExportDesc::Memory(mem_idx) =>
      core_memory_type_of_idx(m, mem_idx).map(fn(mt) {
        CoreExternType::Memory(mt)
      })
    @types.ExportDesc::Global(global_idx) =>
      core_global_type_of_idx(m, global_idx).map(fn(gt) {
        CoreExternType::Global(gt)
      })
    _ => None
  }
}

///|
fn core_import_type_of_module(
  m : @types.Module,
  desc : @types.ImportDesc,
) -> CoreExternType? {
  match desc {
    @types.ImportDesc::Func(tyidx) =>
      Some(CoreExternType::Func(m.get_func_type(tyidx)))
    @types.ImportDesc::Table(tt) => Some(CoreExternType::Table(tt))
    @types.ImportDesc::Memory(mt) => Some(CoreExternType::Memory(mt))
    @types.ImportDesc::Global(gt) => Some(CoreExternType::Global(gt))
    _ => None
  }
}

///|
fn limits_import_compatible(
  expected : @types.Limits,
  provided : @types.Limits,
) -> Bool {
  if provided.min < expected.min {
    return false
  }
  match expected.max {
    None => true
    Some(emax) =>
      match provided.max {
        Some(pmax) => pmax <= emax
        None => false
      }
  }
}

///|
fn core_import_compatible(
  expected : CoreExternType,
  provided : CoreExternType,
) -> Bool {
  match (expected, provided) {
    (Func(a), Func(b)) => a == b
    (Global(a), Global(b)) => a == b
    (Table(a), Table(b)) =>
      a.elem_type == b.elem_type &&
      a.is_table64 == b.is_table64 &&
      limits_import_compatible(a.limits, b.limits)
    (Memory(a), Memory(b)) =>
      a.is_memory64 == b.is_memory64 &&
      a.page_size_log2 == b.page_size_log2 &&
      limits_import_compatible(a.limits, b.limits)
    _ => false
  }
}

///|
fn core_kind_of_extern_type(ty : CoreExternType) -> Int {
  match ty {
    Func(_) => 0x00
    Table(_) => 0x01
    Memory(_) => 0x02
    Global(_) => 0x03
  }
}

///|
/// Core module import signature keyed by "<module>::<name>".
fn core_module_import_sig_of_module(
  m : @types.Module,
) -> Map[String, CoreExternType] {
  let out : Map[String, CoreExternType] = {}
  for imp in m.imports {
    match core_import_type_of_module(m, imp.desc) {
      Some(ty) => out.set("\{imp.mod_name}::\{imp.name}", ty)
      None => ()
    }
  }
  out
}

///|
fn core_module_import_sig_of_type(
  sig : Array[CoreModuleTypeImport],
) -> Map[String, CoreExternType] {
  let out : Map[String, CoreExternType] = {}
  for imp in sig {
    out.set("\{imp.mod_name}::\{imp.name}", imp.ty)
  }
  out
}

///|
fn core_module_import_sig_of_idx(
  idx : Int,
  core_module_defs : Array[@types.Module?],
  core_module_type_imports : Array[Array[CoreModuleTypeImport]?],
) -> Map[String, CoreExternType]? {
  if idx < 0 || idx >= core_module_defs.length() {
    return None
  }
  match core_module_defs[idx] {
    Some(m) => Some(core_module_import_sig_of_module(m))
    None =>
      if idx >= 0 && idx < core_module_type_imports.length() {
        match core_module_type_imports[idx] {
          Some(sig) => Some(core_module_import_sig_of_type(sig))
          None => None
        }
      } else {
        None
      }
  }
}

///|
/// For core module types, imports are contravariant: a provided module may
/// require fewer (or more general) imports than the type describes.
fn check_core_module_import_subtype(
  actual : Map[String, CoreExternType]?,
  expected : Map[String, CoreExternType],
) -> Unit raise ComponentValidationError {
  match actual {
    Some(map) =>
      for kv in map.iter() {
        let (key, actual_ty) = kv
        match expected.get(key) {
          None => raise ComponentImportTypeMismatch("import \{key}")
          Some(expected_ty) =>
            if !core_import_compatible(actual_ty, expected_ty) {
              raise ComponentImportTypeMismatch("import \{key}")
            }
        }
      }
    None => ()
  }
}

///|
fn Counts::new() -> Counts {
  {
    func: 0,
    value: 0,
    component: 0,
    instance: 0,
    core_func: 0,
    core_module: 0,
    core_instance: 0,
    core_type: 0,
    core_table: 0,
    core_memory: 0,
    core_global: 0,
    core_tag: 0,
  }
}

///|
fn is_ascii_letter(b : Byte) -> Bool {
  let n = b.to_int()
  (n >= 0x41 && n <= 0x5A) || (n >= 0x61 && n <= 0x7A)
}

///|
fn is_ascii_lower(b : Byte) -> Bool {
  let n = b.to_int()
  n >= 0x61 && n <= 0x7A
}

///|
fn is_ascii_digit(b : Byte) -> Bool {
  let n = b.to_int()
  n >= 0x30 && n <= 0x39
}

///|
fn is_semver_ident_char(b : Byte) -> Bool {
  is_ascii_letter(b) || is_ascii_digit(b) || b.to_int() == 0x2D // '-'
}

///|
fn is_lower_kebab_case_range(name : Bytes, start : Int, end_ : Int) -> Bool {
  if start < 0 || end_ < 0 || start >= end_ || end_ > name.length() {
    return false
  }
  let mut first = true
  let mut prev_dash = false
  for i in start..<end_ {
    let b = name[i]
    if first {
      if !is_ascii_lower(b) {
        return false
      }
      first = false
      continue
    }
    if b.to_int() == 0x2D {
      if prev_dash {
        return false
      }
      prev_dash = true
    } else if is_ascii_lower(b) || is_ascii_digit(b) {
      prev_dash = false
    } else {
      return false
    }
  }
  !prev_dash
}

///|
fn is_kebab_case_range(name : Bytes, start : Int, end_ : Int) -> Bool {
  // wasm-tools' "kebab case" rules are stricter than "any string" but looser
  // than "all lowercase": each dash-separated segment must not mix upper/lower
  // case letters, and the first overall character must be a letter.
  if start < 0 || end_ < 0 || start >= end_ || end_ > name.length() {
    return false
  }
  // 0=unset, 1=lower, 2=upper
  let mut seg_case = 0
  let mut prev_dash = false
  for i in start..<end_ {
    let b = name[i]
    if i == start {
      if !is_ascii_letter(b) {
        return false
      }
      seg_case = if is_ascii_lower(b) { 1 } else { 2 }
      continue
    }
    if b.to_int() == 0x2D {
      if prev_dash {
        return false
      }
      prev_dash = true
      seg_case = 0
      continue
    }
    prev_dash = false
    if is_ascii_digit(b) {
      continue
    }
    if is_ascii_letter(b) {
      if seg_case == 0 {
        seg_case = if is_ascii_lower(b) { 1 } else { 2 }
      } else if seg_case == 1 {
        if !is_ascii_lower(b) {
          return false
        }
        // seg_case == 2
      } else if is_ascii_lower(b) {
        return false
      }
      continue
    }
    return false
  }
  !prev_dash
}

///|
fn is_semver_range(name : Bytes, start : Int, end_ : Int) -> Bool {
  // Minimal SemVer parser (enough to match wasm-tools component-spec tests).
  // Accepts: MAJOR.MINOR.PATCH[-prerelease][+build]
  if start < 0 || end_ < 0 || start >= end_ || end_ > name.length() {
    return false
  }
  let mut i = start
  let mut saw = false
  while i < end_ && is_ascii_digit(name[i]) {
    saw = true
    i += 1
  }
  if !saw {
    return false
  }
  if i >= end_ || name[i].to_int() != 0x2E {
    return false
  } // '.'
  i += 1
  saw = false
  while i < end_ && is_ascii_digit(name[i]) {
    saw = true
    i += 1
  }
  if !saw {
    return false
  }
  if i >= end_ || name[i].to_int() != 0x2E {
    return false
  } // '.'
  i += 1
  saw = false
  while i < end_ && is_ascii_digit(name[i]) {
    saw = true
    i += 1
  }
  if !saw {
    return false
  }

  // Optional prerelease
  if i < end_ && name[i].to_int() == 0x2D { // '-'
    i += 1
    if i >= end_ {
      return false
    }
    let mut need_id = true
    while i < end_ && name[i].to_int() != 0x2B { // '+'
      let b = name[i]
      if need_id {
        if b.to_int() == 0x2E || !is_semver_ident_char(b) { // '.' or invalid
          return false
        }
        need_id = false
        i += 1
        continue
      }
      if b.to_int() == 0x2E {
        need_id = true
        i += 1
        continue
      }
      if is_semver_ident_char(b) {
        i += 1
        continue
      }
      return false
    }
    if need_id {
      return false
    }
  }

  // Optional build metadata
  if i < end_ && name[i].to_int() == 0x2B { // '+'
    i += 1
    if i >= end_ {
      return false
    }
    let mut need_id = true
    while i < end_ {
      let b = name[i]
      if need_id {
        if b.to_int() == 0x2E || !is_semver_ident_char(b) { // '.' or invalid
          return false
        }
        need_id = false
        i += 1
        continue
      }
      if b.to_int() == 0x2E {
        need_id = true
        i += 1
        continue
      }
      if is_semver_ident_char(b) {
        i += 1
        continue
      }
      return false
    }
    if need_id {
      return false
    }
  }
  i == end_
}

///|
fn is_package_name(name : Bytes) -> Bool {
  if name.length() == 0 {
    return false
  }
  // Allow WIT-style package names like `wasi:http/types` (the version suffix is
  // encoded separately in ImportName/ExportName::WithVersion).
  let mut colon = -1
  let mut at = -1
  for i in 0..<name.length() {
    if name[i].to_int() == 0x3A { // ':'
      if colon != -1 {
        return false
      }
      colon = i
    }
    if name[i].to_int() == 0x40 { // '@'
      if at != -1 {
        return false
      }
      at = i
    }
  }
  if colon <= 0 || colon >= name.length() - 1 {
    return false
  }
  if at != -1 && at <= colon + 1 {
    return false
  }
  if at != -1 {
    if at >= name.length() - 1 {
      return false
    }
    if !is_semver_range(name, at + 1, name.length()) {
      return false
    }
  }
  let base_end = if at == -1 { name.length() } else { at }
  if !is_lower_kebab_case_range(name, 0, colon) {
    return false
  }
  // wasm-tools WIT encoding uses exactly one '/' segment after the ':'.
  let mut slash = -1
  for i in (colon + 1)..<base_end {
    if name[i].to_int() == 0x2F { // '/'
      if slash != -1 {
        return false
      }
      slash = i
    }
  }
  if slash == -1 || slash == colon + 1 || slash == base_end - 1 {
    return false
  }
  if !is_lower_kebab_case_range(name, colon + 1, slash) {
    return false
  }
  is_lower_kebab_case_range(name, slash + 1, base_end)
}

///|
fn is_unlocked_dep_name(name : Bytes) -> Bool {
  // wasm-tools supports "unlocked" dependency names:
  //   unlocked-dep=<namespace:pkg[@*|@{range}]>
  let prefix = "unlocked-dep=<"
  if name.length() <= prefix.length() {
    return false
  }
  // Prefix match
  for i in 0..<prefix.length() {
    if name[i].to_int() != prefix.code_unit_at(i).to_int() {
      return false
    }
  }
  if name[name.length() - 1].to_int() != 0x3E { // '>'
    return false
  }
  // Parse inner: namespace:pkg[@...]
  let start = prefix.length()
  let end_ = name.length() - 1
  if start >= end_ {
    return false
  }
  let mut colon = -1
  let mut at = -1
  for i in start..<end_ {
    let n = name[i].to_int()
    if n == 0x3A { // ':'
      if colon != -1 {
        return false
      }
      colon = i
    } else if n == 0x40 { // '@'
      if at != -1 {
        return false
      }
      at = i
    } else if n == 0x2F { // '/'
      // Not allowed in unlocked-dep inner name.
      return false
    }
  }
  if colon == -1 || colon == start || colon == end_ - 1 {
    return false
  }
  let base_end = if at == -1 { end_ } else { at }
  if !is_lower_kebab_case_range(name, start, colon) {
    return false
  }
  if !is_lower_kebab_case_range(name, colon + 1, base_end) {
    return false
  }
  if at == -1 {
    return true
  }
  // '@' must be followed by '*' or '{...}'
  if at + 1 >= end_ {
    return false
  }
  let next = name[at + 1].to_int()
  if next == 0x2A { // '*'
    return at + 2 == end_
  }
  if next != 0x7B { // '{'
    return false
  }
  if end_ - 1 <= at + 2 {
    return false
  }
  if name[end_ - 1].to_int() != 0x7D { // '}'
    return false
  }
  // Very small range parser: one-or-more constraints separated by spaces.
  let mut i = at + 2
  let range_end = end_ - 1
  let mut saw = false
  let mut saw_lt = false
  while i < range_end {
    // skip spaces
    while i < range_end && name[i].to_int() == 0x20 {
      i += 1
    }
    if i >= range_end {
      break
    }
    let op = name[i].to_int()
    if op == 0x3E { // '>'
      if saw_lt {
        return false
      }
      if i + 1 >= range_end || name[i + 1].to_int() != 0x3D {
        return false
      } // '='
      i += 2
    } else if op == 0x3C { // '<'
      saw_lt = true
      i += 1
    } else {
      return false
    }
    let ver_start = i
    while i < range_end && name[i].to_int() != 0x20 {
      i += 1
    }
    if !is_semver_range(name, ver_start, i) {
      return false
    }
    saw = true
  }
  saw
}

///|
fn is_base64ish_char(b : Byte) -> Bool {
  let n = b.to_int()
  // Allow the base64 alphabet plus a small superset used by wasm-tools tests.
  is_ascii_letter(b) ||
  is_ascii_digit(b) ||
  n == 0x2B ||
  n == 0x2F || // + /
  n == 0x3D ||
  n == 0x3F // = ?
}

///|
fn is_integrity_value(name : Bytes, start : Int, end_ : Int) -> Bool {
  // Parse `sha256-...` digests, allowing multiple digests separated by spaces.
  // Content may have leading/trailing whitespace.
  let mut i = start
  let mut saw = false
  while i < end_ {
    while i < end_ && name[i].to_int() == 0x20 { // ' '
      i += 1
    }
    if i >= end_ {
      break
    }
    // algorithm
    let alg_start = i
    while i < end_ && name[i].to_int() != 0x2D && name[i].to_int() != 0x20 {
      i += 1
    }
    if i >= end_ || name[i].to_int() != 0x2D { // '-'
      return false
    }
    if i - alg_start != 6 {
      return false
    }
    if name[alg_start].to_int() != 0x73 || // s
      name[alg_start + 1].to_int() != 0x68 || // h
      name[alg_start + 2].to_int() != 0x61 { // a
      return false
    }
    let d1 = name[alg_start + 3].to_int()
    let d2 = name[alg_start + 4].to_int()
    let d3 = name[alg_start + 5].to_int()
    let ok = (d1 == 0x32 && d2 == 0x35 && d3 == 0x36) || // 256
      (d1 == 0x33 && d2 == 0x38 && d3 == 0x34) || // 384
      (d1 == 0x35 && d2 == 0x31 && d3 == 0x32) // 512
    if !ok {
      return false
    }
    i += 1 // skip '-'
    // hash token
    let hash_start = i
    while i < end_ && name[i].to_int() != 0x20 {
      let b = name[i]
      if !is_base64ish_char(b) {
        return false
      }
      i += 1
    }
    if hash_start == i {
      return false
    }
    // '=' can only appear at the end, and at most twice.
    let mut eq_count = 0
    let mut seen_eq = false
    for j in hash_start..<i {
      let n = name[j].to_int()
      if n == 0x3D {
        eq_count += 1
        seen_eq = true
      } else if seen_eq {
        return false
      }
    }
    if eq_count > 2 {
      return false
    }
    // Reject hashes that are only '=' padding.
    let mut all_eq = true
    for j in hash_start..<i {
      if name[j].to_int() != 0x3D {
        all_eq = false
        break
      }
    }
    if all_eq {
      return false
    }
    saw = true
  }
  saw
}

///|
fn is_integrity_name(name : Bytes) -> Bool {
  let prefix = "integrity=<"
  if name.length() <= prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if name[i].to_int() != prefix.code_unit_at(i).to_int() {
      return false
    }
  }
  if name[name.length() - 1].to_int() != 0x3E { // '>'
    return false
  }
  is_integrity_value(name, prefix.length(), name.length() - 1)
}

///|
fn is_url_name(name : Bytes) -> Bool {
  let prefix = "url=<"
  if name.length() <= prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if name[i].to_int() != prefix.code_unit_at(i).to_int() {
      return false
    }
  }
  // Find closing '>' of the URL part.
  let mut close = -1
  for i in prefix.length()..<name.length() {
    let n = name[i].to_int()
    if n == 0x3C { // '<'
      return false
    }
    if n == 0x3E { // '>'
      close = i
      break
    }
  }
  if close == -1 {
    return false
  }
  if close == name.length() - 1 {
    return true
  }
  // Optional integrity suffix.
  let suffix = ",integrity=<"
  if close + suffix.length() >= name.length() {
    return false
  }
  for j in 0..<suffix.length() {
    if name[close + 1 + j].to_int() != suffix.code_unit_at(j).to_int() {
      return false
    }
  }
  if name[name.length() - 1].to_int() != 0x3E { // '>'
    return false
  }
  is_integrity_value(name, close + 1 + suffix.length(), name.length() - 1)
}

///|
fn is_locked_dep_name(name : Bytes) -> Bool {
  let prefix = "locked-dep=<"
  if name.length() <= prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if name[i].to_int() != prefix.code_unit_at(i).to_int() {
      return false
    }
  }
  // Find closing '>' of the dep spec.
  let mut close = -1
  for i in prefix.length()..<name.length() {
    if name[i].to_int() == 0x3E { // '>'
      close = i
      break
    }
  }
  if close == -1 {
    return false
  }
  // Parse inner: namespace:pkg[@semver]
  let start = prefix.length()
  let end_ = close
  if start >= end_ {
    return false
  }
  let mut colon = -1
  let mut at = -1
  for i in start..<end_ {
    let n = name[i].to_int()
    if n == 0x3A { // ':'
      if colon != -1 {
        return false
      }
      colon = i
    } else if n == 0x40 { // '@'
      if at != -1 {
        return false
      }
      at = i
    } else if n == 0x2F { // '/'
      return false
    }
  }
  if colon == -1 || colon == start || colon == end_ - 1 {
    return false
  }
  let base_end = if at == -1 { end_ } else { at }
  if !is_lower_kebab_case_range(name, start, colon) {
    return false
  }
  if !is_lower_kebab_case_range(name, colon + 1, base_end) {
    return false
  }
  if at != -1 {
    if at + 1 >= end_ {
      return false
    }
    if !is_semver_range(name, at + 1, end_) {
      return false
    }
  }
  if close == name.length() - 1 {
    return true
  }
  // Optional integrity suffix.
  let suffix = ",integrity=<"
  if close + suffix.length() >= name.length() {
    return false
  }
  for j in 0..<suffix.length() {
    if name[close + 1 + j].to_int() != suffix.code_unit_at(j).to_int() {
      return false
    }
  }
  if name[name.length() - 1].to_int() != 0x3E { // '>'
    return false
  }
  is_integrity_value(name, close + 1 + suffix.length(), name.length() - 1)
}

///|
fn is_kebab_case(name : Bytes) -> Bool {
  is_kebab_case_range(name, 0, name.length())
}

///|
fn is_bracket_resource_name(name : Bytes) -> Bool {
  // WIT-encoding uses resource item names like:
  //   [constructor]resource1
  //   [static]resource1.assert
  //   [method]resource1.take-own
  // These are ASCII and should not be validated as kebab-case.
  if name.length() < 3 {
    return false
  }
  if name[0].to_int() != 0x5B { // '['
    return false
  }
  let mut close = -1
  for i in 1..<name.length() {
    if name[i].to_int() == 0x5D { // ']'
      close = i
      break
    }
  }
  if close <= 1 || close >= name.length() - 1 {
    return false
  }
  fn prefix_eq(s : String) -> Bool {
    if close - 1 != s.length() {
      return false
    }
    for j in 0..<s.length() {
      if name[1 + j].to_int() != s.code_unit_at(j).to_int() {
        return false
      }
    }
    true
  }

  let is_constructor = prefix_eq("constructor")
  let is_method = prefix_eq("method")
  let is_static = prefix_eq("static")
  if !is_constructor && !is_method && !is_static {
    return false
  }
  if is_constructor {
    return is_kebab_case_range(name, close + 1, name.length())
  }
  // method/static: require exactly one '.' and kebab-case around it.
  let mut dot = -1
  for k in (close + 1)..<name.length() {
    if name[k].to_int() == 0x2E { // '.'
      if dot >= 0 {
        return false
      }
      dot = k
    }
  }
  if dot < 0 || dot == close + 1 || dot == name.length() - 1 {
    return false
  }
  is_kebab_case_range(name, close + 1, dot) &&
  is_kebab_case_range(name, dot + 1, name.length())
}

///|
fn validate_name_bytes(name : Bytes) -> Unit raise ComponentValidationError {
  if !is_kebab_case(name) &&
    !is_package_name(name) &&
    !is_bracket_resource_name(name) {
    raise InvalidKebabName(name.to_string())
  }
}

///|
fn validate_import_name_bytes(
  name : Bytes,
) -> Unit raise ComponentValidationError {
  // Component imports allow WIT dependency specifiers like `locked-dep=...`,
  // `unlocked-dep=...`, `url=...`, and `integrity=...`.
  if !is_kebab_case(name) &&
    !is_package_name(name) &&
    !is_bracket_resource_name(name) &&
    !is_unlocked_dep_name(name) &&
    !is_locked_dep_name(name) &&
    !is_url_name(name) &&
    !is_integrity_name(name) {
    raise InvalidKebabName(name.to_string())
  }
}

///|
priv struct CoreTypeReader {
  data : Bytes
  mut pos : Int
}

///|
fn CoreTypeReader::new(data : Bytes) -> CoreTypeReader {
  { data, pos: 0 }
}

///|
fn CoreTypeReader::is_eof(self : CoreTypeReader) -> Bool {
  self.pos >= self.data.length()
}

///|
fn CoreTypeReader::read_u8(
  self : CoreTypeReader,
) -> Int raise ComponentValidationError {
  if self.pos >= self.data.length() {
    raise SectionParseError(3, "unexpected end of core type payload")
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
fn CoreTypeReader::read_leb_u32(
  self : CoreTypeReader,
) -> Int raise ComponentValidationError {
  let mut result = 0
  let mut shift = 0
  while true {
    if shift >= 35 {
      raise SectionParseError(3, "leb128 too large")
    }
    let byte = self.read_u8()
    result = result | ((byte & 0x7F) << shift)
    if (byte & 0x80) == 0 {
      break
    }
    shift += 7
  }
  result
}

///|
fn CoreTypeReader::read_bytes(
  self : CoreTypeReader,
  n : Int,
) -> Bytes raise ComponentValidationError {
  if n < 0 || self.pos + n > self.data.length() {
    raise SectionParseError(3, "unexpected end of core type payload")
  }
  let bytes = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(self.data[self.pos + i])
        continue (acc, i + 1)
      }
  }
  self.pos += n
  Bytes::from_array(bytes)
}

///|
fn ascii_bytes_to_string(bytes : Bytes) -> String? {
  let buf = StringBuilder::new()
  for b in bytes {
    let n = b.to_int()
    if n >= 0x80 {
      return None
    }
    buf.write_char(n.unsafe_to_char())
  }
  Some(buf.to_string())
}

///|
fn CoreTypeReader::read_name_ascii(
  self : CoreTypeReader,
) -> String? raise ComponentValidationError {
  let len = self.read_leb_u32()
  ascii_bytes_to_string(self.read_bytes(len))
}

///|
fn CoreTypeReader::skip_limits(
  self : CoreTypeReader,
) -> Unit raise ComponentValidationError {
  let flags = self.read_u8()
  self.read_leb_u32() |> ignore
  if (flags & 0x01) != 0 {
    self.read_leb_u32() |> ignore
  }
}

///|
fn CoreTypeReader::skip_func_type(
  self : CoreTypeReader,
) -> Unit raise ComponentValidationError {
  let form = self.read_u8()
  if form != 0x60 {
    raise SectionParseError(3, "unsupported core functype form: \{form}")
  }
  self.skip_func_type_body()
}

///|
fn CoreTypeReader::skip_func_type_body(
  self : CoreTypeReader,
) -> Unit raise ComponentValidationError {
  let nparams = self.read_leb_u32()
  for _i in 0..<nparams {
    self.read_u8() |> ignore
  }
  let nresults = self.read_leb_u32()
  for _i in 0..<nresults {
    self.read_u8() |> ignore
  }
}

///|
fn CoreTypeReader::validate_extern_type(
  self : CoreTypeReader,
  kind : Int,
  func_type_bound : Int,
) -> Unit raise ComponentValidationError {
  match kind {
    0x00 => {
      let idx = self.read_leb_u32()
      if idx < 0 || idx >= func_type_bound {
        raise SectionParseError(3, "type index out of bounds")
      }
    }
    0x01 => {
      self.read_u8() |> ignore // elem/ref type
      self.skip_limits()
    }
    0x02 => {
      // Memory limits are bounded for 32-bit memories (wasm-tools expects this
      // validation in module types).
      let flags = self.read_u8()
      let min = self.read_leb_u32()
      if min > 65536 {
        raise SectionParseError(3, "memory size out of bounds")
      }
      if (flags & 0x01) != 0 {
        let max = self.read_leb_u32()
        if max > 65536 || max < min {
          raise SectionParseError(3, "memory size out of bounds")
        }
      }
    }
    0x03 => {
      self.read_u8() |> ignore // valtype
      self.read_u8() |> ignore // mut
    }
    0x04 => {
      let idx = self.read_leb_u32()
      if idx < 0 || idx >= func_type_bound {
        raise SectionParseError(3, "type index out of bounds")
      }
    }
    _ => raise SectionParseError(3, "unknown core extern kind: \{kind}")
  }
}

///|
fn CoreTypeReader::read_core_valtype(
  self : CoreTypeReader,
) -> @types.ValueType raise ComponentValidationError {
  let op = self.read_u8()
  match op {
    0x7f => @types.ValueType::I32
    0x7e => @types.ValueType::I64
    0x7d => @types.ValueType::F32
    0x7c => @types.ValueType::F64
    0x7b => @types.ValueType::V128
    0x70 => @types.ValueType::FuncRef
    0x6f => @types.ValueType::ExternRef
    _ => raise SectionParseError(3, "unsupported core valtype: \{op}")
  }
}

///|
fn CoreTypeReader::read_core_functype(
  self : CoreTypeReader,
) -> @types.FuncType raise ComponentValidationError {
  let form = self.read_u8()
  if form != 0x60 {
    raise SectionParseError(3, "unsupported core functype form: \{form}")
  }
  let nparams = self.read_leb_u32()
  let params : Array[@types.ValueType] = []
  for _i in 0..<nparams {
    params.push(self.read_core_valtype())
  }
  let nresults = self.read_leb_u32()
  let results : Array[@types.ValueType] = []
  for _i in 0..<nresults {
    results.push(self.read_core_valtype())
  }
  { params, results }
}

///|
fn CoreTypeReader::read_extern_type_sig(
  self : CoreTypeReader,
  kind : Int,
  func_types : Array[@types.FuncType?],
  func_type_bound : Int,
) -> CoreExternType? raise ComponentValidationError {
  match kind {
    0x00 => {
      let idx = self.read_leb_u32()
      if idx < 0 || idx >= func_type_bound {
        raise SectionParseError(3, "type index out of bounds")
      }
      if idx >= 0 && idx < func_types.length() {
        match func_types[idx] {
          Some(ft) => Some(CoreExternType::Func(ft))
          None => None
        }
      } else {
        None
      }
    }
    0x01 => {
      // tabletype: elemtype + limits
      let elem = self.read_u8()
      let elem_ty = match elem {
        0x70 => @types.ValueType::FuncRef
        0x6f => @types.ValueType::ExternRef
        _ =>
          raise SectionParseError(3, "unsupported core table elemtype: \{elem}")
      }
      let flags = self.read_u8()
      let min = self.read_leb_u32()
      let max = if (flags & 0x01) != 0 {
        Some(self.read_leb_u32())
      } else {
        None
      }
      let limits : @types.Limits = {
        min: min.to_int64(),
        max: match max {
          Some(v) => Some(v.to_int64())
          None => None
        },
      }
      Some(
        CoreExternType::Table({ elem_type: elem_ty, limits, is_table64: false }),
      )
    }
    0x02 => {
      // memtype: flags + limits (track memory64 when present)
      let flags = self.read_u8()
      let min = self.read_leb_u32()
      if min > 65536 {
        raise SectionParseError(3, "memory size out of bounds")
      }
      let max = if (flags & 0x01) != 0 {
        let maxv = self.read_leb_u32()
        if maxv > 65536 || maxv < min {
          raise SectionParseError(3, "memory size out of bounds")
        }
        Some(maxv)
      } else {
        None
      }
      let limits : @types.Limits = {
        min: min.to_int64(),
        max: match max {
          Some(v) => Some(v.to_int64())
          None => None
        },
      }
      let is_memory64 = (flags & 0x04) != 0
      Some(CoreExternType::Memory({ limits, is_memory64, page_size_log2: 16 }))
    }
    0x03 => {
      // globaltype: valtype + mut
      let vt = self.read_core_valtype()
      let mut_ = self.read_u8()
      let mutable = mut_ != 0
      Some(CoreExternType::Global({ value_type: vt, mutable }))
    }
    _ => {
      self.validate_extern_type(kind, func_type_bound)
      None
    }
  }
}

///|
fn parse_core_type_module_sig(
  r : CoreTypeReader,
  max_outer_depth : Int,
  current_core_type_bound : Int,
  outer_core_type_bounds : Array[Int],
) -> (Array[CoreModuleTypeImport], Map[String, CoreExternType]) raise ComponentValidationError {
  let ndecls = r.read_leb_u32()
  let seen_imports : Map[String, Int] = {}
  let imports : Array[CoreModuleTypeImport] = []
  let export_types : Map[String, CoreExternType] = {}
  let func_types : Array[@types.FuncType?] = []
  let mut func_type_bound = 0
  for _i in 0..<ndecls {
    let tag = r.read_u8()
    match tag {
      0x00 => {
        let mod_name = r.read_name_ascii()
        let name = r.read_name_ascii()
        let mod_s = match mod_name {
          Some(s) => s
          None => ""
        }
        let name_s = match name {
          Some(s) => s
          None => ""
        }
        let key = "\{mod_s}:\{name_s}"
        if seen_imports.get(key) is Some(_) {
          raise SectionParseError(3, "duplicate import name")
        }
        seen_imports.set(key, 1)
        let kind = r.read_u8()
        match r.read_extern_type_sig(kind, func_types, func_type_bound) {
          Some(ty) => imports.push({ mod_name: mod_s, name: name_s, ty })
          None => ()
        }
      }
      0x01 => {
        func_types.push(Some(r.read_core_functype()))
        func_type_bound += 1
      }
      0x02 => {
        // Alias declarations inside module types.
        let sort = r.read_u8()
        if sort == 0x10 {
          // Aliasing a core type introduces a new function-type index (we don't
          // currently resolve its signature here).
          func_types.push(None)
          func_type_bound += 1
        }
        let target_tag = r.read_u8()
        match target_tag {
          0x01 => {
            let depth = r.read_leb_u32()
            let idx = r.read_leb_u32()
            if max_outer_depth >= 0 {
              if depth > max_outer_depth {
                raise SectionParseError(3, "outer alias depth out of bounds")
              }
              // wasm-tools expects out-of-bounds outer indices to be rejected
              // even when we don't fully resolve the aliased core type.
              if sort == 0x10 {
                let bound = if depth <= 1 {
                  current_core_type_bound
                } else if depth - 2 < outer_core_type_bounds.length() {
                  outer_core_type_bounds[depth - 2]
                } else {
                  raise SectionParseError(3, "outer alias depth out of bounds")
                }
                if idx < 0 || idx >= bound {
                  raise SectionParseError(3, "type index out of bounds")
                }
              }
            }
          }
          _ =>
            raise SectionParseError(
              3,
              "unknown module alias target: \{target_tag}",
            )
        }
      }
      0x03 => {
        let name = r.read_name_ascii()
        let kind = r.read_u8()
        let ty = r.read_extern_type_sig(kind, func_types, func_type_bound)
        match (name, ty) {
          (Some(s), Some(t)) =>
            if export_types.get(s) is Some(_) {
              raise SectionParseError(3, "duplicate export name")
            } else {
              export_types.set(s, t)
            }
          _ => ()
        }
      }
      _ => raise SectionParseError(3, "unknown module type decl tag: \{tag}")
    }
  }
  (imports, export_types)
}
