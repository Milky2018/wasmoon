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
} derive(Show, Eq)

///|
priv struct FuncSigShape {
  params : Array[ParamShape]
  result : TypeSig?
} derive(Show, Eq)

///|
priv enum ExportedTypeInfo {
  Existing(Int)
  Resource(Int)
  Opaque
} derive(Show, Eq)

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

///|
fn parse_core_type_module_exports(
  r : CoreTypeReader,
  max_outer_depth : Int,
  current_core_type_bound : Int,
  outer_core_type_bounds : Array[Int],
) -> Map[String, Int] raise ComponentValidationError {
  let ndecls = r.read_leb_u32()
  let exports : Map[String, Int] = {}
  let seen_imports : Map[String, Int] = {}
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
        r.validate_extern_type(kind, func_type_bound)
      }
      0x01 => {
        r.skip_func_type()
        func_type_bound += 1
      }
      0x02 => {
        // Alias declarations inside module types, e.g.:
        //   (alias outer $C $t (type $u))
        // We only skip the encoding here since export-kind validation doesn't
        // depend on it.
        let sort = r.read_u8()
        // Module-type extern kinds (func/tag) reference the module type's own
        // function-type index space. Both inline function type declarations and
        // aliases of core types introduce new indices.
        if sort == 0x10 {
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
        r.validate_extern_type(kind, func_type_bound)
        match name {
          Some(s) =>
            if exports.get(s) is Some(_) {
              raise SectionParseError(3, "duplicate export name")
            } else {
              exports.set(s, kind)
            }
          None => ()
        }
      }
      _ => raise SectionParseError(3, "unknown module type decl tag: \{tag}")
    }
  }
  exports
}

///|
fn parse_core_type_section(
  payload : Bytes,
  max_outer_depth : Int,
  base_core_type_bound : Int,
  outer_core_type_bounds : Array[Int],
) -> Array[Map[String, Int]?] raise ComponentValidationError {
  let r = CoreTypeReader::new(payload)
  let n = r.read_leb_u32()
  let out : Array[Map[String, Int]?] = []
  for i in 0..<n {
    let op = r.read_u8()
    if op == 0x50 {
      out.push(
        Some(
          parse_core_type_module_exports(
            r,
            max_outer_depth,
            base_core_type_bound + i,
            outer_core_type_bounds,
          ),
        ),
      )
    } else if op == 0x60 {
      r.skip_func_type_body()
      out.push(None)
    } else {
      raise SectionParseError(3, "unsupported core type opcode: \{op}")
    }
  }
  if !r.is_eof() {
    raise SectionParseError(3, "trailing bytes in core type section")
  }
  out
}

///|
fn parse_core_type_section_module_sigs(
  payload : Bytes,
  max_outer_depth : Int,
  base_core_type_bound : Int,
  outer_core_type_bounds : Array[Int],
) -> (Array[Array[CoreModuleTypeImport]?], Array[Map[String, CoreExternType]?]) raise ComponentValidationError {
  let r = CoreTypeReader::new(payload)
  let n = r.read_leb_u32()
  let imports : Array[Array[CoreModuleTypeImport]?] = []
  let export_types : Array[Map[String, CoreExternType]?] = []
  for i in 0..<n {
    let op = r.read_u8()
    if op == 0x50 {
      let (imps, exps) = parse_core_type_module_sig(
        r,
        max_outer_depth,
        base_core_type_bound + i,
        outer_core_type_bounds,
      )
      imports.push(Some(imps))
      export_types.push(Some(exps))
    } else if op == 0x60 {
      r.skip_func_type_body()
      imports.push(None)
      export_types.push(None)
    } else {
      raise SectionParseError(3, "unsupported core type opcode: \{op}")
    }
  }
  if !r.is_eof() {
    raise SectionParseError(3, "trailing bytes in core type section")
  }
  (imports, export_types)
}

///|
fn validate_single_core_type(
  payload : Bytes,
  current_core_type_bound : Int,
  outer_core_type_bounds : Array[Int],
) -> Map[String, Int]? raise ComponentValidationError {
  let r = CoreTypeReader::new(payload)
  let op = r.read_u8()
  // For module-type aliases, `depth` counts outward from the module:
  // depth 0/1 target the current component core-type index space; depth >= 2
  // targets outer component environments.
  let max_outer_depth = outer_core_type_bounds.length() + 1
  let exports = if op == 0x50 {
    Some(
      parse_core_type_module_exports(
        r, max_outer_depth, current_core_type_bound, outer_core_type_bounds,
      ),
    )
  } else if op == 0x60 {
    r.skip_func_type_body()
    None
  } else {
    raise SectionParseError(3, "unsupported core type opcode: \{op}")
  }
  if !r.is_eof() {
    raise SectionParseError(3, "trailing bytes in core type payload")
  }
  exports
}

///|
fn validate_import_name(
  name : @component.ImportName,
  cfg : ComponentValidationConfig,
) -> Unit raise ComponentValidationError {
  if !cfg.wit_names {
    return
  }
  match name {
    Plain(bytes) => validate_import_name_bytes(bytes)
    WithVersion(bytes, _vs) => validate_import_name_bytes(bytes)
  }
}

///|
fn validate_export_name(
  name : @component.ExportName,
  cfg : ComponentValidationConfig,
) -> Unit raise ComponentValidationError {
  if !cfg.wit_names {
    return
  }
  match name {
    Plain(bytes) => validate_name_bytes(bytes)
    WithVersion(bytes, _vs) => validate_name_bytes(bytes)
  }
}

///|
fn importname_to_string(name : @component.ImportName) -> String? {
  match name {
    Plain(bytes) => ascii_bytes_to_string(bytes)
    WithVersion(bytes, _vs) => ascii_bytes_to_string(bytes)
  }
}

///|
fn exportname_to_string(name : @component.ExportName) -> String? {
  match name {
    Plain(bytes) => ascii_bytes_to_string(bytes)
    WithVersion(bytes, _vs) => ascii_bytes_to_string(bytes)
  }
}

///|
fn ascii_lower_key(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    let n = c.to_int()
    if n >= 0x41 && n <= 0x5A {
      // ASCII A-Z -> a-z
      buf.write_char((n + 0x20).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn wit_name_conflict_base(name : String) -> String {
  fn parse_resource_prefix(name : String, prefix_len : Int) -> String {
    let buf = StringBuilder::new()
    let mut i = 0
    let mut saw_dot = false
    let mut after_dot = false
    for c in name {
      if i < prefix_len {
        i += 1
        continue
      }
      if c == '.' {
        saw_dot = true
        after_dot = true
        continue
      }
      if after_dot {
        buf.write_char(c)
      }
    }
    if saw_dot {
      buf.to_string()
    } else {
      name
    }
  }

  if name.has_prefix("[method]") {
    parse_resource_prefix(name, 8)
  } else if name.has_prefix("[static]") {
    parse_resource_prefix(name, 8)
  } else {
    name
  }
}

///|
fn wit_conflict_key(name : String) -> String {
  let base = wit_name_conflict_base(name)
  // Names with embedded opaque payloads (base64/url) are case-sensitive.
  if base.has_prefix("integrity=<") ||
    base.has_prefix("locked-dep=") ||
    base.has_prefix("unlocked-dep=") ||
    base.has_prefix("url=") {
    base
  } else {
    ascii_lower_key(base)
  }
}

///|
fn validate_extern_name_string(
  name : String,
  cfg : ComponentValidationConfig,
) -> Unit raise ComponentValidationError {
  if !cfg.wit_names {
    return
  }
  // Component type section names are decoded as UTF-8 strings by the parser.
  // For now we only validate ASCII-compatible names to match the wasm-tools
  // component-spec suite.
  let bytes : Array[Byte] = []
  for c in name {
    let cp = c.to_int()
    if cp < 0 || cp > 0x7f {
      raise InvalidKebabName(name)
    }
    bytes.push(cp.to_byte())
  }
  validate_name_bytes(Bytes::from_array(bytes))
}

///|
priv enum BracketResourceKind {
  Constructor
  Method
  Static
}

///|
priv struct BracketResourceName {
  kind : BracketResourceKind
  resource : String
}

///|
fn parse_bracket_resource_name(name : String) -> BracketResourceName? {
  if !name.has_prefix("[") {
    return None
  }
  let prefix = StringBuilder::new()
  let suffix = StringBuilder::new()
  let mut in_prefix = true
  let mut saw_close = false
  let mut i = 0
  for c in name {
    if i == 0 {
      i += 1
      continue
    }
    if in_prefix {
      if c == ']' {
        in_prefix = false
        saw_close = true
      } else {
        prefix.write_char(c)
      }
    } else {
      suffix.write_char(c)
    }
    i += 1
  }
  if !saw_close {
    return None
  }
  let p = prefix.to_string()
  let s = suffix.to_string()
  if p == "constructor" {
    return Some({ kind: Constructor, resource: s })
  }
  if p == "method" || p == "static" {
    let res = StringBuilder::new()
    let mut after_dot = false
    for c in s {
      if c == '.' && !after_dot {
        after_dot = true
        continue
      }
      if !after_dot {
        res.write_char(c)
      }
    }
    let kind = if p == "method" { Method } else { Static }
    return Some({ kind, resource: res.to_string() })
  }
  None
}

///|
fn own_target_of_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Int? {
  match ty {
    @component.ValType::TypeIdx(idx) =>
      if idx >= 0 && idx < type_table.length() {
        match type_table[idx] {
          Some(@component.TypeDef::Own(t)) => Some(t)
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn borrow_target_of_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Int? {
  match ty {
    @component.ValType::TypeIdx(idx) =>
      if idx >= 0 && idx < type_table.length() {
        match type_table[idx] {
          Some(@component.TypeDef::Borrow(t)) => Some(t)
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn validate_bracketed_func_name(
  section : Int,
  name : String,
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  known_resources : Map[String, Int],
) -> Unit raise ComponentValidationError {
  let br = parse_bracket_resource_name(name)
  match br {
    None => ()
    Some(info) =>
      match known_resources.get(info.resource) {
        None =>
          raise SectionParseError(
            section, "resource used in function does not have a name in this context",
          )
        Some(expected_tyidx) =>
          match info.kind {
            Constructor =>
              match ft.result {
                None =>
                  raise SectionParseError(
                    section, "constructor must return a value",
                  )
                Some(r) => {
                  // Accept `(own $T)` or `(result (own $T) ...)`.
                  let ok = match own_target_of_valtype(r, type_table) {
                    Some(t) =>
                      type_sig_of_typeidx(t, type_table, resource_ids) ==
                      type_sig_of_typeidx(
                        expected_tyidx, type_table, resource_ids,
                      )
                    None =>
                      match r {
                        @component.ValType::TypeIdx(idx) =>
                          if idx >= 0 && idx < type_table.length() {
                            match type_table[idx] {
                              Some(@component.TypeDef::Result(ok, _err)) =>
                                match ok {
                                  Some(v) =>
                                    match own_target_of_valtype(v, type_table) {
                                      Some(t) =>
                                        type_sig_of_typeidx(
                                          t, type_table, resource_ids,
                                        ) ==
                                        type_sig_of_typeidx(
                                          expected_tyidx, type_table, resource_ids,
                                        )
                                      None => false
                                    }
                                  None => false
                                }
                              _ => false
                            }
                          } else {
                            false
                          }
                        _ => false
                      }
                  }
                  if !ok {
                    raise SectionParseError(
                      section, "constructor does not match resource",
                    )
                  }
                }
              }
            Method => {
              if ft.params.length() == 0 {
                raise SectionParseError(section, "method must take `self`")
              }
              let first = ft.params[0]
              if first.label != "self" {
                raise SectionParseError(section, "method must take `self`")
              }
              match borrow_target_of_valtype(first.ty, type_table) {
                Some(t) =>
                  if type_sig_of_typeidx(t, type_table, resource_ids) !=
                    type_sig_of_typeidx(
                      expected_tyidx, type_table, resource_ids,
                    ) {
                    raise SectionParseError(
                      section, "method does not match resource",
                    )
                  }
                None =>
                  raise SectionParseError(section, "method must take `borrow`")
              }
            }
            Static => ()
          }
      }
  }
}

///|
fn valtype_uses_disallowed_resources(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  allowed_resource_type_idxs : Map[Int, Int],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    @component.ValType::Prim(_) => false
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        false
      } else if visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, 1)
        let bad = match type_table[idx] {
          Some(@component.TypeDef::Own(t))
          | Some(@component.TypeDef::Borrow(t)) =>
            allowed_resource_type_idxs.get(t) is None
          Some(@component.TypeDef::Tuple(tys)) => {
            let mut bad = false
            for t in tys {
              if valtype_uses_disallowed_resources(
                  t, type_table, allowed_resource_type_idxs, visiting,
                ) {
                bad = true
                break
              }
            }
            bad
          }
          Some(@component.TypeDef::Record(fields)) => {
            let mut bad = false
            for f in fields {
              if valtype_uses_disallowed_resources(
                  f.ty,
                  type_table,
                  allowed_resource_type_idxs,
                  visiting,
                ) {
                bad = true
                break
              }
            }
            bad
          }
          Some(@component.TypeDef::Variant(cases)) => {
            let mut bad = false
            for c in cases {
              match c.ty {
                None => ()
                Some(t) =>
                  if valtype_uses_disallowed_resources(
                      t, type_table, allowed_resource_type_idxs, visiting,
                    ) {
                    bad = true
                    break
                  }
              }
            }
            bad
          }
          Some(@component.TypeDef::Option(v)) =>
            valtype_uses_disallowed_resources(
              v, type_table, allowed_resource_type_idxs, visiting,
            )
          Some(@component.TypeDef::Result(ok, err)) => {
            let ok_bad = match ok {
              None => false
              Some(v) =>
                valtype_uses_disallowed_resources(
                  v, type_table, allowed_resource_type_idxs, visiting,
                )
            }
            let err_bad = match err {
              None => false
              Some(v) =>
                valtype_uses_disallowed_resources(
                  v, type_table, allowed_resource_type_idxs, visiting,
                )
            }
            ok_bad || err_bad
          }
          Some(@component.TypeDef::List(v)) =>
            valtype_uses_disallowed_resources(
              v, type_table, allowed_resource_type_idxs, visiting,
            )
          Some(@component.TypeDef::Stream(v))
          | Some(@component.TypeDef::Future(v)) =>
            match v {
              None => false
              Some(inner) =>
                valtype_uses_disallowed_resources(
                  inner, type_table, allowed_resource_type_idxs, visiting,
                )
            }
          // Other type defs either don't contain resources or are validated elsewhere.
          _ => false
        }
        visiting.remove(idx) |> ignore
        bad
      }
  }
}

///|
fn functype_uses_disallowed_resources(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
  allowed_resource_type_idxs : Map[Int, Int],
) -> Bool {
  let visiting : Map[Int, Int] = {}
  for p in ft.params {
    if valtype_uses_disallowed_resources(
        p.ty,
        type_table,
        allowed_resource_type_idxs,
        visiting,
      ) {
      return true
    }
  }
  match ft.result {
    None => false
    Some(r) =>
      valtype_uses_disallowed_resources(
        r, type_table, allowed_resource_type_idxs, visiting,
      )
  }
}

///|
fn funcsig_of_functype(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
) -> FuncSigShape {
  let visiting : Map[Int, Int] = {}
  let params : Array[ParamShape] = []
  for p in ft.params {
    params.push({
      name: p.label,
      ty: type_sig_of_valtype(p.ty, type_table, resource_ids, visiting),
    })
  }
  let result : TypeSig? = match ft.result {
    Some(v) => Some(type_sig_of_valtype(v, type_table, resource_ids, visiting))
    None => None
  }
  { params, result }
}

///|
fn type_sig_of_typedef_lg(
  td : @component.TypeDef,
  local_types : Array[@component.TypeDef],
  local_resource_ids : Array[Int?],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
  visiting : Map[Int, Int],
) -> TypeSig {
  match td {
    @component.TypeDef::DefValType(p) => TypeSig::Prim(p)
    @component.TypeDef::Tuple(tys) => {
      let out : Array[TypeSig] = []
      for t in tys {
        out.push(
          type_sig_of_valtype_lg(
            t, local_types, local_resource_ids, global_types, global_resource_ids,
            visiting,
          ),
        )
      }
      TypeSig::Tuple(out)
    }
    @component.TypeDef::Record(fields) => {
      let out : Array[TypeFieldSig] = []
      for f in fields {
        out.push({
          name: f.label,
          ty: type_sig_of_valtype_lg(
            f.ty,
            local_types,
            local_resource_ids,
            global_types,
            global_resource_ids,
            visiting,
          ),
        })
      }
      TypeSig::Record(out)
    }
    @component.TypeDef::Variant(cases) => {
      let out : Array[TypeCaseSig] = []
      for c in cases {
        let payload = match c.ty {
          None => None
          Some(t) =>
            Some(
              type_sig_of_valtype_lg(
                t, local_types, local_resource_ids, global_types, global_resource_ids,
                visiting,
              ),
            )
        }
        out.push({ name: c.label, ty: payload })
      }
      TypeSig::Variant(out)
    }
    @component.TypeDef::Option(v) =>
      TypeSig::Option(
        type_sig_of_valtype_lg(
          v, local_types, local_resource_ids, global_types, global_resource_ids,
          visiting,
        ),
      )
    @component.TypeDef::Result(ok, err) => {
      let ok_sig = ok.map(fn(v) {
        type_sig_of_valtype_lg(
          v, local_types, local_resource_ids, global_types, global_resource_ids,
          visiting,
        )
      })
      let err_sig = err.map(fn(v) {
        type_sig_of_valtype_lg(
          v, local_types, local_resource_ids, global_types, global_resource_ids,
          visiting,
        )
      })
      TypeSig::Result(ok_sig, err_sig)
    }
    @component.TypeDef::List(v) =>
      TypeSig::List(
        type_sig_of_valtype_lg(
          v, local_types, local_resource_ids, global_types, global_resource_ids,
          visiting,
        ),
      )
    @component.TypeDef::Flags(labels) => TypeSig::Flags(labels)
    @component.TypeDef::Enum(labels) => TypeSig::Enum(labels)
    @component.TypeDef::Own(idx) | @component.TypeDef::Borrow(idx) =>
      type_sig_of_valtype_lg(
        @component.ValType::TypeIdx(idx),
        local_types,
        local_resource_ids,
        global_types,
        global_resource_ids,
        visiting,
      )
    _ => TypeSig::Other
  }
}

///|
fn type_sig_of_valtype_lg(
  ty : @component.ValType,
  local_types : Array[@component.TypeDef],
  local_resource_ids : Array[Int?],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
  visiting : Map[Int, Int],
) -> TypeSig {
  match ty {
    @component.ValType::Prim(p) => TypeSig::Prim(p)
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 {
        TypeSig::Other
      } else if visiting.get(idx) is Some(_) {
        TypeSig::Other
      } else {
        visiting.set(idx, 1)
        let td = if idx < local_types.length() {
          Some(local_types[idx])
        } else if idx < global_types.length() {
          global_types[idx]
        } else {
          None
        }
        let rid = if idx < local_resource_ids.length() {
          local_resource_ids[idx]
        } else if idx < global_resource_ids.length() {
          global_resource_ids[idx]
        } else {
          None
        }
        let sig = match td {
          Some(@component.TypeDef::ResourceType(_, _, _, _)) =>
            match rid {
              Some(v) => TypeSig::Resource(v)
              None => TypeSig::Resource(-1)
            }
          Some(def) =>
            type_sig_of_typedef_lg(
              def, local_types, local_resource_ids, global_types, global_resource_ids,
              visiting,
            )
          None => TypeSig::Other
        }
        visiting.remove(idx) |> ignore
        sig
      }
  }
}

///|
fn funcsig_of_functype_lg(
  ft : @component.FuncType,
  local_types : Array[@component.TypeDef],
  local_resource_ids : Array[Int?],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
) -> FuncSigShape {
  let visiting : Map[Int, Int] = {}
  let params : Array[ParamShape] = []
  for p in ft.params {
    params.push({
      name: p.label,
      ty: type_sig_of_valtype_lg(
        p.ty,
        local_types,
        local_resource_ids,
        global_types,
        global_resource_ids,
        visiting,
      ),
    })
  }
  let result : TypeSig? = match ft.result {
    Some(v) =>
      Some(
        type_sig_of_valtype_lg(
          v, local_types, local_resource_ids, global_types, global_resource_ids,
          visiting,
        ),
      )
    None => None
  }
  { params, result }
}

///|
fn type_sig_of_typedef(
  td : @component.TypeDef,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  visiting : Map[Int, Int],
) -> TypeSig {
  match td {
    @component.TypeDef::DefValType(p) => TypeSig::Prim(p)
    @component.TypeDef::Tuple(tys) => {
      let out : Array[TypeSig] = []
      for t in tys {
        out.push(type_sig_of_valtype(t, type_table, resource_ids, visiting))
      }
      TypeSig::Tuple(out)
    }
    @component.TypeDef::Record(fields) => {
      let out : Array[TypeFieldSig] = []
      for f in fields {
        out.push({
          name: f.label,
          ty: type_sig_of_valtype(f.ty, type_table, resource_ids, visiting),
        })
      }
      TypeSig::Record(out)
    }
    @component.TypeDef::Variant(cases) => {
      let out : Array[TypeCaseSig] = []
      for c in cases {
        let payload = match c.ty {
          None => None
          Some(t) =>
            Some(type_sig_of_valtype(t, type_table, resource_ids, visiting))
        }
        out.push({ name: c.label, ty: payload })
      }
      TypeSig::Variant(out)
    }
    @component.TypeDef::Option(v) =>
      TypeSig::Option(
        type_sig_of_valtype(v, type_table, resource_ids, visiting),
      )
    @component.TypeDef::Result(ok, err) => {
      let ok_sig = ok.map(fn(v) {
        type_sig_of_valtype(v, type_table, resource_ids, visiting)
      })
      let err_sig = err.map(fn(v) {
        type_sig_of_valtype(v, type_table, resource_ids, visiting)
      })
      TypeSig::Result(ok_sig, err_sig)
    }
    @component.TypeDef::List(v) =>
      TypeSig::List(type_sig_of_valtype(v, type_table, resource_ids, visiting))
    @component.TypeDef::Flags(labels) => TypeSig::Flags(labels)
    @component.TypeDef::Enum(labels) => TypeSig::Enum(labels)
    // Own/borrow wrappers are nominally tied to the underlying resource type.
    @component.TypeDef::Own(idx) | @component.TypeDef::Borrow(idx) =>
      type_sig_of_valtype(
        @component.ValType::TypeIdx(idx),
        type_table,
        resource_ids,
        visiting,
      )
    _ => TypeSig::Other
  }
}

///|
fn type_sig_of_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  visiting : Map[Int, Int],
) -> TypeSig {
  match ty {
    @component.ValType::Prim(p) => TypeSig::Prim(p)
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        TypeSig::Other
      } else if visiting.get(idx) is Some(_) {
        TypeSig::Other
      } else {
        visiting.set(idx, 1)
        let sig = match type_table[idx] {
          Some(@component.TypeDef::ResourceType(_, _, _, _)) =>
            match resource_ids.get(idx) {
              Some(Some(rid)) => TypeSig::Resource(rid)
              _ => TypeSig::Resource(-1)
            }
          Some(td) =>
            type_sig_of_typedef(td, type_table, resource_ids, visiting)
          None => TypeSig::Other
        }
        visiting.remove(idx) |> ignore
        sig
      }
  }
}

///|
fn type_sig_of_typeidx(
  idx : Int,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
) -> TypeSig {
  type_sig_of_valtype(
    @component.ValType::TypeIdx(idx),
    type_table,
    resource_ids,
    {},
  )
}

///|
fn type_sig_subst_resources(sig : TypeSig, subst : Map[Int, Int]) -> TypeSig {
  match sig {
    TypeSig::Prim(p) => TypeSig::Prim(p)
    TypeSig::Tuple(xs) =>
      TypeSig::Tuple(xs.map(fn(x) { type_sig_subst_resources(x, subst) }))
    TypeSig::Record(fs) =>
      TypeSig::Record(
        fs.map(fn(f) {
          { name: f.name, ty: type_sig_subst_resources(f.ty, subst) }
        }),
      )
    TypeSig::Variant(cs) =>
      TypeSig::Variant(
        cs.map(fn(c) {
          let ty = match c.ty {
            None => None
            Some(t) => Some(type_sig_subst_resources(t, subst))
          }
          { name: c.name, ty }
        }),
      )
    TypeSig::Option(v) => TypeSig::Option(type_sig_subst_resources(v, subst))
    TypeSig::Result(ok, err) => {
      let ok2 = ok.map(fn(v) { type_sig_subst_resources(v, subst) })
      let err2 = err.map(fn(v) { type_sig_subst_resources(v, subst) })
      TypeSig::Result(ok2, err2)
    }
    TypeSig::List(v) => TypeSig::List(type_sig_subst_resources(v, subst))
    TypeSig::Flags(labels) => TypeSig::Flags(labels)
    TypeSig::Enum(labels) => TypeSig::Enum(labels)
    TypeSig::Resource(rid) =>
      match subst.get(rid) {
        Some(v) => TypeSig::Resource(v)
        None => TypeSig::Resource(rid)
      }
    TypeSig::Other => TypeSig::Other
  }
}

///|
fn type_sig_has_resource_mismatch(expected : TypeSig, actual : TypeSig) -> Bool {
  match (expected, actual) {
    (TypeSig::Resource(a), TypeSig::Resource(b)) => a != b
    (TypeSig::Tuple(xs), TypeSig::Tuple(ys)) =>
      xs.length() == ys.length() &&
      {
        let mut mismatch = false
        for i in 0..<xs.length() {
          if xs[i] != ys[i] && type_sig_has_resource_mismatch(xs[i], ys[i]) {
            mismatch = true
            break
          }
        }
        mismatch
      }
    (TypeSig::Record(xs), TypeSig::Record(ys)) =>
      xs.length() == ys.length() &&
      {
        let mut mismatch = false
        for i in 0..<xs.length() {
          if xs[i].ty != ys[i].ty &&
            type_sig_has_resource_mismatch(xs[i].ty, ys[i].ty) {
            mismatch = true
            break
          }
        }
        mismatch
      }
    (TypeSig::Variant(xs), TypeSig::Variant(ys)) =>
      xs.length() == ys.length() &&
      {
        let mut mismatch = false
        for i in 0..<xs.length() {
          let a = xs[i].ty
          let b = ys[i].ty
          if a != b {
            match (a, b) {
              (Some(a2), Some(b2)) =>
                if type_sig_has_resource_mismatch(a2, b2) {
                  mismatch = true
                  break
                }
              _ => ()
            }
          }
        }
        mismatch
      }
    (TypeSig::Option(a), TypeSig::Option(b)) =>
      a != b && type_sig_has_resource_mismatch(a, b)
    (TypeSig::List(a), TypeSig::List(b)) =>
      a != b && type_sig_has_resource_mismatch(a, b)
    (TypeSig::Result(a1, a2), TypeSig::Result(b1, b2)) => {
      if a1 != b1 {
        match (a1, b1) {
          (Some(x), Some(y)) =>
            if type_sig_has_resource_mismatch(x, y) {
              return true
            }
          _ => ()
        }
      }
      if a2 != b2 {
        match (a2, b2) {
          (Some(x), Some(y)) =>
            if type_sig_has_resource_mismatch(x, y) {
              return true
            }
          _ => ()
        }
      }
      false
    }
    _ => false
  }
}

///|
fn funcsig_subst_resources(
  sig : FuncSigShape,
  subst : Map[Int, Int],
) -> FuncSigShape {
  let params : Array[ParamShape] = []
  for p in sig.params {
    params.push({ name: p.name, ty: type_sig_subst_resources(p.ty, subst) })
  }
  let result = match sig.result {
    None => None
    Some(r) => Some(type_sig_subst_resources(r, subst))
  }
  { params, result }
}

///|
fn funcsig_has_resource_mismatch(
  expected : FuncSigShape,
  actual : FuncSigShape,
) -> Bool {
  if expected.params.length() != actual.params.length() {
    return false
  }
  for i in 0..<expected.params.length() {
    let a = expected.params[i].ty
    let b = actual.params[i].ty
    if a != b && type_sig_has_resource_mismatch(a, b) {
      return true
    }
  }
  match (expected.result, actual.result) {
    (None, None) => false
    (Some(a), Some(b)) => a != b && type_sig_has_resource_mismatch(a, b)
    _ => false
  }
}

///|
fn typedef_requires_name_for_interface(td : @component.TypeDef) -> Bool {
  match td {
    @component.TypeDef::Record(_)
    | @component.TypeDef::Variant(_)
    | @component.TypeDef::Flags(_)
    | @component.TypeDef::Enum(_)
    | @component.TypeDef::ResourceType(_, _, _, _) => true
    _ => false
  }
}

///|
fn valtype_valid_in_interface(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  named_types : Map[Int, Int],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    @component.ValType::Prim(_) => true
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        true
      } else if visiting.get(idx) is Some(_) {
        true
      } else {
        match type_table[idx] {
          None => true
          Some(td) => {
            if typedef_requires_name_for_interface(td) &&
              named_types.get(idx) is None {
              let sig = type_sig_of_typeidx(idx, type_table, resource_ids)
              let mut ok = false
              if sig != TypeSig::Other {
                for kv in named_types.iter() {
                  let (k, _v) = kv
                  if type_sig_of_typeidx(k, type_table, resource_ids) == sig {
                    ok = true
                    break
                  }
                }
              }
              if !ok {
                return false
              }
            }
            visiting.set(idx, 1)
            let ok = match td {
              @component.TypeDef::DefValType(_) => true
              @component.TypeDef::Tuple(tys) => {
                let mut ok = true
                for t in tys {
                  if !valtype_valid_in_interface(
                      t, type_table, resource_ids, named_types, visiting,
                    ) {
                    ok = false
                    break
                  }
                }
                ok
              }
              @component.TypeDef::Record(fields) => {
                let mut ok = true
                for f in fields {
                  if !valtype_valid_in_interface(
                      f.ty,
                      type_table,
                      resource_ids,
                      named_types,
                      visiting,
                    ) {
                    ok = false
                    break
                  }
                }
                ok
              }
              @component.TypeDef::Variant(cases) => {
                let mut ok = true
                for c in cases {
                  match c.ty {
                    None => ()
                    Some(t) =>
                      if !valtype_valid_in_interface(
                          t, type_table, resource_ids, named_types, visiting,
                        ) {
                        ok = false
                        break
                      }
                  }
                }
                ok
              }
              @component.TypeDef::Option(v) =>
                valtype_valid_in_interface(
                  v, type_table, resource_ids, named_types, visiting,
                )
              @component.TypeDef::Result(ok, err) => {
                let ok_ok = match ok {
                  None => true
                  Some(v) =>
                    valtype_valid_in_interface(
                      v, type_table, resource_ids, named_types, visiting,
                    )
                }
                let err_ok = match err {
                  None => true
                  Some(v) =>
                    valtype_valid_in_interface(
                      v, type_table, resource_ids, named_types, visiting,
                    )
                }
                ok_ok && err_ok
              }
              @component.TypeDef::List(v) =>
                valtype_valid_in_interface(
                  v, type_table, resource_ids, named_types, visiting,
                )
              @component.TypeDef::Own(idx) | @component.TypeDef::Borrow(idx) =>
                valtype_valid_in_interface(
                  @component.ValType::TypeIdx(idx),
                  type_table,
                  resource_ids,
                  named_types,
                  visiting,
                )
              // Nominal-ish types still need their payloads checked.
              @component.TypeDef::Future(v) | @component.TypeDef::Stream(v) =>
                match v {
                  None => true
                  Some(inner) =>
                    valtype_valid_in_interface(
                      inner, type_table, resource_ids, named_types, visiting,
                    )
                }
              _ => true
            }
            visiting.remove(idx) |> ignore
            ok
          }
        }
      }
  }
}

///|
fn valtype_valid_for_type_import_export(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  named_types : Map[Int, Int],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    @component.ValType::Prim(_) => true
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        true
      } else if visiting.get(idx) is Some(_) {
        true
      } else {
        match type_table[idx] {
          None => true
          Some(td) => {
            match td {
              @component.TypeDef::Own(_) | @component.TypeDef::Borrow(_) =>
                return false
              @component.TypeDef::FuncType(ft) =>
                return functype_valid_in_interface(
                  ft, type_table, resource_ids, named_types,
                )
              _ => ()
            }
            if typedef_requires_name_for_interface(td) &&
              named_types.get(idx) is None {
              let sig = type_sig_of_typeidx(idx, type_table, resource_ids)
              let mut ok = false
              if sig != TypeSig::Other {
                for kv in named_types.iter() {
                  let (k, _v) = kv
                  if type_sig_of_typeidx(k, type_table, resource_ids) == sig {
                    ok = true
                    break
                  }
                }
              }
              if !ok {
                return false
              }
            }
            visiting.set(idx, 1)
            let ok = match td {
              @component.TypeDef::DefValType(_) => true
              @component.TypeDef::Tuple(tys) => {
                let mut ok = true
                for t in tys {
                  if !valtype_valid_for_type_import_export(
                      t, type_table, resource_ids, named_types, visiting,
                    ) {
                    ok = false
                    break
                  }
                }
                ok
              }
              @component.TypeDef::Record(fields) => {
                let mut ok = true
                for f in fields {
                  if !valtype_valid_for_type_import_export(
                      f.ty,
                      type_table,
                      resource_ids,
                      named_types,
                      visiting,
                    ) {
                    ok = false
                    break
                  }
                }
                ok
              }
              @component.TypeDef::Variant(cases) => {
                let mut ok = true
                for c in cases {
                  match c.ty {
                    None => ()
                    Some(t) =>
                      if !valtype_valid_for_type_import_export(
                          t, type_table, resource_ids, named_types, visiting,
                        ) {
                        ok = false
                        break
                      }
                  }
                }
                ok
              }
              @component.TypeDef::Option(v) =>
                valtype_valid_for_type_import_export(
                  v, type_table, resource_ids, named_types, visiting,
                )
              @component.TypeDef::Result(ok_v, err_v) => {
                let ok_ok = match ok_v {
                  None => true
                  Some(v) =>
                    valtype_valid_for_type_import_export(
                      v, type_table, resource_ids, named_types, visiting,
                    )
                }
                let err_ok = match err_v {
                  None => true
                  Some(v) =>
                    valtype_valid_for_type_import_export(
                      v, type_table, resource_ids, named_types, visiting,
                    )
                }
                ok_ok && err_ok
              }
              @component.TypeDef::List(v) =>
                valtype_valid_for_type_import_export(
                  v, type_table, resource_ids, named_types, visiting,
                )
              @component.TypeDef::Flags(_) | @component.TypeDef::Enum(_) => true
              @component.TypeDef::ResourceType(_, _, _, _) => true
              @component.TypeDef::Future(v) | @component.TypeDef::Stream(v) =>
                match v {
                  None => true
                  Some(inner) =>
                    valtype_valid_for_type_import_export(
                      inner, type_table, resource_ids, named_types, visiting,
                    )
                }
              @component.TypeDef::InstanceTypeEmpty => true
              @component.TypeDef::InstanceType(_) => true
              @component.TypeDef::ComponentType(_) => true
              _ => false
            }
            visiting.remove(idx) |> ignore
            ok
          }
        }
      }
  }
}

///|
fn functype_valid_in_interface(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  named_types : Map[Int, Int],
) -> Bool {
  let visiting : Map[Int, Int] = {}
  for p in ft.params {
    if !valtype_valid_in_interface(
        p.ty,
        type_table,
        resource_ids,
        named_types,
        visiting,
      ) {
      return false
    }
  }
  match ft.result {
    None => true
    Some(r) =>
      valtype_valid_in_interface(
        r, type_table, resource_ids, named_types, visiting,
      )
  }
}

///|
fn component_import_type_sigs_of(
  c : @component.Component,
) -> Map[String, TypeSig] {
  let type_table : Array[@component.TypeDef?] = []
  let resource_ids : Array[Int?] = []
  let mut next_rid = 0
  for td in c.types {
    type_table.push(Some(td))
    match td {
      @component.TypeDef::ResourceType(_, _, _, _) => {
        resource_ids.push(Some(next_rid))
        next_rid += 1
      }
      _ => resource_ids.push(None)
    }
  }
  let out : Map[String, TypeSig] = {}
  for imp in c.imports {
    match (importname_to_string(imp.name), imp.desc) {
      (Some(name), @component.ExternDesc::Type(bound)) =>
        match bound {
          @component.TypeBound::Eq(tyidx) =>
            out.set(name, type_sig_of_typeidx(tyidx, type_table, resource_ids))
          _ => ()
        }
      _ => ()
    }
  }
  out
}

///|
fn instancetype_sig_of_typedef(
  td : @component.TypeDef,
  type_table : Array[@component.TypeDef?],
  visiting_global : Map[Int, Int],
) -> InstanceSig {
  match td {
    @component.TypeDef::InstanceTypeEmpty => InstanceSig::empty()
    @component.TypeDef::InstanceType(decls) =>
      instancetype_sig_of_decls(decls, type_table, visiting_global)
    _ => InstanceSig::empty()
  }
}

///|
fn instancetype_sig_of_global_idx(
  tyidx : Int,
  type_table : Array[@component.TypeDef?],
  visiting_global : Map[Int, Int],
) -> InstanceSig {
  if tyidx < 0 || tyidx >= type_table.length() {
    return InstanceSig::empty()
  }
  // Avoid infinite recursion on recursive instance types; wasm-tools accepts
  // such encodings, so we conservatively stop descending.
  if visiting_global.get(tyidx) is Some(_) {
    return InstanceSig::empty()
  }
  visiting_global.set(tyidx, 1)
  match type_table[tyidx] {
    Some(td) => instancetype_sig_of_typedef(td, type_table, visiting_global)
    None => InstanceSig::empty()
  }
}

///|
fn instancetype_sig_of_local_idx(
  tyidx : Int,
  local_types : Array[@component.TypeDef],
  type_table : Array[@component.TypeDef?],
  visiting_local : Map[Int, Int],
  visiting_global : Map[Int, Int],
) -> InstanceSig {
  if tyidx < 0 {
    return InstanceSig::empty()
  }
  if tyidx < local_types.length() {
    if visiting_local.get(tyidx) is Some(_) {
      return InstanceSig::empty()
    }
    visiting_local.set(tyidx, 1)
    return instancetype_sig_of_typedef(
      local_types[tyidx],
      type_table,
      visiting_global,
    )
  }
  // Fallback to the component's type index space if the index does not refer to
  // a locally declared type. This keeps the validator tolerant of different
  // toolchain encodings.
  instancetype_sig_of_global_idx(tyidx, type_table, visiting_global)
}

///|
fn instancetype_sig_of_decls(
  decls : Array[@component.InstanceDecl],
  type_table : Array[@component.TypeDef?],
  visiting_global : Map[Int, Int],
) -> InstanceSig {
  let exports : Map[String, @component.Sort] = {}
  let nested : Map[String, InstanceSig] = {}
  // Instance types define their own internal type index space introduced by
  // `Type(...)` declarations in-order.
  let local_types : Array[@component.TypeDef] = []
  let visiting_local : Map[Int, Int] = {}
  for d in decls {
    match d {
      @component.InstanceDecl::Type(t) => local_types.push(t)
      @component.InstanceDecl::Export(name, desc) => {
        let sort = sort_of_externdesc(desc)
        exports.set(name, sort)
        match desc {
          @component.ExternDesc::InstanceType(child_tyidx) => {
            let child = instancetype_sig_of_local_idx(
              child_tyidx, local_types, type_table, visiting_local, visiting_global,
            )
            nested.set(name, child)
          }
          _ => ()
        }
      }
      _ => ()
    }
  }
  { exports, nested }
}

///|
fn instancetype_valid_for_use_as_interface(
  tyidx : Int,
  type_table : Array[@component.TypeDef?],
  type_outers : Array[Array[@component.TypeDef?]],
) -> Bool {
  if tyidx < 0 || tyidx >= type_table.length() {
    return true
  }
  match type_table[tyidx] {
    Some(@component.TypeDef::InstanceTypeEmpty) => true
    Some(@component.TypeDef::InstanceType(decls)) => {
      let local_type_table : Array[@component.TypeDef?] = []
      let local_resource_ids : Array[Int?] = []
      let local_named_types : Map[Int, Int] = {}
      let mut next_rid = 0
      fn push_local(td : @component.TypeDef?) -> Unit {
        local_type_table.push(td)
        match td {
          Some(@component.TypeDef::ResourceType(_, _, _, _)) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }

      for d in decls {
        match d {
          @component.InstanceDecl::Type(t) => push_local(Some(t))
          @component.InstanceDecl::AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let td = outer_type_of_alias(type_outers, count, idx) catch {
                _ => None
              }
              push_local(td)
            }
          @component.InstanceDecl::AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              push_local(None)
            }
          @component.InstanceDecl::Export(_name, desc) =>
            match desc {
              @component.ExternDesc::Type(bound) => {
                let new_idx = local_type_table.length()
                match bound {
                  @component.TypeBound::Eq(src) =>
                    if src >= 0 && src < local_type_table.length() {
                      push_local(local_type_table[src])
                    } else {
                      push_local(None)
                    }
                  @component.TypeBound::SubResource =>
                    push_local(
                      Some(
                        @component.TypeDef::ResourceType(
                          -1,
                          0x7f,
                          None,
                          @component.ResourceKind::HostDefined,
                        ),
                      ),
                    )
                }
                local_named_types.set(new_idx, 1)
                if !valtype_valid_for_type_import_export(
                    @component.ValType::TypeIdx(new_idx),
                    local_type_table,
                    local_resource_ids,
                    local_named_types,
                    {},
                  ) {
                  return false
                }
              }
              @component.ExternDesc::FuncType(ft_idx) =>
                if ft_idx >= 0 && ft_idx < local_type_table.length() {
                  match local_type_table[ft_idx] {
                    Some(@component.TypeDef::FuncType(ft)) =>
                      if !functype_valid_in_interface(
                          ft, local_type_table, local_resource_ids, local_named_types,
                        ) {
                        return false
                      }
                    _ => ()
                  }
                }
              _ => ()
            }
          _ => ()
        }
      }
      true
    }
    _ => true
  }
}

///|
fn componenttype_signature_of_decls(
  decls : Array[@component.ComponentDecl],
  type_table : Array[@component.TypeDef?],
) -> (
  Map[String, @component.Sort],
  Map[String, InstanceSig],
  Map[String, @component.Sort],
  Map[String, InstanceSig],
) {
  let import_sorts : Map[String, @component.Sort] = {}
  let import_instance_sigs : Map[String, InstanceSig] = {}
  let export_sorts : Map[String, @component.Sort] = {}
  let export_instance_sigs : Map[String, InstanceSig] = {}
  // Component type declarations define their own local type space introduced by
  // `Type(...)` plus type-valued alias/import/export declarations.
  let local_types : Array[@component.TypeDef] = []
  let visiting_local : Map[Int, Int] = {}
  let visiting_global : Map[Int, Int] = {}
  fn record_type_slot() -> Unit {
    // Placeholder for a type index introduced by an alias/import/export decl.
    local_types.push(@component.TypeDef::InstanceTypeEmpty)
  }

  for d in decls {
    match d {
      @component.ComponentDecl::Type(t) => local_types.push(t)
      @component.ComponentDecl::AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          record_type_slot()
        }
      @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot()
        }
      @component.ComponentDecl::Import(name, desc) => {
        import_sorts.set(name, sort_of_externdesc(desc))
        match desc {
          @component.ExternDesc::InstanceType(tyidx) => {
            let sig = instancetype_sig_of_local_idx(
              tyidx, local_types, type_table, visiting_local, visiting_global,
            )
            import_instance_sigs.set(name, sig)
          }
          _ => ()
        }
        if desc is @component.ExternDesc::Type(_) {
          record_type_slot()
        }
      }
      @component.ComponentDecl::Export(name, desc) => {
        export_sorts.set(name, sort_of_externdesc(desc))
        match desc {
          @component.ExternDesc::InstanceType(tyidx) => {
            let sig = instancetype_sig_of_local_idx(
              tyidx, local_types, type_table, visiting_local, visiting_global,
            )
            export_instance_sigs.set(name, sig)
          }
          _ => ()
        }
        if desc is @component.ExternDesc::Type(_) {
          record_type_slot()
        }
      }
      @component.ComponentDecl::CoreType(_) => ()
    }
  }
  (import_sorts, import_instance_sigs, export_sorts, export_instance_sigs)
}

///|
fn check_instance_subtype(
  actual : InstanceSig?,
  expected : InstanceSig,
) -> Unit raise ComponentValidationError {
  match actual {
    Some(sig) =>
      for kv in expected.exports.iter() {
        let (name, expected_sort) = kv
        match sig.exports.get(name) {
          Some(actual_sort) =>
            if actual_sort != expected_sort {
              raise ComponentImportTypeMismatch("export \{name}")
            } else {
              match expected.nested.get(name) {
                Some(expected_child) =>
                  match sig.nested.get(name) {
                    Some(actual_child) =>
                      check_instance_subtype(Some(actual_child), expected_child)
                    None => ()
                  }
                None => ()
              }
            }
          None => raise MissingExpectedExport(name)
        }
      }
    None => ()
  }
}

///|
fn check_core_module_subtype(
  actual : Map[String, Int]?,
  expected : Map[String, Int],
) -> Unit raise ComponentValidationError {
  match actual {
    Some(map) =>
      for kv in expected.iter() {
        let (name, expected_kind) = kv
        match map.get(name) {
          Some(actual_kind) =>
            if actual_kind != expected_kind {
              raise ComponentImportTypeMismatch("export \{name}")
            }
          None => raise MissingExpectedExport(name)
        }
      }
    None => ()
  }
}

///|
fn component_signature(
  c : @component.Component,
) -> (
  Map[String, @component.Sort],
  Map[String, InstanceSig],
  Map[String, @component.Sort],
  Map[String, InstanceSig],
) {
  let type_table : Array[@component.TypeDef?] = []
  for td in c.types {
    type_table.push(Some(td))
  }
  let import_sorts : Map[String, @component.Sort] = {}
  let import_instance_sigs : Map[String, InstanceSig] = {}
  for i in c.imports {
    match importname_to_string(i.name) {
      Some(name) => {
        let sort = sort_of_externdesc(i.desc)
        import_sorts.set(name, sort)
        match i.desc {
          @component.ExternDesc::InstanceType(tyidx) =>
            if tyidx >= 0 && tyidx < type_table.length() {
              let sig = instancetype_sig_of_global_idx(tyidx, type_table, {})
              import_instance_sigs.set(name, sig)
            }
          _ => ()
        }
      }
      None => ()
    }
  }
  let export_sorts : Map[String, @component.Sort] = {}
  let export_instance_sigs : Map[String, InstanceSig] = {}
  for e in c.exports {
    match exportname_to_string(e.name) {
      Some(name) => {
        export_sorts.set(name, e.sortidx.sort)
        match e.desc {
          Some(@component.ExternDesc::InstanceType(tyidx)) =>
            if tyidx >= 0 && tyidx < type_table.length() {
              let sig = instancetype_sig_of_global_idx(tyidx, type_table, {})
              export_instance_sigs.set(name, sig)
            }
          _ => ()
        }
      }
      None => ()
    }
  }
  (import_sorts, import_instance_sigs, export_sorts, export_instance_sigs)
}

///|
fn component_import_func_sigs_of(
  c : @component.Component,
) -> Map[String, FuncSigShape] {
  let type_table : Array[@component.TypeDef?] = []
  let resource_ids : Array[Int?] = []
  let mut next_rid = 0
  for td in c.types {
    type_table.push(Some(td))
    match td {
      @component.TypeDef::ResourceType(_, _, _, _) => {
        resource_ids.push(Some(next_rid))
        next_rid += 1
      }
      _ => resource_ids.push(None)
    }
  }
  let out : Map[String, FuncSigShape] = {}
  for i in c.imports {
    match (importname_to_string(i.name), i.desc) {
      (Some(name), @component.ExternDesc::FuncType(tyidx)) =>
        if tyidx >= 0 && tyidx < type_table.length() {
          match type_table[tyidx] {
            Some(@component.TypeDef::FuncType(ft)) =>
              out.set(name, funcsig_of_functype(ft, type_table, resource_ids))
            _ => ()
          }
        }
      _ => ()
    }
  }
  out
}

///|
fn componenttype_import_func_sigs_of_decls(
  decls : Array[@component.ComponentDecl],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
) -> Map[String, FuncSigShape] {
  let out : Map[String, FuncSigShape] = {}
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  // Avoid collisions with the enclosing component's nominal resource ids.
  let mut next_rid = 0
  for rid in global_resource_ids {
    match rid {
      Some(v) => if v >= next_rid { next_rid = v + 1 }
      None => ()
    }
  }
  fn record_type_slot() -> Unit {
    local_types.push(@component.TypeDef::InstanceTypeEmpty)
    local_resource_ids.push(None)
  }

  fn record_type_slot_for_bound(b : @component.TypeBound) -> Unit {
    match b {
      @component.TypeBound::SubResource => {
        local_types.push(
          @component.TypeDef::ResourceType(
            -1,
            0x7f,
            None,
            @component.ResourceKind::HostDefined,
          ),
        )
        local_resource_ids.push(Some(next_rid))
        next_rid += 1
      }
      @component.TypeBound::Eq(_idx) => record_type_slot()
    }
  }

  for d in decls {
    match d {
      @component.ComponentDecl::Type(t) => {
        local_types.push(t)
        match t {
          @component.TypeDef::ResourceType(_, _, _, _) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }
      @component.ComponentDecl::AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          record_type_slot()
        }
      @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot()
        }
      @component.ComponentDecl::Import(name, desc) => {
        match desc {
          @component.ExternDesc::FuncType(tyidx) =>
            if tyidx >= 0 && tyidx < local_types.length() {
              match local_types[tyidx] {
                @component.TypeDef::FuncType(ft) =>
                  out.set(
                    name,
                    funcsig_of_functype_lg(
                      ft, local_types, local_resource_ids, global_types, global_resource_ids,
                    ),
                  )
                _ => ()
              }
            } else if tyidx >= 0 && tyidx < global_types.length() {
              match global_types[tyidx] {
                Some(@component.TypeDef::FuncType(ft)) =>
                  out.set(
                    name,
                    funcsig_of_functype_lg(
                      ft,
                      [],
                      [],
                      global_types,
                      global_resource_ids,
                    ),
                  )
                _ => ()
              }
            }
          _ => ()
        }
        match desc {
          @component.ExternDesc::Type(b) => record_type_slot_for_bound(b)
          _ => ()
        }
      }
      @component.ComponentDecl::Export(_name, desc) =>
        match desc {
          @component.ExternDesc::Type(b) => record_type_slot_for_bound(b)
          _ => ()
        }
      @component.ComponentDecl::CoreType(_) => ()
    }
  }
  out
}

///|
fn componenttype_import_type_sigs_of_decls(
  decls : Array[@component.ComponentDecl],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
) -> Map[String, TypeSig] {
  let out : Map[String, TypeSig] = {}
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  // Avoid collisions with the enclosing component's nominal resource ids.
  let mut next_rid = 0
  for rid in global_resource_ids {
    match rid {
      Some(v) => if v >= next_rid { next_rid = v + 1 }
      None => ()
    }
  }
  fn record_type_slot(as_resource : Bool) -> Int {
    let idx = local_types.length()
    if as_resource {
      local_types.push(
        @component.TypeDef::ResourceType(
          -1,
          0x7f,
          None,
          @component.ResourceKind::HostDefined,
        ),
      )
      local_resource_ids.push(Some(next_rid))
      next_rid += 1
    } else {
      local_types.push(@component.TypeDef::InstanceTypeEmpty)
      local_resource_ids.push(None)
    }
    idx
  }

  for d in decls {
    match d {
      @component.ComponentDecl::Type(t) => {
        local_types.push(t)
        match t {
          @component.TypeDef::ResourceType(_, _, _, _) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }
      @component.ComponentDecl::AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          record_type_slot(false) |> ignore
        }
      @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot(false) |> ignore
        }
      @component.ComponentDecl::Import(name, desc) =>
        match desc {
          @component.ExternDesc::Type(bound) =>
            match bound {
              @component.TypeBound::Eq(tyidx) => {
                // Compute the bound signature in the current local/global environment.
                out.set(
                  name,
                  type_sig_of_valtype_lg(
                    @component.ValType::TypeIdx(tyidx),
                    local_types,
                    local_resource_ids,
                    global_types,
                    global_resource_ids,
                    {},
                  ),
                )
                record_type_slot(false) |> ignore
              }
              @component.TypeBound::SubResource => {
                let new_idx = record_type_slot(true)
                out.set(
                  name,
                  type_sig_of_valtype_lg(
                    @component.ValType::TypeIdx(new_idx),
                    local_types,
                    local_resource_ids,
                    global_types,
                    global_resource_ids,
                    {},
                  ),
                )
              }
            }
          _ =>
            if desc is @component.ExternDesc::Type(_) {
              record_type_slot(false) |> ignore
            }
        }
      @component.ComponentDecl::Export(_name, desc) =>
        match desc {
          @component.ExternDesc::Type(bound) =>
            match bound {
              @component.TypeBound::SubResource =>
                record_type_slot(true) |> ignore
              @component.TypeBound::Eq(_tyidx) =>
                record_type_slot(false) |> ignore
            }
          _ => ()
        }
      @component.ComponentDecl::CoreType(_) => ()
    }
  }
  out
}

///|
fn componenttype_import_type_bounds_of_decls(
  decls : Array[@component.ComponentDecl],
) -> Map[String, @component.TypeBound] {
  let out : Map[String, @component.TypeBound] = {}
  for d in decls {
    match d {
      @component.ComponentDecl::Import(name, @component.ExternDesc::Type(b)) =>
        out.set(name, b)
      _ => ()
    }
  }
  out
}

///|
fn componenttype_export_func_sigs_of_decls(
  decls : Array[@component.ComponentDecl],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
) -> Map[String, FuncSigShape] {
  let out : Map[String, FuncSigShape] = {}
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  // Avoid collisions with the enclosing component's nominal resource ids.
  let mut next_rid = 0
  for rid in global_resource_ids {
    match rid {
      Some(v) => if v >= next_rid { next_rid = v + 1 }
      None => ()
    }
  }
  fn record_type_slot() -> Unit {
    local_types.push(@component.TypeDef::InstanceTypeEmpty)
    local_resource_ids.push(None)
  }

  fn record_type_slot_for_bound(b : @component.TypeBound) -> Unit {
    match b {
      @component.TypeBound::SubResource => {
        local_types.push(
          @component.TypeDef::ResourceType(
            -1,
            0x7f,
            None,
            @component.ResourceKind::HostDefined,
          ),
        )
        local_resource_ids.push(Some(next_rid))
        next_rid += 1
      }
      @component.TypeBound::Eq(_idx) => record_type_slot()
    }
  }

  fn record_type_slots_for_desc(desc : @component.ExternDesc) -> Unit {
    match desc {
      @component.ExternDesc::Type(b) => record_type_slot_for_bound(b)
      _ => ()
    }
  }

  for d in decls {
    match d {
      @component.ComponentDecl::Type(t) => {
        local_types.push(t)
        match t {
          @component.TypeDef::ResourceType(_, _, _, _) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }
      @component.ComponentDecl::AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          record_type_slot()
        }
      @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot()
        }
      @component.ComponentDecl::Import(_name, desc) =>
        record_type_slots_for_desc(desc)
      @component.ComponentDecl::Export(name, desc) => {
        match desc {
          @component.ExternDesc::FuncType(tyidx) =>
            if tyidx >= 0 && tyidx < local_types.length() {
              match local_types[tyidx] {
                @component.TypeDef::FuncType(ft) =>
                  out.set(
                    name,
                    funcsig_of_functype_lg(
                      ft, local_types, local_resource_ids, global_types, global_resource_ids,
                    ),
                  )
                _ => ()
              }
            } else if tyidx >= 0 && tyidx < global_types.length() {
              match global_types[tyidx] {
                Some(@component.TypeDef::FuncType(ft)) =>
                  out.set(
                    name,
                    funcsig_of_functype_lg(
                      ft,
                      [],
                      [],
                      global_types,
                      global_resource_ids,
                    ),
                  )
                _ => ()
              }
            }
          _ => ()
        }
        record_type_slots_for_desc(desc)
      }
      @component.ComponentDecl::CoreType(_) => ()
    }
  }
  out
}

///|
/// For a given component, extract the expected export-kinds of any core-module
/// imports, keyed by the component import name.
fn component_import_core_module_exports_of(
  c : @component.Component,
) -> Map[String, Map[String, Int]] raise ComponentValidationError {
  let core_type_exports : Array[Map[String, Int]?] = []
  for payload in c.core_types {
    let exports = parse_core_type_section(payload, -1, 0, [])
    for e in exports {
      core_type_exports.push(e)
    }
  }
  let result : Map[String, Map[String, Int]] = {}
  for i in c.imports {
    match (importname_to_string(i.name), i.desc) {
      (Some(name), @component.ExternDesc::CoreModuleType(tyidx)) =>
        if tyidx >= 0 && tyidx < core_type_exports.length() {
          match core_type_exports[tyidx] {
            Some(map) => result.set(name, map)
            None => ()
          }
        }
      _ => ()
    }
  }
  result
}

///|
fn component_import_core_module_import_sigs_of(
  c : @component.Component,
) -> Map[String, Map[String, CoreExternType]] raise ComponentValidationError {
  let core_type_imports : Array[Array[CoreModuleTypeImport]?] = []
  let mut base_bound = 0
  for payload in c.core_types {
    let (imports, _export_types) = parse_core_type_section_module_sigs(
      payload,
      -1,
      base_bound,
      [],
    )
    for imps in imports {
      core_type_imports.push(imps)
    }
    base_bound += imports.length()
  }
  let result : Map[String, Map[String, CoreExternType]] = {}
  for i in c.imports {
    match (importname_to_string(i.name), i.desc) {
      (Some(name), @component.ExternDesc::CoreModuleType(tyidx)) =>
        if tyidx >= 0 && tyidx < core_type_imports.length() {
          match core_type_imports[tyidx] {
            Some(imps) => {
              let map : Map[String, CoreExternType] = {}
              for imp in imps {
                map.set("\{imp.mod_name}::\{imp.name}", imp.ty)
              }
              result.set(name, map)
            }
            None => ()
          }
        }
      _ => ()
    }
  }
  result
}

///|
fn componenttype_import_core_module_sigs_of_decls(
  decls : Array[@component.ComponentDecl],
) -> (Map[String, Map[String, CoreExternType]], Map[String, Map[String, Int]]) raise ComponentValidationError {
  let local_core_import_sigs : Array[Map[String, CoreExternType]?] = []
  let local_core_export_kinds : Array[Map[String, Int]?] = []
  let mut core_type_bound = 0
  for d in decls {
    match d {
      @component.ComponentDecl::CoreType(bytes) => {
        let r = CoreTypeReader::new(bytes)
        let op = r.read_u8()
        if op == 0x50 {
          let (imps, exps) = parse_core_type_module_sig(
            r,
            -1,
            core_type_bound,
            [],
          )
          let imp_map : Map[String, CoreExternType] = {}
          for imp in imps {
            imp_map.set("\{imp.mod_name}::\{imp.name}", imp.ty)
          }
          let exp_kinds : Map[String, Int] = {}
          for kv in exps.iter() {
            let (nm, ty) = kv
            exp_kinds.set(nm, core_kind_of_extern_type(ty))
          }
          local_core_import_sigs.push(Some(imp_map))
          local_core_export_kinds.push(Some(exp_kinds))
        } else if op == 0x60 {
          r.skip_func_type_body()
          local_core_import_sigs.push(None)
          local_core_export_kinds.push(None)
        } else {
          raise SectionParseError(3, "unsupported core type opcode: \{op}")
        }
        if !r.is_eof() {
          raise SectionParseError(3, "trailing bytes in core type payload")
        }
        core_type_bound += 1
      }
      @component.ComponentDecl::AliasOuter(kind, _count, _idx) =>
        if kind != 0x03 {
          // Core-type aliases consume a core-type index.
          local_core_import_sigs.push(None)
          local_core_export_kinds.push(None)
          core_type_bound += 1
        }
      @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
        if kind != 0x03 {
          local_core_import_sigs.push(None)
          local_core_export_kinds.push(None)
          core_type_bound += 1
        }
      _ => ()
    }
  }
  let import_sigs : Map[String, Map[String, CoreExternType]] = {}
  let export_kinds : Map[String, Map[String, Int]] = {}
  for d in decls {
    match d {
      @component.ComponentDecl::Import(name, desc) =>
        match desc {
          @component.ExternDesc::CoreModuleType(tyidx) =>
            if tyidx >= 0 && tyidx < local_core_import_sigs.length() {
              match local_core_import_sigs[tyidx] {
                Some(map) => import_sigs.set(name, map)
                None => ()
              }
              match local_core_export_kinds[tyidx] {
                Some(map) => export_kinds.set(name, map)
                None => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
  (import_sigs, export_kinds)
}

///|
fn check_typeidx(idx : Int, bound : Int) -> Unit raise ComponentValidationError {
  if idx < 0 || idx >= bound {
    raise InvalidTypeIndex(idx)
  }
}

///|
fn check_sortidx(
  sortidx : @component.SortIdx,
  counts : Counts,
  type_bound : Int,
) -> Unit raise ComponentValidationError {
  let idx = sortidx.idx
  match sortidx.sort {
    Type => if idx < 0 || idx >= type_bound { raise InvalidTypeIndex(idx) }
    Func => if idx < 0 || idx >= counts.func { raise InvalidFuncIndex(idx) }
    Value => if idx < 0 || idx >= counts.value { raise InvalidValueIndex(idx) }
    Component =>
      if idx < 0 || idx >= counts.component {
        raise InvalidComponentIndex(idx)
      }
    Instance =>
      if idx < 0 || idx >= counts.instance {
        raise InvalidInstanceIndex(idx)
      }
    Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= counts.core_func {
            raise InvalidCoreFuncIndex(idx)
          }
        0x01 =>
          if idx < 0 || idx >= counts.core_table {
            raise InvalidCoreTableIndex(idx)
          }
        0x02 =>
          if idx < 0 || idx >= counts.core_memory {
            raise InvalidCoreMemoryIndex(idx)
          }
        0x03 =>
          if idx < 0 || idx >= counts.core_global {
            raise InvalidCoreGlobalIndex(idx)
          }
        0x04 =>
          if idx < 0 || idx >= counts.core_tag {
            raise InvalidCoreTagIndex(idx)
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= counts.core_type {
            raise InvalidCoreTypeIndex(idx)
          }
        0x11 =>
          if idx < 0 || idx >= counts.core_module {
            raise InvalidCoreModuleIndex(idx)
          }
        0x12 =>
          if idx < 0 || idx >= counts.core_instance {
            raise InvalidCoreInstanceIndex(idx)
          }
        _ => raise UnsupportedCoreSort(core_sort)
      }
  }
}

///|
fn count_import(desc : @component.ExternDesc, counts : Counts) -> Unit {
  match desc {
    CoreModuleType(_tyidx) => counts.core_module += 1
    FuncType(_tyidx) => counts.func += 1
    Value(_b) => counts.value += 1
    Type(_b) => ()
    ComponentType(_tyidx) => counts.component += 1
    InstanceType(_tyidx) => counts.instance += 1
  }
}

///|
fn sort_of_externdesc(desc : @component.ExternDesc) -> @component.Sort {
  match desc {
    CoreModuleType(_) => @component.Sort::Core(0x11)
    FuncType(_) => @component.Sort::Func
    Value(_) => @component.Sort::Value
    Type(_) => @component.Sort::Type
    ComponentType(_) => @component.Sort::Component
    InstanceType(_) => @component.Sort::Instance
  }
}

///|
fn count_alias(
  sort : @component.Sort,
  counts : Counts,
) -> Unit raise ComponentValidationError {
  match sort {
    Func => counts.func += 1
    Value => counts.value += 1
    Type => ()
    Component => counts.component += 1
    Instance => counts.instance += 1
    Core(core_sort) =>
      match core_sort {
        0x00 => counts.core_func += 1
        0x01 => counts.core_table += 1
        0x02 => counts.core_memory += 1
        0x03 => counts.core_global += 1
        0x04 => counts.core_tag += 1
        0x05 | 0x10 => counts.core_type += 1
        0x11 => counts.core_module += 1
        0x12 => counts.core_instance += 1
        _ => raise UnsupportedCoreSort(core_sort)
      }
  }
}

///|
fn count_canon(c : @component.Canon, counts : Counts) -> Unit {
  match c {
    Lift(_, _, _) => counts.func += 1
    // All other canonical items produce a core function.
    _ => counts.core_func += 1
  }
}

///|
fn validate_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Unit raise ComponentValidationError {
  match ty {
    TypeIdx(idx) => {
      check_typeidx(idx, type_table.length())
      match type_table[idx] {
        // Component valtypes may reference any defined type (not function,
        // component, or instance types).
        Some(@component.TypeDef::FuncType(_))
        | Some(@component.TypeDef::ComponentType(_))
        | Some(@component.TypeDef::InstanceTypeEmpty)
        | Some(@component.TypeDef::InstanceType(_)) =>
          raise TypeIndexNotDefinedType(idx)
        Some(_) => ()
        None => ()
      }
    }
    Prim(_) => ()
  }
}

///|
fn check_core_typeidx(
  idx : Int,
  bound : Int,
) -> Unit raise ComponentValidationError {
  if idx < 0 || idx >= bound {
    raise InvalidCoreTypeIndex(idx)
  }
}

///|
fn outer_type_of_alias(
  type_outers : Array[Array[@component.TypeDef?]],
  count : Int,
  idx : Int,
) -> @component.TypeDef? raise ComponentValidationError {
  if count <= 0 || count > type_outers.length() {
    raise InvalidTypeIndex(idx)
  }
  let tbl = type_outers[count - 1]
  check_typeidx(idx, tbl.length())
  tbl[idx]
}

///|
fn outer_core_type_of_alias(
  core_type_outers : Array[Array[Map[String, Int]?]],
  count : Int,
  idx : Int,
) -> Map[String, Int]? raise ComponentValidationError {
  if count <= 0 || count > core_type_outers.length() {
    raise InvalidCoreTypeIndex(idx)
  }
  let tbl = core_type_outers[count - 1]
  check_core_typeidx(idx, tbl.length())
  tbl[idx]
}

///|
fn component_outer_type_of_alias(
  current_types : Array[@component.TypeDef?],
  type_outers : Array[Array[@component.TypeDef?]],
  count : Int,
  idx : Int,
) -> @component.TypeDef? raise ComponentValidationError {
  if count == 0 {
    check_typeidx(idx, current_types.length())
    current_types[idx]
  } else {
    outer_type_of_alias(type_outers, count, idx)
  }
}

///|
fn valtype_contains_borrow(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    @component.ValType::Prim(_) => false
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        false
      } else if visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, 1)
        let any = match type_table[idx] {
          Some(@component.TypeDef::Borrow(_)) => true
          Some(@component.TypeDef::Tuple(xs)) => {
            let mut any = false
            for v in xs {
              if valtype_contains_borrow(v, type_table, visiting) {
                any = true
                break
              }
            }
            any
          }
          Some(@component.TypeDef::Record(fields)) => {
            let mut any = false
            for f in fields {
              if valtype_contains_borrow(f.ty, type_table, visiting) {
                any = true
                break
              }
            }
            any
          }
          Some(@component.TypeDef::Variant(cases)) => {
            let mut any = false
            for c in cases {
              match c.ty {
                None => ()
                Some(v) =>
                  if valtype_contains_borrow(v, type_table, visiting) {
                    any = true
                    break
                  }
              }
            }
            any
          }
          Some(@component.TypeDef::Option(v)) =>
            valtype_contains_borrow(v, type_table, visiting)
          Some(@component.TypeDef::Result(ok, err)) => {
            let ok_any = match ok {
              None => false
              Some(v) => valtype_contains_borrow(v, type_table, visiting)
            }
            let err_any = match err {
              None => false
              Some(v) => valtype_contains_borrow(v, type_table, visiting)
            }
            ok_any || err_any
          }
          Some(@component.TypeDef::List(v)) =>
            valtype_contains_borrow(v, type_table, visiting)
          Some(@component.TypeDef::Stream(v))
          | Some(@component.TypeDef::Future(v)) =>
            match v {
              None => false
              Some(inner) =>
                valtype_contains_borrow(inner, type_table, visiting)
            }
          Some(@component.TypeDef::Own(idx2)) =>
            valtype_contains_borrow(
              @component.ValType::TypeIdx(idx2),
              type_table,
              visiting,
            )
          _ => false
        }
        visiting.remove(idx) |> ignore
        any
      }
  }
}

///|
fn validate_typedef(
  td : @component.TypeDef,
  cfg : ComponentValidationConfig,
  type_outers : Array[Array[@component.TypeDef?]],
  core_type_outers : Array[Array[Map[String, Int]?]],
  allow_resource_defs : Bool,
) -> Unit raise ComponentValidationError {
  if type_outers.length() == 0 || core_type_outers.length() == 0 {
    raise SectionParseError(
      7, "missing outer environment for typedef validation",
    )
  }
  let type_table = type_outers[0]
  let outer_core_type_bounds : Array[Int] = []
  for i in 0..<core_type_outers.length() {
    outer_core_type_bounds.push(core_type_outers[i].length())
  }
  match td {
    DefValType(_) => ()
    List(v) => validate_valtype(v, type_table)
    Record(fields) => {
      if fields.length() == 0 {
        raise SectionParseError(7, "record type must have at least one field")
      }
      let seen : Map[String, String] = {}
      for f in fields {
        validate_extern_name_string(f.label, cfg)
        let key = ascii_lower_key(f.label)
        match seen.get(key) {
          Some(prev) =>
            raise SectionParseError(
              7,
              "record field name `\{f.label}` conflicts with previous field name `\{prev}`",
            )
          None => seen.set(key, f.label)
        }
        validate_valtype(f.ty, type_table)
      }
    }
    Variant(cases) => {
      if cases.length() == 0 {
        raise SectionParseError(7, "variant type must have at least one case")
      }
      let seen : Map[String, String] = {}
      for i in 0..<cases.length() {
        let c = cases[i]
        validate_extern_name_string(c.label, cfg)
        let key = ascii_lower_key(c.label)
        match seen.get(key) {
          Some(prev) =>
            raise SectionParseError(
              7,
              "variant case name `\{c.label}` conflicts with previous case name `\{prev}`",
            )
          None => seen.set(key, c.label)
        }
        match c.refines {
          Some(idx) =>
            if idx < 0 || idx >= i {
              raise SectionParseError(
                7, "variant case can only refine a previously defined case",
              )
            }
          None => ()
        }
        match c.ty {
          Some(v) => validate_valtype(v, type_table)
          None => ()
        }
      }
    }
    Tuple(tys) => {
      if tys.length() == 0 {
        raise SectionParseError(7, "tuple type must have at least one type")
      }
      for v in tys {
        validate_valtype(v, type_table)
      }
    }
    Flags(cases) => {
      if cases.length() == 0 {
        raise SectionParseError(7, "flags must have at least one entry")
      }
      if cases.length() > 32 {
        raise SectionParseError(7, "cannot have more than 32 flags")
      }
      let seen : Map[String, String] = {}
      for name in cases {
        validate_extern_name_string(name, cfg)
        let key = ascii_lower_key(name)
        match seen.get(key) {
          Some(prev) =>
            raise SectionParseError(
              7,
              "flag name `\{name}` conflicts with previous flag name `\{prev}`",
            )
          None => seen.set(key, name)
        }
      }
    }
    Enum(cases) => {
      if cases.length() == 0 {
        raise SectionParseError(7, "enum type must have at least one variant")
      }
      let seen : Map[String, String] = {}
      for name in cases {
        validate_extern_name_string(name, cfg)
        let key = ascii_lower_key(name)
        match seen.get(key) {
          Some(prev) =>
            raise SectionParseError(
              7,
              "enum tag name `\{name}` conflicts with previous tag name `\{prev}`",
            )
          None => seen.set(key, name)
        }
      }
    }
    Option(v) => validate_valtype(v, type_table)
    Result(ok, err) => {
      match ok {
        Some(v) => validate_valtype(v, type_table)
        None => ()
      }
      match err {
        Some(v) => validate_valtype(v, type_table)
        None => ()
      }
    }
    Own(ti) | Borrow(ti) => {
      if ti < 0 || ti >= type_table.length() {
        raise SectionParseError(7, "type index out of bounds")
      }
      match type_table[ti] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        None => ()
        Some(_) => raise SectionParseError(7, "not a resource type")
      }
    }
    Stream(v) | Future(v) =>
      match v {
        Some(t) => validate_valtype(t, type_table)
        None => ()
      }
    ResourceType(_, rep, _dtor, _kind) => {
      if !allow_resource_defs {
        raise SectionParseError(
          7, "resources can only be defined within a concrete component",
        )
      }
      if rep != 0x7f {
        raise SectionParseError(7, "resources can only be represented by `i32`")
      }
    }
    ComponentType(decls) => {
      // Component type declarations define their own internal type/core-type
      // index spaces referenced by later imports/exports within the same type.
      let local_type_table : Array[@component.TypeDef?] = []
      let local_resource_ids : Array[Int?] = []
      let mut local_core_type_bound = 0
      let seen_imports : Map[String, String] = {}
      let seen_exports : Map[String, String] = {}
      let local_named_types : Map[Int, Int] = {}
      let local_import_resource_names : Map[String, Int] = {}
      let local_export_resource_names : Map[String, Int] = {}
      let local_import_resource_type_idxs : Map[Int, Int] = {}
      let local_export_resource_type_idxs : Map[Int, Int] = {}
      let local_core_type_exports : Array[Map[String, Int]?] = []
      for d in decls {
        match d {
          @component.ComponentDecl::CoreType(bytes) => {
            local_core_type_exports.push(
              validate_single_core_type(
                bytes, local_core_type_bound, outer_core_type_bounds,
              ),
            )
            local_core_type_bound += 1
          }
          @component.ComponentDecl::AliasOuter(kind, count, idx) =>
            // Component-model extern kinds use the same discriminants as the
            // component export kind encoding; `Type` is 0x03.
            if kind == 0x03 {
              local_type_table.push(
                outer_type_of_alias(type_outers, count, idx),
              )
              local_resource_ids.push(None)
            } else {
              local_core_type_exports.push(
                outer_core_type_of_alias(core_type_outers, count, idx),
              )
              local_core_type_bound += 1
            }
          @component.ComponentDecl::AliasInstanceExport(
            kind,
            _instance_idx,
            _name
          ) =>
            if kind == 0x03 {
              local_type_table.push(None)
              local_resource_ids.push(None)
            } else {
              local_core_type_exports.push(None)
              local_core_type_bound += 1
            }
          @component.ComponentDecl::Type(t) => {
            validate_typedef(
              t,
              cfg,
              [local_type_table] + type_outers,
              [local_core_type_exports] + core_type_outers,
              false,
            )
            local_type_table.push(Some(t))
            local_resource_ids.push(None)
          }
          @component.ComponentDecl::Import(name, desc) => {
            validate_extern_name_string(name, cfg)
            let key = ascii_lower_key(name)
            match seen_imports.get(key) {
              Some(prev) =>
                if prev == name {
                  raise DuplicateImportName(name)
                } else {
                  raise SectionParseError(
                    7,
                    "import name `\{name}` conflicts with previous name `\{prev}`",
                  )
                }
              None => seen_imports.set(key, name)
            }
            validate_externdesc(desc, local_type_table, local_core_type_bound)
            match desc {
              @component.ExternDesc::CoreModuleType(tyidx) =>
                if tyidx < 0 ||
                  tyidx >= local_core_type_exports.length() ||
                  local_core_type_exports[tyidx] is None {
                  raise CoreTypeIndexNotModuleType(tyidx)
                }
              _ => ()
            }
            match desc {
              @component.ExternDesc::Type(bound) => {
                let new_idx = local_type_table.length()
                match bound {
                  @component.TypeBound::Eq(tyidx) =>
                    if tyidx >= 0 && tyidx < local_type_table.length() {
                      local_type_table.push(local_type_table[tyidx])
                      local_resource_ids.push(local_resource_ids[tyidx])
                    } else {
                      local_type_table.push(None)
                      local_resource_ids.push(None)
                    }
                  @component.TypeBound::SubResource => {
                    local_type_table.push(
                      Some(
                        @component.TypeDef::ResourceType(
                          -1,
                          0x7f,
                          None,
                          @component.ResourceKind::HostDefined,
                        ),
                      ),
                    )
                    local_resource_ids.push(None)
                  }
                }
                local_named_types.set(new_idx, 1)
                match bound {
                  @component.TypeBound::SubResource => {
                    local_import_resource_names.set(name, new_idx)
                    local_import_resource_type_idxs.set(new_idx, 1)
                  }
                  _ => ()
                }
                if !valtype_valid_for_type_import_export(
                    @component.ValType::TypeIdx(new_idx),
                    local_type_table,
                    local_resource_ids,
                    local_named_types,
                    {},
                  ) {
                  raise SectionParseError(
                    7, "type not valid to be used as import",
                  )
                }
              }
              @component.ExternDesc::FuncType(tyidx) =>
                if tyidx >= 0 && tyidx < local_type_table.length() {
                  match local_type_table[tyidx] {
                    Some(@component.TypeDef::FuncType(ft)) => {
                      validate_bracketed_func_name(
                        7, name, ft, local_type_table, local_resource_ids, local_import_resource_names,
                      )
                      if functype_uses_disallowed_resources(
                          ft, local_type_table, local_import_resource_type_idxs,
                        ) {
                        raise SectionParseError(
                          7, "func not valid to be used as import",
                        )
                      }
                      if !functype_valid_in_interface(
                          ft, local_type_table, local_resource_ids, local_named_types,
                        ) {
                        raise SectionParseError(
                          7, "func not valid to be used as import",
                        )
                      }
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
          @component.ComponentDecl::Export(name, desc) => {
            validate_extern_name_string(name, cfg)
            let key = ascii_lower_key(name)
            match seen_exports.get(key) {
              Some(prev) =>
                if prev == name {
                  raise DuplicateExportName(name)
                } else {
                  raise SectionParseError(
                    7,
                    "export name `\{name}` conflicts with previous name `\{prev}`",
                  )
                }
              None => seen_exports.set(key, name)
            }
            validate_externdesc(desc, local_type_table, local_core_type_bound)
            match desc {
              @component.ExternDesc::CoreModuleType(tyidx) =>
                if tyidx < 0 ||
                  tyidx >= local_core_type_exports.length() ||
                  local_core_type_exports[tyidx] is None {
                  raise CoreTypeIndexNotModuleType(tyidx)
                }
              _ => ()
            }
            match desc {
              @component.ExternDesc::Type(bound) => {
                let new_idx = local_type_table.length()
                match bound {
                  @component.TypeBound::Eq(tyidx) =>
                    if tyidx >= 0 && tyidx < local_type_table.length() {
                      local_type_table.push(local_type_table[tyidx])
                      local_resource_ids.push(local_resource_ids[tyidx])
                    } else {
                      local_type_table.push(None)
                      local_resource_ids.push(None)
                    }
                  @component.TypeBound::SubResource => {
                    local_type_table.push(
                      Some(
                        @component.TypeDef::ResourceType(
                          -1,
                          0x7f,
                          None,
                          @component.ResourceKind::HostDefined,
                        ),
                      ),
                    )
                    local_resource_ids.push(None)
                  }
                }
                local_named_types.set(new_idx, 1)
                match bound {
                  @component.TypeBound::SubResource => {
                    local_export_resource_names.set(name, new_idx)
                    local_export_resource_type_idxs.set(new_idx, 1)
                  }
                  _ => ()
                }
                if !valtype_valid_for_type_import_export(
                    @component.ValType::TypeIdx(new_idx),
                    local_type_table,
                    local_resource_ids,
                    local_named_types,
                    {},
                  ) {
                  raise SectionParseError(
                    7, "type not valid to be used as export",
                  )
                }
              }
              @component.ExternDesc::FuncType(tyidx) =>
                if tyidx >= 0 && tyidx < local_type_table.length() {
                  match local_type_table[tyidx] {
                    Some(@component.TypeDef::FuncType(ft)) => {
                      validate_bracketed_func_name(
                        7, name, ft, local_type_table, local_resource_ids, local_export_resource_names,
                      )
                      if !functype_valid_in_interface(
                          ft, local_type_table, local_resource_ids, local_named_types,
                        ) {
                        raise SectionParseError(
                          7, "func not valid to be used as export",
                        )
                      }
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
        }
      }
    }
    InstanceTypeEmpty => ()
    InstanceType(decls) => {
      // Instance type declarations define their own internal type index space
      // which is referenced by later exports within the same instance type.
      let local_type_table : Array[@component.TypeDef?] = []
      let mut local_core_type_bound = 0
      let seen_exports : Map[String, String] = {}
      let local_core_type_exports : Array[Map[String, Int]?] = []
      for d in decls {
        match d {
          @component.InstanceDecl::CoreType(bytes) => {
            let r = CoreTypeReader::new(bytes)
            let op = r.read_u8()
            if op == 0x50 {
              local_core_type_exports.push(
                Some(
                  parse_core_type_module_exports(r, -1, local_core_type_bound, []),
                ),
              )
            } else if op == 0x60 {
              r.skip_func_type_body()
              local_core_type_exports.push(None)
            } else {
              raise SectionParseError(3, "unsupported core type opcode: \{op}")
            }
            if !r.is_eof() {
              raise SectionParseError(3, "trailing bytes in core type payload")
            }
            local_core_type_bound += 1
          }
          @component.InstanceDecl::AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              local_type_table.push(
                outer_type_of_alias(type_outers, count, idx),
              )
            } else {
              local_core_type_exports.push(
                outer_core_type_of_alias(core_type_outers, count, idx),
              )
              local_core_type_bound += 1
            }
          @component.InstanceDecl::AliasInstanceExport(
            kind,
            _instance_idx,
            _name
          ) =>
            if kind == 0x03 {
              local_type_table.push(None)
            } else {
              local_core_type_exports.push(None)
              local_core_type_bound += 1
            }
          @component.InstanceDecl::Type(t) => {
            validate_typedef(
              t,
              cfg,
              [local_type_table] + type_outers,
              [local_core_type_exports] + core_type_outers,
              false,
            )
            local_type_table.push(Some(t))
          }
          @component.InstanceDecl::Export(name, desc) => {
            validate_extern_name_string(name, cfg)
            let key = ascii_lower_key(name)
            match seen_exports.get(key) {
              Some(prev) =>
                if prev == name {
                  raise DuplicateExportName(name)
                } else {
                  raise SectionParseError(
                    7,
                    "export name `\{name}` conflicts with previous name `\{prev}`",
                  )
                }
              None => seen_exports.set(key, name)
            }
            validate_externdesc(desc, local_type_table, local_core_type_bound)
            match desc {
              @component.ExternDesc::CoreModuleType(tyidx) =>
                if tyidx < 0 ||
                  tyidx >= local_core_type_exports.length() ||
                  local_core_type_exports[tyidx] is None {
                  raise CoreTypeIndexNotModuleType(tyidx)
                }
              _ => ()
            }
            // Like the component export section, exporting a type introduces
            // a fresh type index in this instance type's local type space.
            if desc is Type(_) {
              local_type_table.push(None)
            }
          }
        }
      }
    }
    FuncType(ft) => {
      let seen_params : Map[String, String] = {}
      for p in ft.params {
        validate_extern_name_string(p.label, cfg)
        let key = ascii_lower_key(p.label)
        match seen_params.get(key) {
          Some(prev) => raise FuncParamNameConflict(p.label, prev)
          None => seen_params.set(key, p.label)
        }
        validate_valtype(p.ty, type_table)
      }
      match ft.result {
        Some(r) => {
          validate_valtype(r, type_table)
          if valtype_contains_borrow(r, type_table, {}) {
            raise SectionParseError(
              7, "function result cannot contain a `borrow` type",
            )
          }
        }
        None => ()
      }
    }
  }
}

///|
fn validate_externdesc(
  desc : @component.ExternDesc,
  type_table : Array[@component.TypeDef?],
  core_type_bound : Int,
) -> Unit raise ComponentValidationError {
  match desc {
    CoreModuleType(tyidx) => check_typeidx(tyidx, core_type_bound)
    FuncType(tyidx) => {
      check_typeidx(tyidx, type_table.length())
      match type_table[tyidx] {
        Some(@component.TypeDef::FuncType(_)) => ()
        Some(_) | None => raise TypeIndexNotFuncType(tyidx)
      }
    }
    ComponentType(tyidx) => {
      check_typeidx(tyidx, type_table.length())
      match type_table[tyidx] {
        Some(@component.TypeDef::ComponentType(_)) => ()
        Some(_) | None => raise TypeIndexNotComponentType(tyidx)
      }
    }
    InstanceType(tyidx) => {
      check_typeidx(tyidx, type_table.length())
      match type_table[tyidx] {
        Some(@component.TypeDef::InstanceType(_))
        | Some(@component.TypeDef::InstanceTypeEmpty) => ()
        Some(_) | None => raise TypeIndexNotInstanceType(tyidx)
      }
    }
    Type(b) =>
      match b {
        Eq(tyidx) => check_typeidx(tyidx, type_table.length())
        SubResource => ()
      }
    Value(b) =>
      match b {
        Eq(_v) => ()
        Type(vt) => validate_valtype(vt, type_table)
      }
  }
}

///|
fn validate_canon_opts(
  opts : Array[@component.CanonOpt],
) -> Unit raise ComponentValidationError {
  let mut seen_encoding = false
  let mut seen_memory = false
  let mut seen_realloc = false
  let mut seen_post_return = false
  let mut seen_callback = false
  let mut seen_async = false
  for o in opts {
    match o {
      StringEncoding(_) =>
        if seen_encoding {
          raise DuplicateCanonOption("string-encoding")
        } else {
          seen_encoding = true
        }
      Memory(_) =>
        if seen_memory {
          raise DuplicateCanonOption("memory")
        } else {
          seen_memory = true
        }
      Realloc(_) =>
        if seen_realloc {
          raise DuplicateCanonOption("realloc")
        } else {
          seen_realloc = true
        }
      PostReturn(_) =>
        if seen_post_return {
          raise DuplicateCanonOption("post-return")
        } else {
          seen_post_return = true
        }
      Callback(_) =>
        if seen_callback {
          raise DuplicateCanonOption("callback")
        } else {
          seen_callback = true
        }
      Async =>
        if seen_async {
          raise DuplicateCanonOption("async")
        } else {
          seen_async = true
        }
    }
  }
}

///|
fn canon_has_memory(opts : Array[@component.CanonOpt]) -> Bool {
  for o in opts {
    if o is Memory(_) {
      return true
    }
  }
  false
}

///|
fn canon_has_realloc(opts : Array[@component.CanonOpt]) -> Bool {
  for o in opts {
    if o is Realloc(_) {
      return true
    }
  }
  false
}

///|
fn canon_has_async(opts : Array[@component.CanonOpt]) -> Bool {
  for o in opts {
    if o is Async {
      return true
    }
  }
  false
}

///|
fn canon_has_post_return(opts : Array[@component.CanonOpt]) -> Bool {
  for o in opts {
    if o is PostReturn(_) {
      return true
    }
  }
  false
}

///|
fn canon_memory_idx(opts : Array[@component.CanonOpt]) -> Int? {
  for o in opts {
    match o {
      Memory(idx) => return Some(idx)
      _ => ()
    }
  }
  None
}

///|
fn canon_realloc_idx(opts : Array[@component.CanonOpt]) -> Int? {
  for o in opts {
    match o {
      Realloc(idx) => return Some(idx)
      _ => ()
    }
  }
  None
}

///|
fn canon_post_return_idx(opts : Array[@component.CanonOpt]) -> Int? {
  for o in opts {
    match o {
      PostReturn(idx) => return Some(idx)
      _ => ()
    }
  }
  None
}

///|
fn valtype_needs_memory(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
  core_valtypes_for_component_valtype(ty, type_table) is None
}

///|
fn functype_needs_memory(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
  // Canonical ABI uses linear memory when:
  // - any param/result type itself needs memory (e.g. string/list), or
  // - the flattened parameter list is too large (>16), or
  // - the result can't be represented as a single core value.
  let mut param_count = 0
  for p in ft.params {
    match core_valtypes_for_component_valtype(p.ty, type_table) {
      Some(ts) => {
        param_count += ts.length()
        if param_count > 16 {
          return true
        }
      }
      None => return true
    }
  }
  match ft.result {
    None => false
    Some(r) =>
      match core_valtypes_for_component_valtype(r, type_table) {
        None => true
        Some(ts) => ts.length() != 1
      }
  }
}

///|
fn functype_needs_realloc_for_lift(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
  // For canon lift, `realloc` is required when the wrapper must allocate/write
  // linear memory to pass params (strings/lists or indirect args).
  let mut param_count = 0
  for p in ft.params {
    match core_valtypes_for_component_valtype(p.ty, type_table) {
      Some(ts) => {
        param_count += ts.length()
        if param_count > 16 {
          return true
        }
      }
      None => return true
    }
  }
  false
}

///|
fn functype_needs_realloc_for_lower(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
  // For canon lower, `realloc` is required when the wrapper must write a
  // component value into core linear memory as a result.
  match ft.result {
    Some(r) => core_valtypes_for_component_valtype(r, type_table) is None
    None => false
  }
}

///|
fn core_valtypes_for_component_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Array[@types.ValueType]? {
  // For now, we only model the "flat" ABI for scalar/composite values that can
  // be represented without linear memory. Types that require memory (strings,
  // lists, etc) return `None` and skip signature checks; those are still
  // validated structurally by canonical option checks.
  let visiting : Map[Int, Unit] = {}
  fn scalar_prim(p : @component.PrimValType) -> Array[@types.ValueType]? {
    match p {
      @component.PrimValType::Bool
      | @component.PrimValType::S8
      | @component.PrimValType::U8
      | @component.PrimValType::S16
      | @component.PrimValType::U16
      | @component.PrimValType::S32
      | @component.PrimValType::U32
      | @component.PrimValType::Char => Some([@types.ValueType::I32])
      @component.PrimValType::S64 | @component.PrimValType::U64 =>
        Some([@types.ValueType::I64])
      @component.PrimValType::F32 => Some([@types.ValueType::F32])
      @component.PrimValType::F64 => Some([@types.ValueType::F64])
      // Strings/results need canonical ABI memory rules.
      @component.PrimValType::String | @component.PrimValType::ErrorContext =>
        None
    }
  }

  fn join_flat(a : @types.ValueType, b : @types.ValueType) -> @types.ValueType {
    if a == b {
      return a
    }
    // The canonical ABI uses "join" to unify variant payloads with differing
    // shapes. Mixed integer/float representations fall back to integer bit
    // patterns (I32/I64) to preserve bits and allow masking.
    match (a, b) {
      (@types.ValueType::I64, _)
      | (_, @types.ValueType::I64)
      | (@types.ValueType::F64, _)
      | (_, @types.ValueType::F64) => @types.ValueType::I64
      (@types.ValueType::F32, @types.ValueType::I32)
      | (@types.ValueType::I32, @types.ValueType::F32) => @types.ValueType::I32
      (@types.ValueType::F32, @types.ValueType::F64)
      | (@types.ValueType::F64, @types.ValueType::F32) => @types.ValueType::I64
      (@types.ValueType::F32, @types.ValueType::I64)
      | (@types.ValueType::I64, @types.ValueType::F32) => @types.ValueType::I64
      (@types.ValueType::I32, _) | (_, @types.ValueType::I32) =>
        @types.ValueType::I32
      // Default to I64 for any other mixed case (conservative).
      _ => @types.ValueType::I64
    }
  }

  fn scalar_flat_valtype(vt : @component.ValType) -> Array[@types.ValueType]? {
    match vt {
      @component.ValType::Prim(p) => scalar_prim(p)
      @component.ValType::TypeIdx(idx) => {
        if idx < 0 || idx >= type_table.length() {
          return None
        }
        match visiting.get(idx) {
          Some(_) => None
          None => {
            visiting.set(idx, ())
            let res = match type_table[idx] {
              None => None
              Some(td) =>
                match td {
                  @component.TypeDef::DefValType(p) => scalar_prim(p)
                  @component.TypeDef::Tuple(tys) => {
                    let out : Array[@types.ValueType] = []
                    for t in tys {
                      match scalar_flat_valtype(t) {
                        Some(ts) =>
                          for x in ts {
                            out.push(x)
                            if out.length() > 16 {
                              return None
                            }
                          }
                        None => return None
                      }
                    }
                    Some(out)
                  }
                  @component.TypeDef::Record(fields) => {
                    let out : Array[@types.ValueType] = []
                    for f in fields {
                      match scalar_flat_valtype(f.ty) {
                        Some(ts) =>
                          for x in ts {
                            out.push(x)
                            if out.length() > 16 {
                              return None
                            }
                          }
                        None => return None
                      }
                    }
                    Some(out)
                  }
                  @component.TypeDef::Variant(cases) => {
                    let payloads : Array[Array[@types.ValueType]] = []
                    let mut max_len = 0
                    for c in cases {
                      let flat = match c.ty {
                        None => []
                        Some(t) =>
                          match scalar_flat_valtype(t) {
                            Some(ts) => ts
                            None => return None
                          }
                      }
                      if flat.length() > max_len {
                        max_len = flat.length()
                      }
                      payloads.push(flat)
                    }
                    let joined : Array[@types.ValueType] = []
                    for i in 0..<max_len {
                      let mut cur : @types.ValueType? = None
                      for p in payloads {
                        if i < p.length() {
                          cur = match cur {
                            None => Some(p[i])
                            Some(prev) => Some(join_flat(prev, p[i]))
                          }
                        }
                      }
                      match cur {
                        None => ()
                        Some(t) => joined.push(t)
                      }
                    }
                    if 1 + joined.length() > 16 {
                      None
                    } else {
                      Some([@types.ValueType::I32] + joined)
                    }
                  }
                  @component.TypeDef::Option(v) =>
                    match scalar_flat_valtype(v) {
                      Some(payload) =>
                        if 1 + payload.length() > 16 {
                          None
                        } else {
                          Some([@types.ValueType::I32] + payload)
                        }
                      None => None
                    }
                  @component.TypeDef::Result(ok, err) => {
                    let ok_flat = match ok {
                      None => []
                      Some(v) =>
                        match scalar_flat_valtype(v) {
                          Some(ts) => ts
                          None => return None
                        }
                    }
                    let err_flat = match err {
                      None => []
                      Some(v) =>
                        match scalar_flat_valtype(v) {
                          Some(ts) => ts
                          None => return None
                        }
                    }
                    let mut max_len = ok_flat.length()
                    if err_flat.length() > max_len {
                      max_len = err_flat.length()
                    }
                    let joined : Array[@types.ValueType] = []
                    for i in 0..<max_len {
                      let mut cur : @types.ValueType? = None
                      if i < ok_flat.length() {
                        cur = Some(ok_flat[i])
                      }
                      if i < err_flat.length() {
                        cur = match cur {
                          None => Some(err_flat[i])
                          Some(prev) => Some(join_flat(prev, err_flat[i]))
                        }
                      }
                      match cur {
                        None => ()
                        Some(t) => joined.push(t)
                      }
                    }
                    if 1 + joined.length() > 16 {
                      None
                    } else {
                      Some([@types.ValueType::I32] + joined)
                    }
                  }
                  @component.TypeDef::Flags(labels) =>
                    if labels.length() <= 32 {
                      Some([@types.ValueType::I32])
                    } else if labels.length() <= 64 {
                      Some([@types.ValueType::I64])
                    } else {
                      None
                    }
                  @component.TypeDef::Enum(_labels) =>
                    Some([@types.ValueType::I32])
                  @component.TypeDef::Own(_) | @component.TypeDef::Borrow(_) =>
                    Some([@types.ValueType::I32])
                  @component.TypeDef::ResourceType(_, _, _, _) =>
                    Some([@types.ValueType::I32])
                  @component.TypeDef::Future(_)
                  | @component.TypeDef::Stream(_) =>
                    Some([@types.ValueType::I32])
                  // Lists/strings/resources with non-scalar reps require memory.
                  _ => None
                }
            }
            visiting.remove(idx) |> ignore
            res
          }
        }
      }
    }
  }

  scalar_flat_valtype(ty)
}

///|
fn core_functype_for_component_functype(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> @types.FuncType? {
  let params : Array[@types.ValueType] = []
  for p in ft.params {
    match core_valtypes_for_component_valtype(p.ty, type_table) {
      Some(ts) =>
        for t in ts {
          params.push(t)
          if params.length() > 16 {
            // Indirect parameters: canonical ABI requires memory.
            return None
          }
        }
      None => return None
    }
  }
  let results : Array[@types.ValueType] = []
  match ft.result {
    None => ()
    Some(r) =>
      match core_valtypes_for_component_valtype(r, type_table) {
        Some(ts) =>
          for t in ts {
            results.push(t)
          }
        None => return None
      }
  }
  // Indirect/multi-value results go through memory (retptr), not direct core results.
  if results.length() > 1 {
    return None
  }
  Some({ params, results })
}

///|
fn validate_canon(
  c : @component.Canon,
  type_table : Array[@component.TypeDef?],
  local_resource_types : Array[Bool],
  type_bound : Int,
  core_memory_types : Array[@types.MemoryType?],
  core_func_types : Array[@types.FuncType?],
  func_types : Array[@component.FuncType?],
) -> Unit raise ComponentValidationError {
  match c {
    Lift(core_func_idx, opts, tyidx) => {
      validate_canon_opts(opts)
      match canon_memory_idx(opts) {
        Some(mem_idx) =>
          if mem_idx < 0 || mem_idx >= core_memory_types.length() {
            raise InvalidCoreMemoryIndex(mem_idx)
          } else {
            match core_memory_types[mem_idx] {
              Some(mt) =>
                if mt.is_memory64 {
                  raise CanonMemoryNot32Bit(mem_idx)
                }
              None => ()
            }
          }
        None => ()
      }
      match canon_realloc_idx(opts) {
        Some(idx) =>
          if idx < 0 || idx >= core_func_types.length() {
            raise InvalidCoreFuncIndex(idx)
          }
        None => ()
      }
      match canon_post_return_idx(opts) {
        Some(idx) =>
          if idx < 0 || idx >= core_func_types.length() {
            raise InvalidCoreFuncIndex(idx)
          }
        None => ()
      }
      if core_func_idx < 0 || core_func_idx >= core_func_types.length() {
        raise InvalidCoreFuncIndex(core_func_idx)
      }
      check_typeidx(tyidx, type_bound)
      let td = type_table[tyidx]
      match td {
        Some(@component.TypeDef::FuncType(ft)) => {
          match canon_realloc_idx(opts) {
            Some(idx) =>
              match core_func_types[idx] {
                Some(core_ft) => {
                  let expected : @types.FuncType = {
                    params: [
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                    ],
                    results: [@types.ValueType::I32],
                  }
                  if core_ft != expected {
                    raise CanonCoreFuncTypeMismatch(
                      "canonical option `realloc` uses a core function with an incorrect signature",
                    )
                  }
                }
                None => ()
              }
            None => ()
          }
          match canon_post_return_idx(opts) {
            Some(idx) =>
              match (core_func_types[core_func_idx], core_func_types[idx]) {
                (Some(lifted_ft), Some(post_ft)) => {
                  let expected : @types.FuncType = {
                    params: lifted_ft.results,
                    results: [],
                  }
                  if post_ft != expected {
                    raise CanonCoreFuncTypeMismatch(
                      "canonical option `post-return` uses a core function with an incorrect signature",
                    )
                  }
                }
                _ => ()
              }
            None => ()
          }
          if functype_needs_memory(ft, type_table) {
            if !canon_has_memory(opts) {
              raise MissingCanonOption("memory")
            }
          }
          if functype_needs_realloc_for_lift(ft, type_table) {
            if !canon_has_realloc(opts) {
              raise MissingCanonOption("realloc")
            }
          }
          // Async-lifted functions use a callback/event-code ABI and do not
          // match the direct lowering signature.
          if !canon_has_async(opts) {
            match
              (
                core_func_types[core_func_idx],
                core_functype_for_component_functype(ft, type_table),
              ) {
              (Some(core_ft), Some(expected_core_ft)) =>
                if core_ft != expected_core_ft {
                  raise CanonCoreFuncTypeMismatch(
                    "canon lift core signature mismatch",
                  )
                }
              _ => ()
            }
          }
        }
        None => ()
        _ => raise CanonExpectedFuncType(tyidx)
      }
    }
    Lower(func_idx, opts) => {
      validate_canon_opts(opts)
      if canon_has_post_return(opts) {
        raise CanonOptionNotAllowed("post-return")
      }
      match canon_memory_idx(opts) {
        Some(mem_idx) =>
          if mem_idx < 0 || mem_idx >= core_memory_types.length() {
            raise InvalidCoreMemoryIndex(mem_idx)
          } else {
            match core_memory_types[mem_idx] {
              Some(mt) =>
                if mt.is_memory64 {
                  raise CanonMemoryNot32Bit(mem_idx)
                }
              None => ()
            }
          }
        None => ()
      }
      match canon_realloc_idx(opts) {
        Some(idx) =>
          if idx < 0 || idx >= core_func_types.length() {
            raise InvalidCoreFuncIndex(idx)
          }
        None => ()
      }
      if func_idx < 0 || func_idx >= func_types.length() {
        raise InvalidFuncIndex(func_idx)
      }
      match func_types[func_idx] {
        Some(ft) => {
          match canon_realloc_idx(opts) {
            Some(idx) =>
              match core_func_types[idx] {
                Some(core_ft) => {
                  let expected : @types.FuncType = {
                    params: [
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                    ],
                    results: [@types.ValueType::I32],
                  }
                  if core_ft != expected {
                    raise CanonCoreFuncTypeMismatch(
                      "canonical option `realloc` uses a core function with an incorrect signature",
                    )
                  }
                }
                None => ()
              }
            None => ()
          }
          if functype_needs_memory(ft, type_table) && !canon_has_memory(opts) {
            raise MissingCanonOption("memory")
          }
          if functype_needs_realloc_for_lower(ft, type_table) &&
            !canon_has_realloc(opts) {
            raise MissingCanonOption("realloc")
          }
        }
        None => ()
      }
    }
    ResourceNew(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      // `resource.new` requires a resource type defined in this concrete component.
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 ||
        tyidx >= local_resource_types.length() ||
        !local_resource_types[tyidx] {
        raise SectionParseError(8, "not a local resource")
      }
      match type_table[tyidx] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        _ => raise SectionParseError(8, "not a resource type")
      }
    }
    ResourceRep(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 ||
        tyidx >= local_resource_types.length() ||
        !local_resource_types[tyidx] {
        raise SectionParseError(8, "not a local resource")
      }
      match type_table[tyidx] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        _ => raise SectionParseError(8, "not a resource type")
      }
    }
    ResourceDrop(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      // `resource.drop` is allowed for both local resource types and imported
      // `(sub resource)` types (which we currently model as None).
      match type_table[tyidx] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        None => ()
        Some(_) => raise SectionParseError(8, "not a resource type")
      }
    }
    _ => ()
  }
}

///|
fn valtype_refers_to_resource(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    @component.ValType::Prim(_) => false
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        false
      } else if visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, 1)
        let any = match type_table[idx] {
          None => false
          Some(td) => typedef_refers_to_resource(td, type_table, visiting)
        }
        visiting.remove(idx) |> ignore
        any
      }
  }
}

///|
fn externdesc_refers_to_resource(
  desc : @component.ExternDesc,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match desc {
    @component.ExternDesc::Type(b) =>
      match b {
        @component.TypeBound::Eq(idx) =>
          valtype_refers_to_resource(
            @component.ValType::TypeIdx(idx),
            type_table,
            visiting,
          )
        @component.TypeBound::SubResource => true
      }
    @component.ExternDesc::FuncType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(@component.TypeDef::FuncType(ft)) => {
            let mut any = false
            for p in ft.params {
              if valtype_refers_to_resource(p.ty, type_table, visiting) {
                any = true
                break
              }
            }
            if !any {
              match ft.result {
                None => ()
                Some(r) =>
                  if valtype_refers_to_resource(r, type_table, visiting) {
                    any = true
                  }
              }
            }
            any
          }
          _ => false
        }
      }
    @component.ExternDesc::InstanceType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(@component.TypeDef::InstanceType(decls)) => {
            let mut any = false
            for d in decls {
              match d {
                @component.InstanceDecl::Type(td) =>
                  if typedef_refers_to_resource(td, type_table, visiting) {
                    any = true
                    break
                  }
                @component.InstanceDecl::Export(_name, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                _ => ()
              }
            }
            any
          }
          _ => false
        }
      }
    @component.ExternDesc::ComponentType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(@component.TypeDef::ComponentType(decls)) => {
            let mut any = false
            for d in decls {
              match d {
                @component.ComponentDecl::Type(td) =>
                  if typedef_refers_to_resource(td, type_table, visiting) {
                    any = true
                    break
                  }
                @component.ComponentDecl::Import(_name, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                @component.ComponentDecl::Export(_name, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                _ => ()
              }
            }
            any
          }
          _ => false
        }
      }
    _ => false
  }
}

///|
fn typedef_refers_to_resource(
  td : @component.TypeDef,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match td {
    @component.TypeDef::ResourceType(_, _, _, _) => true
    @component.TypeDef::Own(_) | @component.TypeDef::Borrow(_) => true
    @component.TypeDef::DefValType(_) => false
    @component.TypeDef::Tuple(tys) => {
      let mut any = false
      for t in tys {
        if valtype_refers_to_resource(t, type_table, visiting) {
          any = true
          break
        }
      }
      any
    }
    @component.TypeDef::Record(fields) => {
      let mut any = false
      for f in fields {
        if valtype_refers_to_resource(f.ty, type_table, visiting) {
          any = true
          break
        }
      }
      any
    }
    @component.TypeDef::Variant(cases) => {
      let mut any = false
      for c in cases {
        match c.ty {
          None => ()
          Some(t) =>
            if valtype_refers_to_resource(t, type_table, visiting) {
              any = true
              break
            }
        }
      }
      any
    }
    @component.TypeDef::Option(v) =>
      valtype_refers_to_resource(v, type_table, visiting)
    @component.TypeDef::Result(ok, err) => {
      let ok_any = match ok {
        None => false
        Some(v) => valtype_refers_to_resource(v, type_table, visiting)
      }
      let err_any = match err {
        None => false
        Some(v) => valtype_refers_to_resource(v, type_table, visiting)
      }
      ok_any || err_any
    }
    @component.TypeDef::List(v) =>
      valtype_refers_to_resource(v, type_table, visiting)
    @component.TypeDef::Stream(v) | @component.TypeDef::Future(v) =>
      match v {
        None => false
        Some(inner) => valtype_refers_to_resource(inner, type_table, visiting)
      }
    @component.TypeDef::FuncType(ft) => {
      let mut any = false
      for p in ft.params {
        if valtype_refers_to_resource(p.ty, type_table, visiting) {
          any = true
          break
        }
      }
      if !any {
        match ft.result {
          None => ()
          Some(r) =>
            if valtype_refers_to_resource(r, type_table, visiting) {
              any = true
            }
        }
      }
      any
    }
    @component.TypeDef::ComponentType(decls) => {
      let mut any = false
      for d in decls {
        match d {
          @component.ComponentDecl::Type(td2) =>
            if typedef_refers_to_resource(td2, type_table, visiting) {
              any = true
              break
            }
          @component.ComponentDecl::Import(_name, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          @component.ComponentDecl::Export(_name, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          _ => ()
        }
      }
      any
    }
    @component.TypeDef::InstanceType(decls) => {
      let mut any = false
      for d in decls {
        match d {
          @component.InstanceDecl::Type(td2) =>
            if typedef_refers_to_resource(td2, type_table, visiting) {
              any = true
              break
            }
          @component.InstanceDecl::Export(_name, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          _ => ()
        }
      }
      any
    }
    _ => false
  }
}

///|
/// Compute a conservative "effective type size" for component/instance types.
///
/// This is a lightweight check used to reject pathological type graphs that
/// explode when expanded (wasm-tools' `very-nested.wast`). The component-spec
/// limit is 100_000.
fn clamp_type_size(size : Int) -> Int {
  if size > 100000 {
    100001
  } else {
    size
  }
}

///|
fn add_type_size(acc : Int, delta : Int) -> Int {
  if acc > 100000 {
    return 100001
  }
  let d = clamp_type_size(delta)
  let sum = acc + d
  clamp_type_size(sum)
}

///|
fn local_type_size_of(idx : Int, local_sizes : Array[Int]) -> Int {
  if idx < 0 || idx >= local_sizes.length() {
    return 1
  }
  local_sizes[idx]
}

///|
fn externdesc_type_size(
  desc : @component.ExternDesc,
  local_sizes : Array[Int],
) -> Int {
  match desc {
    @component.ExternDesc::ComponentType(tyidx) =>
      local_type_size_of(tyidx, local_sizes)
    @component.ExternDesc::InstanceType(tyidx) =>
      local_type_size_of(tyidx, local_sizes)
    @component.ExternDesc::FuncType(_) => 1
    @component.ExternDesc::CoreModuleType(_) => 1
    @component.ExternDesc::Type(_) => 1
    @component.ExternDesc::Value(_) => 1
  }
}

///|
fn effective_typedef_size(
  td : @component.TypeDef,
  outer_sizes : Array[Int],
) -> Int {
  fn valtype_size(ty : @component.ValType) -> Int {
    match ty {
      @component.ValType::Prim(_) => 1
      @component.ValType::TypeIdx(idx) => local_type_size_of(idx, outer_sizes)
    }
  }

  match td {
    @component.TypeDef::ComponentType(decls) => {
      let local_sizes : Array[Int] = []
      let mut total = 1
      for d in decls {
        match d {
          @component.ComponentDecl::Type(t) =>
            local_sizes.push(effective_typedef_size(t, outer_sizes))
          @component.ComponentDecl::AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let s = if count == 1 && idx >= 0 && idx < outer_sizes.length() {
                outer_sizes[idx]
              } else {
                1
              }
              local_sizes.push(s)
            } else {
              ()
            }
          @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              local_sizes.push(1)
            } else {
              ()
            }
          @component.ComponentDecl::Import(_name, desc)
          | @component.ComponentDecl::Export(_name, desc) => {
            total = add_type_size(
              total,
              externdesc_type_size(desc, local_sizes),
            )
            // Importing/exporting a type introduces a fresh local type index.
            if desc is @component.ExternDesc::Type(_) {
              local_sizes.push(1)
            }
          }
          @component.ComponentDecl::CoreType(_) => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::InstanceType(decls) => {
      let local_sizes : Array[Int] = []
      let mut total = 1
      for d in decls {
        match d {
          @component.InstanceDecl::Type(t) =>
            local_sizes.push(effective_typedef_size(t, outer_sizes))
          @component.InstanceDecl::AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let s = if count == 1 && idx >= 0 && idx < outer_sizes.length() {
                outer_sizes[idx]
              } else {
                1
              }
              local_sizes.push(s)
            } else {
              ()
            }
          @component.InstanceDecl::AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              local_sizes.push(1)
            } else {
              ()
            }
          @component.InstanceDecl::Export(_name, desc) => {
            total = add_type_size(
              total,
              externdesc_type_size(desc, local_sizes),
            )
            if desc is @component.ExternDesc::Type(_) {
              local_sizes.push(1)
            }
          }
          @component.InstanceDecl::CoreType(_) => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::DefValType(_) => 1
    @component.TypeDef::FuncType(ft) => {
      let mut total = 1
      for p in ft.params {
        total = add_type_size(total, valtype_size(p.ty))
        if total > 100000 {
          return 100001
        }
      }
      match ft.result {
        Some(r) => add_type_size(total, valtype_size(r))
        None => total
      }
    }
    @component.TypeDef::Tuple(tys) => {
      let mut total = 1
      for t in tys {
        total = add_type_size(total, valtype_size(t))
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::Record(fields) => {
      let mut total = 1
      for f in fields {
        total = add_type_size(total, valtype_size(f.ty))
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::Variant(cases) => {
      let mut total = 1
      for c in cases {
        match c.ty {
          Some(t) => total = add_type_size(total, valtype_size(t))
          None => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::Option(v) => add_type_size(1, valtype_size(v))
    @component.TypeDef::Result(ok, err) => {
      let mut total = 1
      match ok {
        Some(v) => total = add_type_size(total, valtype_size(v))
        None => ()
      }
      match err {
        Some(v) => total = add_type_size(total, valtype_size(v))
        None => ()
      }
      total
    }
    @component.TypeDef::List(v) => add_type_size(1, valtype_size(v))
    @component.TypeDef::Flags(labels) => add_type_size(1, labels.length())
    @component.TypeDef::Enum(labels) => add_type_size(1, labels.length())
    _ => 1
  }
}

///|
/// Compute a conservative nesting depth for defined types.
///
/// The component-spec suite expects a rejection for overly deep nesting even
/// when effective size is small (e.g. 101 nested `list` types).
fn valtype_nesting_depth(
  ty : @component.ValType,
  type_depths : Array[Int],
) -> Int {
  match ty {
    @component.ValType::Prim(_) => 0
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_depths.length() {
        0
      } else {
        type_depths[idx]
      }
  }
}

///|
fn effective_typedef_depth(
  td : @component.TypeDef,
  type_depths : Array[Int],
) -> Int {
  match td {
    // Base types contribute depth=1 so that chains like 101 nested `list`
    // typedefs trip the component-spec limit.
    @component.TypeDef::DefValType(_) => 1
    @component.TypeDef::FuncType(_) => 1
    @component.TypeDef::List(v) => 1 + valtype_nesting_depth(v, type_depths)
    @component.TypeDef::Option(v) => 1 + valtype_nesting_depth(v, type_depths)
    @component.TypeDef::Result(ok, err) => {
      let mut max_child = 0
      match ok {
        Some(v) => max_child = valtype_nesting_depth(v, type_depths)
        None => ()
      }
      match err {
        Some(v) => {
          let d = valtype_nesting_depth(v, type_depths)
          if d > max_child {
            max_child = d
          }
        }
        None => ()
      }
      1 + max_child
    }
    @component.TypeDef::Tuple(tys) => {
      let mut max_child = 0
      for v in tys {
        let d = valtype_nesting_depth(v, type_depths)
        if d > max_child {
          max_child = d
        }
      }
      1 + max_child
    }
    @component.TypeDef::Record(fields) => {
      let mut max_child = 0
      for f in fields {
        let d = valtype_nesting_depth(f.ty, type_depths)
        if d > max_child {
          max_child = d
        }
      }
      1 + max_child
    }
    @component.TypeDef::Variant(cases) => {
      let mut max_child = 0
      for c in cases {
        match c.ty {
          Some(v) => {
            let d = valtype_nesting_depth(v, type_depths)
            if d > max_child {
              max_child = d
            }
          }
          None => ()
        }
      }
      1 + max_child
    }
    // Types that are represented scalarly or don't contribute additional depth
    // beyond the base `1`.
    _ => 1
  }
}

///|
priv struct ValidatedComponentInfo {
  size : Int
  import_sorts : Map[String, @component.Sort]
  import_instance_sigs : Map[String, InstanceSig]
  import_func_sigs : Map[String, FuncSigShape]
  import_instance_resource_exports : Map[String, Map[String, Int]]
  import_type_bounds : Map[String, @component.TypeBound]
  import_type_sigs : Map[String, TypeSig]
  import_core_module_exports : Map[String, Map[String, Int]]
  import_core_module_import_sigs : Map[String, Map[String, CoreExternType]]
  export_sorts : Map[String, @component.Sort]
  export_instance_sigs : Map[String, InstanceSig]
  export_instance_type_sigs : Map[String, Map[String, TypeSig]]
  export_instance_func_sigs : Map[String, Map[String, FuncSigShape]]
  export_type_sigs : Map[String, TypeSig]
  export_func_sigs : Map[String, FuncSigShape]
}

///|
/// Validate a parsed component (partial).
fn validate_component_inner(
  component : @component.Component,
  is_root : Bool,
  cfg : ComponentValidationConfig,
  depth : Int,
  type_outers : Array[Array[@component.TypeDef?]],
  core_type_bound_outers : Array[Int],
  component_size_outers : Array[Array[Int]],
) -> ValidatedComponentInfo raise ComponentValidationError {
  let counts = Counts::new()
  let type_table : Array[@component.TypeDef?] = []
  // Track which type indices correspond to resource types defined in the
  // current concrete component (as opposed to imported/aliased resource types).
  let local_resource_types : Array[Bool] = []
  // Nominal identity ids for resource types (both defined and imported via `sub resource`).
  // These are local to this validation run, but used to detect mismatches across instantiation.
  let resource_ids : Array[Int?] = []
  let mut next_resource_id = 0
  let type_sizes : Array[Int] = []
  let type_depths : Array[Int] = []
  // Approximate export-signature size (used for wasm-tools' very-nested.wast).
  let component_sizes : Array[Int] = []
  let instance_sizes : Array[Int] = []
  let mut export_size = 1
  // Type indices that have names in the current interface namespace (type imports/exports).
  let named_types : Map[Int, Int] = {}
  // Type indices named by imports only (used to validate imports even if the
  // component's sections are reordered).
  let import_named_types : Map[Int, Int] = {}
  let core_type_exports : Array[Map[String, Int]?] = []
  let core_type_module_imports : Array[Array[CoreModuleTypeImport]?] = []
  let core_type_module_export_types : Array[Map[String, CoreExternType]?] = []
  let core_module_exports : Array[Map[String, Int]?] = []
  // Align core module definitions to the core-module index space (imports get None).
  let core_module_defs : Array[@types.Module?] = []
  let core_func_types : Array[@types.FuncType?] = []
  let core_module_export_types : Array[Map[String, CoreExternType]?] = []
  let core_module_type_imports : Array[Array[CoreModuleTypeImport]?] = []
  let core_instance_exports : Array[Map[String, Int]?] = []
  let core_instance_export_types : Array[Map[String, CoreExternType]?] = []
  let core_memory_types : Array[@types.MemoryType?] = []
  let component_import_sorts : Array[Map[String, @component.Sort]?] = []
  let component_import_instance_sigs : Array[Map[String, InstanceSig]?] = []
  let component_import_func_sigs : Array[Map[String, FuncSigShape]?] = []
  let component_import_instance_resource_exports : Array[
    Map[String, Map[String, Int]]?,
  ] = []
  let component_import_core_module_exports : Array[
    Map[String, Map[String, Int]]?,
  ] = []
  let component_import_core_module_import_sigs : Array[
    Map[String, Map[String, CoreExternType]]?,
  ] = []
  let component_import_type_bounds : Array[Map[String, @component.TypeBound]?] = []
  let component_import_type_sigs : Array[Map[String, TypeSig]?] = []
  let component_export_sorts : Array[Map[String, @component.Sort]?] = []
  let component_export_instance_sigs : Array[Map[String, InstanceSig]?] = []
  let component_export_instance_type_sigs : Array[
    Map[String, Map[String, TypeSig]]?,
  ] = []
  let component_export_instance_func_sigs : Array[
    Map[String, Map[String, FuncSigShape]]?,
  ] = []
  let component_export_type_sigs : Array[Map[String, TypeSig]?] = []
  let component_export_func_sigs : Array[Map[String, FuncSigShape]?] = []
  let instance_sigs : Array[InstanceSig?] = []
  // Instances that are part of this component's interface namespace (imports
  // plus export-introduced instance aliases).
  let interface_instance_idxs : Map[Int, Int] = {}
  let instance_export_type_idxs : Array[Array[Int]?] = []
  let instance_export_func_idxs : Array[Array[Int]?] = []
  let instance_export_type_map : Array[Map[String, ExportedTypeInfo]?] = []
  let instance_export_type_sigs : Array[Map[String, TypeSig]?] = []
  let instance_export_func_sigs : Array[Map[String, FuncSigShape]?] = []
  let instance_nested_instance_type_sigs : Array[
    Map[String, Map[String, TypeSig]]?,
  ] = []
  let instance_nested_instance_func_sigs : Array[
    Map[String, Map[String, FuncSigShape]]?,
  ] = []
  let func_types : Array[@component.FuncType?] = []
  let func_sig_shapes : Array[FuncSigShape?] = []
  let mut imported_funcs = 0
  let seen_import_names : Map[String, String] = {}
  let seen_export_names : Map[String, String] = {}
  // Resource-type names in the WIT interface namespace.
  let import_resource_names : Map[String, Int] = {}
  let export_resource_names : Map[String, Int] = {}

  // Signature tables for this component (returned to parent for instantiation validation).
  let my_import_sorts : Map[String, @component.Sort] = {}
  let my_import_instance_sigs : Map[String, InstanceSig] = {}
  let my_import_func_sigs : Map[String, FuncSigShape] = {}
  let my_import_instance_resource_exports : Map[String, Map[String, Int]] = {}
  let my_import_type_bounds : Map[String, @component.TypeBound] = {}
  let my_import_type_sigs : Map[String, TypeSig] = {}
  let my_export_sorts : Map[String, @component.Sort] = {}
  let my_export_instance_sigs : Map[String, InstanceSig] = {}
  let my_export_instance_type_sigs : Map[String, Map[String, TypeSig]] = {}
  let my_export_instance_func_sigs : Map[String, Map[String, FuncSigShape]] = {}
  let my_export_type_sigs : Map[String, TypeSig] = {}
  let my_export_func_sigs : Map[String, FuncSigShape] = {}
  for s in component.binary.sections {
    match s.id {
      // Core module/instance/type sections each declare a single core item.
      1 => {
        // Validate embedded core modules using the existing core validator.
        let core_mod = @parser.parse_module(s.payload) catch {
          e => raise CoreModuleError("parse core module: \{e}")
        }
        // wasm-tools expects duplicate import names in core modules to be invalid.
        let seen_imports : Map[String, Int] = {}
        for imp in core_mod.imports {
          let key = "\{imp.mod_name}:\{imp.name}"
          if seen_imports.get(key) is Some(_) {
            raise CoreModuleError("duplicate import name `\{key}`")
          }
          seen_imports.set(key, 1)
        }
        validate_module(core_mod) catch {
          e => raise CoreModuleError("validate core module: \{e}")
        }
        let exports : Map[String, Int] = {}
        let export_types : Map[String, CoreExternType] = {}
        for ex in core_mod.exports {
          match ex.desc {
            @types.ExportDesc::Func(_) => exports.set(ex.name, 0x00)
            @types.ExportDesc::Table(_) => exports.set(ex.name, 0x01)
            @types.ExportDesc::Memory(_) => exports.set(ex.name, 0x02)
            @types.ExportDesc::Global(_) => exports.set(ex.name, 0x03)
            @types.ExportDesc::Tag(_) => exports.set(ex.name, 0x04)
          }
          match core_export_type_of_module(core_mod, ex) {
            Some(t) => export_types.set(ex.name, t)
            None => ()
          }
        }
        core_module_exports.push(Some(exports))
        core_module_export_types.push(Some(export_types))
        core_module_type_imports.push(None)
        core_module_defs.push(Some(core_mod))
        counts.core_module += 1
      }
      2 => {
        let core_instances = @component.parse_core_instance_section(s.payload) catch {
          e => raise SectionParseError(2, "\{e}")
        }
        for inst in core_instances {
          let mut export_map : Map[String, Int]? = None
          let mut export_types : Map[String, CoreExternType]? = None
          match inst.expr {
            @component.CoreInstanceExpr::Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= counts.core_module {
                raise InvalidCoreModuleIndex(module_idx)
              }
              if module_idx >= 0 && module_idx < core_module_exports.length() {
                export_map = core_module_exports[module_idx]
              }
              if module_idx >= 0 &&
                module_idx < core_module_export_types.length() {
                export_types = core_module_export_types[module_idx]
              }
              // Validate that instantiation args satisfy the core module's
              // imports when we have enough type information (either a full
              // core module body, or a core module type signature).
              let providers : Map[String, Int] = {}
              let seen_arg_names : Map[String, Int] = {}
              for a in args {
                check_sortidx(a.sortidx, counts, type_table.length())
                if seen_arg_names.get(a.name) is Some(_) {
                  raise CoreModuleError(
                    "duplicate module instantiation argument named `\{a.name}`",
                  )
                }
                seen_arg_names.set(a.name, 1)
                match a.sortidx.sort {
                  @component.Sort::Core(0x12) =>
                    providers.set(a.name, a.sortidx.idx)
                  _ => ()
                }
              }
              let mod_def = if module_idx >= 0 &&
                module_idx < core_module_defs.length() {
                core_module_defs[module_idx]
              } else {
                None
              }
              match mod_def {
                Some(mod_) =>
                  for imp in mod_.imports {
                    match providers.get(imp.mod_name) {
                      None =>
                        raise CoreModuleError(
                          "module import `\{imp.mod_name}::\{imp.name}` not defined",
                        )
                      Some(provider_idx) => {
                        if provider_idx < 0 ||
                          provider_idx >= core_instance_export_types.length() {
                          raise InvalidCoreInstanceIndex(provider_idx)
                        }
                        let expected = core_import_type_of_module(
                          mod_,
                          imp.desc,
                        )
                        match expected {
                          None => ()
                          Some(exp_ty) => {
                            let expected_kind = core_kind_of_extern_type(exp_ty)
                            // Check presence/kind first (even if we don't have full type info).
                            if provider_idx < 0 ||
                              provider_idx >= core_instance_exports.length() {
                              raise InvalidCoreInstanceIndex(provider_idx)
                            }
                            match core_instance_exports[provider_idx] {
                              Some(kinds) =>
                                match kinds.get(imp.name) {
                                  None =>
                                    raise CoreModuleError(
                                      "module import `\{imp.mod_name}::\{imp.name}` not defined",
                                    )
                                  Some(actual_kind) =>
                                    if actual_kind != expected_kind {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                }
                              None => ()
                            }
                            // If we also know full types, enforce type compatibility.
                            match core_instance_export_types[provider_idx] {
                              Some(map) =>
                                match map.get(imp.name) {
                                  Some(prov_ty) =>
                                    if !core_import_compatible(exp_ty, prov_ty) {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                  None => ()
                                }
                              None => ()
                            }
                          }
                        }
                      }
                    }
                  }
                None =>
                  match
                    (if module_idx >= 0 &&
                      module_idx < core_module_type_imports.length() {
                      core_module_type_imports[module_idx]
                    } else {
                      None
                    }) {
                    Some(sigs) =>
                      for imp in sigs {
                        match providers.get(imp.mod_name) {
                          None =>
                            raise CoreModuleError(
                              "module import `\{imp.mod_name}::\{imp.name}` not defined",
                            )
                          Some(provider_idx) => {
                            if provider_idx < 0 ||
                              provider_idx >=
                              core_instance_export_types.length() {
                              raise InvalidCoreInstanceIndex(provider_idx)
                            }
                            let expected_kind = core_kind_of_extern_type(imp.ty)
                            if provider_idx < 0 ||
                              provider_idx >= core_instance_exports.length() {
                              raise InvalidCoreInstanceIndex(provider_idx)
                            }
                            match core_instance_exports[provider_idx] {
                              Some(kinds) =>
                                match kinds.get(imp.name) {
                                  None =>
                                    raise CoreModuleError(
                                      "module import `\{imp.mod_name}::\{imp.name}` not defined",
                                    )
                                  Some(actual_kind) =>
                                    if actual_kind != expected_kind {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                }
                              None => ()
                            }
                            match core_instance_export_types[provider_idx] {
                              Some(map) =>
                                match map.get(imp.name) {
                                  Some(prov_ty) =>
                                    if !core_import_compatible(imp.ty, prov_ty) {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                  None => ()
                                }
                              None => ()
                            }
                          }
                        }
                      }
                    None => ()
                  }
              }
            }
            @component.CoreInstanceExpr::InlineExports(inline_exports) => {
              let map : Map[String, Int] = {}
              for ex in inline_exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
                if map.get(ex.name) is Some(_) {
                  raise DuplicateExportName(ex.name)
                }
                match ex.sortidx.sort {
                  @component.Sort::Core(core_sort) =>
                    map.set(ex.name, core_sort)
                  _ => ()
                }
              }
              export_map = Some(map)
            }
          }
          core_instance_exports.push(export_map)
          core_instance_export_types.push(export_types)
          counts.core_instance += 1
        }
      }
      3 => {
        // Validate core module type signatures, including `alias outer` bounds.
        // The `outer` depth counts enclosing component scopes.
        let max_outer_depth = depth + 1
        let base_core_type_bound = counts.core_type
        let exports = parse_core_type_section(
          s.payload,
          max_outer_depth,
          base_core_type_bound,
          core_type_bound_outers,
        )
        let (module_imports, module_export_types) = parse_core_type_section_module_sigs(
          s.payload,
          max_outer_depth,
          base_core_type_bound,
          core_type_bound_outers,
        )
        for e in exports {
          core_type_exports.push(e)
        }
        for m in module_imports {
          core_type_module_imports.push(m)
        }
        for t in module_export_types {
          core_type_module_export_types.push(t)
        }
        counts.core_type += exports.length()
      }
      4 => {
        // Nested component payloads are also component binaries.
        let nested = @component.parse_component(s.payload) catch {
          e => raise SectionParseError(4, "parse nested component: \{e}")
        }
        let nested_info = validate_component_inner(
          nested,
          false,
          cfg,
          depth + 1,
          [type_table] + type_outers,
          [counts.core_type] + core_type_bound_outers,
          [component_sizes] + component_size_outers,
        )
        component_import_sorts.push(Some(nested_info.import_sorts))
        component_import_instance_sigs.push(
          Some(nested_info.import_instance_sigs),
        )
        component_import_func_sigs.push(Some(nested_info.import_func_sigs))
        component_import_instance_resource_exports.push(
          Some(nested_info.import_instance_resource_exports),
        )
        component_import_core_module_exports.push(
          Some(nested_info.import_core_module_exports),
        )
        component_import_core_module_import_sigs.push(
          Some(nested_info.import_core_module_import_sigs),
        )
        component_import_type_bounds.push(Some(nested_info.import_type_bounds))
        component_import_type_sigs.push(Some(nested_info.import_type_sigs))
        component_export_sorts.push(Some(nested_info.export_sorts))
        component_export_instance_sigs.push(
          Some(nested_info.export_instance_sigs),
        )
        component_export_instance_type_sigs.push(
          Some(nested_info.export_instance_type_sigs),
        )
        component_export_instance_func_sigs.push(
          Some(nested_info.export_instance_func_sigs),
        )
        component_export_type_sigs.push(Some(nested_info.export_type_sigs))
        component_export_func_sigs.push(Some(nested_info.export_func_sigs))
        component_sizes.push(nested_info.size)
        // Nested component definitions contribute to the overall effective
        // size of the component graph (wasm-tools/very-nested.wast).
        export_size = add_type_size(export_size, nested_info.size)
        counts.component += 1
      }
      7 => {
        // Definitions extend the type index space.
        let defs = @component.parse_type_section(s.payload) catch {
          e => raise SectionParseError(7, "\{e}")
        }
        for d in defs {
          // This is still a subset: we only allow referencing earlier types.
          validate_typedef(
            d,
            cfg,
            [type_table] + type_outers,
            [core_type_exports],
            true,
          )
          // Resource types refer to the core-func index space for their dtor.
          // Validate bounds/signature here where we have access to the current
          // core-func types.
          match d {
            @component.TypeDef::ResourceType(_, _rep, dtor_idx, _kind) =>
              match dtor_idx {
                Some(idx) =>
                  if idx < 0 || idx >= counts.core_func {
                    raise SectionParseError(7, "function index out of bounds")
                  } else {
                    match core_func_types.get(idx) {
                      Some(Some(ft)) => {
                        let expected : @types.FuncType = {
                          params: [@types.ValueType::I32],
                          results: [],
                        }
                        if ft != expected {
                          raise SectionParseError(
                            7, "wrong signature for a destructor",
                          )
                        }
                      }
                      _ => ()
                    }
                  }
                None => ()
              }
            _ => ()
          }
          let size = effective_typedef_size(d, type_sizes)
          if size > 100000 {
            raise SectionParseError(7, "effective type size exceeds the limit")
          }
          let depth = effective_typedef_depth(d, type_depths)
          if depth > 100 {
            raise SectionParseError(7, "type nesting is too deep")
          }
          type_table.push(Some(d))
          local_resource_types.push(
            d is @component.TypeDef::ResourceType(_, _, _, _),
          )
          match d {
            @component.TypeDef::ResourceType(_, _, _, _) => {
              resource_ids.push(Some(next_resource_id))
              next_resource_id += 1
            }
            _ => resource_ids.push(None)
          }
          type_sizes.push(size)
          type_depths.push(depth)
        }
      }
      10 => {
        let imports = @component.parse_import_section(s.payload) catch {
          e => raise SectionParseError(10, "\{e}")
        }
        for i in imports {
          validate_import_name(i.name, cfg)
          if is_root && i.desc is @component.ExternDesc::ComponentType(_) {
            raise SectionParseError(
              10, "root-level component imports are not supported",
            )
          }
          match importname_to_string(i.name) {
            Some(name) => {
              let key = if cfg.wit_names {
                wit_conflict_key(name)
              } else {
                name
              }
              match seen_import_names.get(key) {
                Some(prev) =>
                  if prev == name {
                    raise DuplicateImportName(name)
                  } else {
                    raise SectionParseError(
                      10,
                      "import name `\{name}` conflicts with previous name `\{prev}`",
                    )
                  }
                None => seen_import_names.set(key, name)
              }
            }
            None => ()
          }
          match importname_to_string(i.name) {
            Some(name) => my_import_sorts.set(name, sort_of_externdesc(i.desc))
            None => ()
          }
          match importname_to_string(i.name) {
            Some(name) =>
              if parse_bracket_resource_name(name) is Some(_) &&
                !(i.desc is @component.ExternDesc::FuncType(_)) {
                raise SectionParseError(10, "is not a func")
              }
            None => ()
          }
          // Import type references must be in-bounds at the point they appear.
          validate_externdesc(i.desc, type_table, counts.core_type)
          match i.desc {
            FuncType(tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::FuncType(_)) => ()
                Some(_) => raise CanonExpectedFuncType(tyidx)
                None => ()
              }
            ComponentType(tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::ComponentType(_)) => ()
                Some(_) => raise InvalidTypeIndex(tyidx)
                None => ()
              }
            InstanceType(tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::InstanceType(_)) => ()
                Some(@component.TypeDef::InstanceTypeEmpty) => ()
                Some(_) => raise InvalidTypeIndex(tyidx)
                None => ()
              }
            _ => ()
          }
          match i.desc {
            FuncType(tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::FuncType(ft)) => {
                  let sig = funcsig_of_functype(ft, type_table, resource_ids)
                  match importname_to_string(i.name) {
                    Some(name) =>
                      validate_bracketed_func_name(
                        10, name, ft, type_table, resource_ids, import_resource_names,
                      )
                    None => ()
                  }
                  if !functype_valid_in_interface(
                      ft, type_table, resource_ids, import_named_types,
                    ) {
                    raise SectionParseError(
                      10, "func not valid to be used as import",
                    )
                  }
                  func_types.push(Some(ft))
                  func_sig_shapes.push(Some(sig))
                  match importname_to_string(i.name) {
                    Some(name) => my_import_func_sigs.set(name, sig)
                    None => ()
                  }
                }
                _ => {
                  func_types.push(None)
                  func_sig_shapes.push(None)
                }
              }
            _ => ()
          }
          match i.desc {
            CoreModuleType(tyidx) =>
              if tyidx >= 0 && tyidx < core_type_exports.length() {
                match core_type_exports[tyidx] {
                  Some(map) => core_module_exports.push(Some(map))
                  None => raise CoreTypeIndexNotModuleType(tyidx)
                }
              } else {
                core_module_exports.push(None)
              }
            _ => ()
          }
          match i.desc {
            CoreModuleType(tyidx) => {
              core_module_defs.push(None)
              if tyidx >= 0 && tyidx < core_type_module_export_types.length() {
                core_module_export_types.push(
                  core_type_module_export_types[tyidx],
                )
              } else {
                core_module_export_types.push(None)
              }
              if tyidx >= 0 && tyidx < core_type_module_imports.length() {
                core_module_type_imports.push(core_type_module_imports[tyidx])
              } else {
                core_module_type_imports.push(None)
              }
            }
            InstanceType(tyidx) => {
              let mut type_map : Map[String, ExportedTypeInfo]? = None
              let mut type_sig_map : Map[String, TypeSig]? = None
              let mut resource_exports : Map[String, Int]? = None
              let mut func_export_sigs : Map[String, FuncSigShape]? = None
              match type_table[tyidx] {
                Some(td) => {
                  let sig = instancetype_sig_of_typedef(td, type_table, {})
                  instance_sigs.push(Some(sig))
                  match importname_to_string(i.name) {
                    Some(name) => my_import_instance_sigs.set(name, sig)
                    None => ()
                  }
                  match td {
                    @component.TypeDef::InstanceType(decls) => {
                      let local_types : Array[@component.TypeDef] = []
                      let local_resource_ids : Array[Int?] = []
                      let out : Map[String, ExportedTypeInfo] = {}
                      let type_sigs : Map[String, TypeSig] = {}
                      let res : Map[String, Int] = {}
                      let fns : Map[String, FuncSigShape] = {}
                      let mut any_types = false
                      let mut any_fns = false
                      let visiting : Map[Int, Int] = {}
                      fn record_type_slot() -> Unit {
                        local_types.push(@component.TypeDef::InstanceTypeEmpty)
                        local_resource_ids.push(None)
                      }

                      fn record_type_slot_for_bound(
                        b : @component.TypeBound,
                      ) -> Unit {
                        match b {
                          @component.TypeBound::SubResource => {
                            let rid = next_resource_id
                            next_resource_id += 1
                            local_types.push(
                              @component.TypeDef::ResourceType(
                                -1,
                                0x7f,
                                None,
                                @component.ResourceKind::HostDefined,
                              ),
                            )
                            local_resource_ids.push(Some(rid))
                          }
                          @component.TypeBound::Eq(_idx) => record_type_slot()
                        }
                      }

                      for d in decls {
                        match d {
                          @component.InstanceDecl::Type(t) => {
                            local_types.push(t)
                            local_resource_ids.push(None)
                          }
                          @component.InstanceDecl::AliasOuter(
                            kind,
                            _count,
                            _idx
                          ) => if kind == 0x03 { record_type_slot() }
                          @component.InstanceDecl::AliasInstanceExport(
                            kind,
                            _inst,
                            _name
                          ) => if kind == 0x03 { record_type_slot() }
                          @component.InstanceDecl::Export(name, desc) =>
                            match desc {
                              @component.ExternDesc::Type(b) =>
                                match b {
                                  @component.TypeBound::SubResource => {
                                    let rid = next_resource_id
                                    next_resource_id += 1
                                    local_types.push(
                                      @component.TypeDef::ResourceType(
                                        -1,
                                        0x7f,
                                        None,
                                        @component.ResourceKind::HostDefined,
                                      ),
                                    )
                                    local_resource_ids.push(Some(rid))
                                    out.set(
                                      name,
                                      ExportedTypeInfo::Resource(rid),
                                    )
                                    type_sigs.set(name, TypeSig::Resource(rid))
                                    res.set(name, rid)
                                    any_types = true
                                  }
                                  @component.TypeBound::Eq(idx) => {
                                    let new_idx = local_types.length()
                                    if idx >= 0 && idx < local_types.length() {
                                      local_types.push(local_types[idx])
                                      local_resource_ids.push(
                                        local_resource_ids[idx],
                                      )
                                    } else {
                                      record_type_slot()
                                    }
                                    let sig = type_sig_of_valtype_lg(
                                      @component.ValType::TypeIdx(new_idx),
                                      local_types,
                                      local_resource_ids,
                                      type_table,
                                      resource_ids,
                                      visiting,
                                    )
                                    out.set(name, ExportedTypeInfo::Opaque)
                                    type_sigs.set(name, sig)
                                    any_types = true
                                  }
                                }
                              @component.ExternDesc::FuncType(ft_idx) => {
                                let sig = if ft_idx >= 0 &&
                                  ft_idx < local_types.length() {
                                  match local_types[ft_idx] {
                                    @component.TypeDef::FuncType(ft) =>
                                      Some(
                                        funcsig_of_functype_lg(
                                          ft, local_types, local_resource_ids, type_table,
                                          resource_ids,
                                        ),
                                      )
                                    _ => None
                                  }
                                } else if ft_idx >= 0 &&
                                  ft_idx < type_table.length() {
                                  match type_table[ft_idx] {
                                    Some(@component.TypeDef::FuncType(ft)) =>
                                      Some(
                                        funcsig_of_functype_lg(
                                          ft,
                                          [],
                                          [],
                                          type_table,
                                          resource_ids,
                                        ),
                                      )
                                    _ => None
                                  }
                                } else {
                                  None
                                }
                                match sig {
                                  Some(s) => {
                                    fns.set(name, s)
                                    any_fns = true
                                  }
                                  None => ()
                                }
                              }
                              _ => ()
                            }
                          _ => ()
                        }
                      }
                      if any_types {
                        type_map = Some(out)
                        type_sig_map = Some(type_sigs)
                        resource_exports = Some(res)
                      }
                      if any_fns {
                        func_export_sigs = Some(fns)
                      }
                    }
                    _ => ()
                  }
                  match (importname_to_string(i.name), resource_exports) {
                    (Some(name), Some(res)) =>
                      my_import_instance_resource_exports.set(name, res)
                    _ => ()
                  }
                  if !instancetype_valid_for_use_as_interface(
                      tyidx, type_table, type_outers,
                    ) {
                    raise SectionParseError(
                      10, "instance not valid to be used as import",
                    )
                  }
                }
                None => instance_sigs.push(None)
              }
              instance_export_type_idxs.push(None)
              instance_export_func_idxs.push(None)
              instance_export_type_map.push(type_map)
              instance_export_type_sigs.push(type_sig_map)
              instance_export_func_sigs.push(func_export_sigs)
              instance_nested_instance_type_sigs.push(None)
              instance_nested_instance_func_sigs.push(None)
              // Imported instances contribute an entry to the instance index space.
              // We don't have a precise effective-size model here; treat as 1.
              instance_sizes.push(1)
              interface_instance_idxs.set(instance_sigs.length() - 1, 1)
            }
            _ => ()
          }
          if i.desc is FuncType(_) {
            imported_funcs += 1
          }
          match i.desc {
            ComponentType(tyidx) => {
              let mut import_sorts : Map[String, @component.Sort]? = None
              let mut import_instance_sigs : Map[String, InstanceSig]? = None
              let mut import_func_sigs : Map[String, FuncSigShape]? = None
              let mut import_core_module_import_sigs : Map[
                String,
                Map[String, CoreExternType],
              ]? = None
              let mut import_core_module_exports : Map[String, Map[String, Int]]? = None
              let mut import_type_sigs : Map[String, TypeSig]? = None
              let mut import_type_bounds : Map[String, @component.TypeBound]? = None
              let mut export_sorts : Map[String, @component.Sort]? = None
              let mut export_instance_sigs : Map[String, InstanceSig]? = None
              let mut export_func_sigs : Map[String, FuncSigShape]? = None
              if tyidx >= 0 && tyidx < type_table.length() {
                match type_table[tyidx] {
                  Some(@component.TypeDef::ComponentType(decls)) => {
                    let (imp_sorts, imp_inst_sigs, exp_sorts, exp_inst_sigs) = componenttype_signature_of_decls(
                      decls, type_table,
                    )
                    import_sorts = Some(imp_sorts)
                    import_instance_sigs = Some(imp_inst_sigs)
                    import_func_sigs = Some(
                      componenttype_import_func_sigs_of_decls(
                        decls, type_table, resource_ids,
                      ),
                    )
                    let (core_imports, core_exports) = componenttype_import_core_module_sigs_of_decls(
                      decls,
                    )
                    import_core_module_import_sigs = Some(core_imports)
                    import_core_module_exports = Some(core_exports)
                    import_type_sigs = Some(
                      componenttype_import_type_sigs_of_decls(
                        decls, type_table, resource_ids,
                      ),
                    )
                    import_type_bounds = Some(
                      componenttype_import_type_bounds_of_decls(decls),
                    )
                    export_sorts = Some(exp_sorts)
                    export_instance_sigs = Some(exp_inst_sigs)
                    export_func_sigs = Some(
                      componenttype_export_func_sigs_of_decls(
                        decls, type_table, resource_ids,
                      ),
                    )
                  }
                  _ => ()
                }
              }
              component_import_sorts.push(import_sorts)
              component_import_instance_sigs.push(import_instance_sigs)
              component_import_func_sigs.push(import_func_sigs)
              component_import_instance_resource_exports.push(None)
              component_import_core_module_exports.push(
                import_core_module_exports,
              )
              component_import_core_module_import_sigs.push(
                import_core_module_import_sigs,
              )
              component_import_type_bounds.push(import_type_bounds)
              component_import_type_sigs.push(import_type_sigs)
              component_export_sorts.push(export_sorts)
              component_export_instance_sigs.push(export_instance_sigs)
              component_export_instance_type_sigs.push(None)
              component_export_instance_func_sigs.push(None)
              component_export_type_sigs.push(None)
              component_export_func_sigs.push(export_func_sigs)
              // Imported component size is unknown; treat as 1.
              component_sizes.push(1)
            }
            _ => ()
          }
          match i.desc {
            // Type imports extend the type index space.
            //
            // `eq` imports are aliases to an existing type, so we can propagate
            // the underlying definition/size/depth. `sub resource` is treated
            // as abstract for now.
            Type(b) => {
              match b {
                Eq(tyidx) =>
                  if tyidx >= 0 && tyidx < type_table.length() {
                    type_table.push(type_table[tyidx])
                    if tyidx >= 0 && tyidx < local_resource_types.length() {
                      local_resource_types.push(local_resource_types[tyidx])
                    } else {
                      local_resource_types.push(false)
                    }
                    if tyidx >= 0 && tyidx < resource_ids.length() {
                      resource_ids.push(resource_ids[tyidx])
                    } else {
                      resource_ids.push(None)
                    }
                    if tyidx >= 0 && tyidx < type_sizes.length() {
                      type_sizes.push(type_sizes[tyidx])
                    } else {
                      type_sizes.push(1)
                    }
                    if tyidx >= 0 && tyidx < type_depths.length() {
                      type_depths.push(type_depths[tyidx])
                    } else {
                      type_depths.push(1)
                    }
                  } else {
                    type_table.push(None)
                    local_resource_types.push(false)
                    resource_ids.push(None)
                    type_sizes.push(1)
                    type_depths.push(1)
                  }
                SubResource => {
                  type_table.push(
                    Some(
                      @component.TypeDef::ResourceType(
                        -1,
                        0x7f,
                        None,
                        @component.ResourceKind::HostDefined,
                      ),
                    ),
                  )
                  local_resource_types.push(false)
                  resource_ids.push(Some(next_resource_id))
                  next_resource_id += 1
                  type_sizes.push(1)
                  type_depths.push(1)
                }
              }
              // Imported types are named by their import string, so the newly
              // introduced type index is available as a named type.
              let new_idx = type_table.length() - 1
              named_types.set(new_idx, 1)
              import_named_types.set(new_idx, 1)
              match importname_to_string(i.name) {
                Some(name) =>
                  match b {
                    Eq(tyidx) => {
                      my_import_type_bounds.set(
                        name,
                        @component.TypeBound::Eq(tyidx),
                      )
                      my_import_type_sigs.set(
                        name,
                        type_sig_of_typeidx(tyidx, type_table, resource_ids),
                      )
                    }
                    SubResource => {
                      import_resource_names.set(name, new_idx)
                      my_import_type_bounds.set(
                        name,
                        @component.TypeBound::SubResource,
                      )
                      my_import_type_sigs.set(
                        name,
                        type_sig_of_typeidx(new_idx, type_table, resource_ids),
                      )
                    }
                  }
                None => ()
              }
              if !valtype_valid_for_type_import_export(
                  @component.ValType::TypeIdx(new_idx),
                  type_table,
                  resource_ids,
                  import_named_types,
                  {},
                ) {
                raise SectionParseError(
                  10, "type not valid to be used as import",
                )
              }
              match type_table[new_idx] {
                Some(@component.TypeDef::InstanceType(_))
                | Some(@component.TypeDef::InstanceTypeEmpty) =>
                  if !instancetype_valid_for_use_as_interface(
                      new_idx, type_table, type_outers,
                    ) {
                    raise SectionParseError(
                      10, "type not valid to be used as import",
                    )
                  }
                _ => ()
              }
            }
            _ => ()
          }
          count_import(i.desc, counts)
        }
      }
      11 => {
        let exports = @component.parse_export_section(s.payload) catch {
          e => raise SectionParseError(11, "\{e}")
        }
        for e in exports {
          validate_export_name(e.name, cfg)
          if is_root && e.sortidx.sort is @component.Sort::Component {
            raise SectionParseError(
              11, "exporting a component from the root component is not supported",
            )
          }
          match exportname_to_string(e.name) {
            Some(name) => {
              // wasm-tools' very-nested.wast relies on long export names to
              // trigger the effective-size limiter.
              export_size = add_type_size(export_size, name.length())
              let key = if cfg.wit_names {
                wit_conflict_key(name)
              } else {
                name
              }
              match seen_export_names.get(key) {
                Some(prev) =>
                  if prev == name {
                    raise DuplicateExportName(name)
                  } else {
                    raise SectionParseError(
                      11,
                      "export name `\{name}` conflicts with previous name `\{prev}`",
                    )
                  }
                None => seen_export_names.set(key, name)
              }
            }
            None => ()
          }
          match exportname_to_string(e.name) {
            Some(name) => my_export_sorts.set(name, e.sortidx.sort)
            None => ()
          }
          match exportname_to_string(e.name) {
            Some(name) =>
              if parse_bracket_resource_name(name) is Some(_) &&
                !(e.sortidx.sort is @component.Sort::Func) {
                raise SectionParseError(11, "is not a func")
              }
            None => ()
          }
          if is_root && e.sortidx.sort is Func && e.sortidx.idx < imported_funcs {
            raise ExportedImportedFunc(e.sortidx.idx)
          }
          check_sortidx(e.sortidx, counts, type_table.length())
          if e.sortidx.sort is @component.Sort::Type {
            match exportname_to_string(e.name) {
              Some(name) =>
                my_export_type_sigs.set(
                  name,
                  type_sig_of_typeidx(e.sortidx.idx, type_table, resource_ids),
                )
              None => ()
            }
            match exportname_to_string(e.name) {
              Some(name) =>
                if type_sig_of_typeidx(e.sortidx.idx, type_table, resource_ids)
                  is TypeSig::Resource(_) {
                  export_resource_names.set(name, e.sortidx.idx)
                }
              None => ()
            }
          }
          if e.sortidx.sort is @component.Sort::Func {
            match exportname_to_string(e.name) {
              Some(name) =>
                if e.sortidx.idx >= 0 && e.sortidx.idx < func_types.length() {
                  let mut ft : @component.FuncType? = None
                  match e.desc {
                    Some(@component.ExternDesc::FuncType(tyidx)) =>
                      if tyidx >= 0 && tyidx < type_table.length() {
                        match type_table[tyidx] {
                          Some(@component.TypeDef::FuncType(t)) => ft = Some(t)
                          _ => ()
                        }
                      }
                    _ => ()
                  }
                  if ft is None {
                    ft = func_types[e.sortidx.idx]
                  }
                  match ft {
                    Some(ft) => {
                      validate_bracketed_func_name(
                        11, name, ft, type_table, resource_ids, export_resource_names,
                      )
                      my_export_func_sigs.set(
                        name,
                        funcsig_of_functype(ft, type_table, resource_ids),
                      )
                    }
                    None => ()
                  }
                }
              None => ()
            }
          }
          if e.sortidx.sort is @component.Sort::Instance {
            match exportname_to_string(e.name) {
              Some(name) => {
                if e.sortidx.idx >= 0 && e.sortidx.idx < instance_sigs.length() {
                  match instance_sigs[e.sortidx.idx] {
                    Some(sig) => my_export_instance_sigs.set(name, sig)
                    None => ()
                  }
                }
                if e.sortidx.idx >= 0 &&
                  e.sortidx.idx < instance_export_type_sigs.length() {
                  match instance_export_type_sigs[e.sortidx.idx] {
                    Some(map) => my_export_instance_type_sigs.set(name, map)
                    None => ()
                  }
                }
                if e.sortidx.idx >= 0 &&
                  e.sortidx.idx < instance_export_func_sigs.length() {
                  match instance_export_func_sigs[e.sortidx.idx] {
                    Some(map) => my_export_instance_func_sigs.set(name, map)
                    None => ()
                  }
                }
              }
              None => ()
            }
          }

          // Enforce "exportable" rules: nominal-ish types must have names in the
          // interface namespace (provided via type imports/exports).
          match e.sortidx.sort {
            @component.Sort::Type => {
              let idx = e.sortidx.idx
              let had = named_types.get(idx) is Some(_)
              if !had {
                named_types.set(idx, 1)
              }
              if !valtype_valid_for_type_import_export(
                  @component.ValType::TypeIdx(idx),
                  type_table,
                  resource_ids,
                  named_types,
                  {},
                ) {
                raise SectionParseError(
                  11, "type not valid to be used as export",
                )
              }
              if !had {
                named_types.remove(idx) |> ignore
              }
              if idx >= 0 && idx < type_table.length() {
                match type_table[idx] {
                  Some(@component.TypeDef::InstanceType(_))
                  | Some(@component.TypeDef::InstanceTypeEmpty) =>
                    if !instancetype_valid_for_use_as_interface(
                        idx, type_table, type_outers,
                      ) {
                      raise SectionParseError(
                        11, "type not valid to be used as export",
                      )
                    }
                  _ => ()
                }
              }
            }
            @component.Sort::Func =>
              if e.sortidx.idx >= 0 && e.sortidx.idx < func_types.length() {
                let mut ft : @component.FuncType? = None
                match e.desc {
                  Some(@component.ExternDesc::FuncType(tyidx)) =>
                    if tyidx >= 0 && tyidx < type_table.length() {
                      match type_table[tyidx] {
                        Some(@component.TypeDef::FuncType(t)) => ft = Some(t)
                        _ => ()
                      }
                    }
                  _ => ()
                }
                if ft is None {
                  ft = func_types[e.sortidx.idx]
                }
                match ft {
                  Some(ft) =>
                    if !functype_valid_in_interface(
                        ft, type_table, resource_ids, named_types,
                      ) {
                      raise SectionParseError(
                        11, "func not valid to be used as export",
                      )
                    }
                  None => ()
                }
              }
            @component.Sort::Instance => {
              let inst_idx = e.sortidx.idx
              if inst_idx >= 0 && inst_idx < counts.instance {
                let exported_type_idxs : Array[Int] = []
                let seen : Map[Int, Int] = {}
                if inst_idx >= 0 &&
                  inst_idx < instance_export_type_idxs.length() {
                  match instance_export_type_idxs[inst_idx] {
                    Some(t_idxs) =>
                      for t in t_idxs {
                        if seen.get(t) is None {
                          seen.set(t, 1)
                          exported_type_idxs.push(t)
                        }
                      }
                    None => ()
                  }
                }
                if inst_idx >= 0 && inst_idx < instance_export_type_map.length() {
                  match instance_export_type_map[inst_idx] {
                    Some(map) =>
                      for kv in map.iter() {
                        let (_name, info) = kv
                        match info {
                          ExportedTypeInfo::Existing(t) =>
                            if seen.get(t) is None {
                              seen.set(t, 1)
                              exported_type_idxs.push(t)
                            }
                          _ => ()
                        }
                      }
                    None => ()
                  }
                }
                if inst_idx >= 0 &&
                  inst_idx < instance_export_type_sigs.length() {
                  match instance_export_type_sigs[inst_idx] {
                    Some(map) =>
                      for kv in map.iter() {
                        let (_name, sig) = kv
                        match
                          typeidx_of_typesig(sig, type_table, resource_ids) {
                          Some(t) =>
                            if seen.get(t) is None {
                              seen.set(t, 1)
                              exported_type_idxs.push(t)
                            }
                          None => ()
                        }
                      }
                    None => ()
                  }
                }
                let inst_named : Map[Int, Int] = {}
                for kv in named_types.iter() {
                  let (k, v) = kv
                  inst_named.set(k, v)
                }
                for t in exported_type_idxs {
                  inst_named.set(t, 1)
                }
                for t in exported_type_idxs {
                  if !valtype_valid_in_interface(
                      @component.ValType::TypeIdx(t),
                      type_table,
                      resource_ids,
                      inst_named,
                      {},
                    ) {
                    raise SectionParseError(
                      11, "instance not valid to be used as export",
                    )
                  }
                }

                // Make types exported through this instance available to later
                // exports in this component's interface.
                for t in exported_type_idxs {
                  named_types.set(t, 1)
                }

                // Validate exported functions use only named types (either named
                // in the parent interface or exported by this instance).
                let named_sigs : Array[TypeSig] = []
                for kv in inst_named.iter() {
                  let (k, _v) = kv
                  let sig = type_sig_of_typeidx(k, type_table, resource_ids)
                  if sig != TypeSig::Other && !typesig_contains(sig, named_sigs) {
                    named_sigs.push(sig)
                  }
                }
                if inst_idx >= 0 &&
                  inst_idx < instance_export_type_sigs.length() {
                  match instance_export_type_sigs[inst_idx] {
                    Some(map) =>
                      for kv in map.iter() {
                        let (_name, sig) = kv
                        if sig != TypeSig::Other &&
                          !typesig_contains(sig, named_sigs) {
                          named_sigs.push(sig)
                        }
                      }
                    None => ()
                  }
                }
                let mut validated_by_idx = false
                let mut validated_by_sig = false
                if inst_idx >= 0 &&
                  inst_idx < instance_export_func_idxs.length() {
                  match instance_export_func_idxs[inst_idx] {
                    Some(f_idxs) => {
                      validated_by_idx = true
                      for f in f_idxs {
                        if f >= 0 && f < func_types.length() {
                          match func_types[f] {
                            Some(ft) =>
                              if !functype_valid_in_interface(
                                  ft, type_table, resource_ids, inst_named,
                                ) {
                                raise SectionParseError(
                                  11, "instance not valid to be used as export",
                                )
                              }
                            None => ()
                          }
                        }
                      }
                    }
                    None => ()
                  }
                }
                if !validated_by_idx &&
                  inst_idx >= 0 &&
                  inst_idx < instance_export_func_sigs.length() {
                  match instance_export_func_sigs[inst_idx] {
                    Some(map) => {
                      validated_by_sig = true
                      for kv in map.iter() {
                        let (_name, sig) = kv
                        if !funcsig_valid_in_interface(sig, named_sigs) {
                          raise SectionParseError(
                            11, "instance not valid to be used as export",
                          )
                        }
                      }
                    }
                    None => ()
                  }
                }
                if !validated_by_idx && !validated_by_sig {
                  let mut needs_funcs = false
                  if inst_idx >= 0 && inst_idx < instance_sigs.length() {
                    match instance_sigs[inst_idx] {
                      Some(s) =>
                        for kv in s.exports.iter() {
                          let (_n, sort) = kv
                          if sort is @component.Sort::Func {
                            needs_funcs = true
                            break
                          }
                        }
                      None => ()
                    }
                  }
                  if needs_funcs {
                    raise SectionParseError(
                      11, "instance not valid to be used as export",
                    )
                  }
                }
              }
            }
            _ => ()
          }
          // Track effective type size of this component's export signature.
          match e.sortidx.sort {
            @component.Sort::Instance => {
              let delta = if e.sortidx.idx >= 0 &&
                e.sortidx.idx < instance_sizes.length() {
                instance_sizes[e.sortidx.idx]
              } else {
                1
              }
              export_size = add_type_size(export_size, delta)
            }
            @component.Sort::Type => {
              let delta = if e.sortidx.idx >= 0 &&
                e.sortidx.idx < type_sizes.length() {
                type_sizes[e.sortidx.idx]
              } else {
                1
              }
              export_size = add_type_size(export_size, delta)
            }
            @component.Sort::Component => {
              let delta = if e.sortidx.idx >= 0 &&
                e.sortidx.idx < component_sizes.length() {
                component_sizes[e.sortidx.idx]
              } else {
                1
              }
              export_size = add_type_size(export_size, delta)
            }
            _ => export_size = add_type_size(export_size, 1)
          }
          match e.desc {
            Some(d) => validate_externdesc(d, type_table, counts.core_type)
            None => ()
          }
          // Export ascription: if a type is provided, it must be compatible with
          // the actual export (we currently model instance-type compatibility).
          match (e.sortidx.sort, e.desc) {
            (
              @component.Sort::Instance,
              Some(@component.ExternDesc::InstanceType(tyidx)),
            ) =>
              if tyidx >= 0 && tyidx < type_table.length() {
                let expected = instancetype_sig_of_global_idx(
                  tyidx,
                  type_table,
                  {},
                )
                let actual = if e.sortidx.idx >= 0 &&
                  e.sortidx.idx < instance_sigs.length() {
                  instance_sigs[e.sortidx.idx]
                } else {
                  None
                }
                check_instance_subtype(actual, expected)
                match exportname_to_string(e.name) {
                  Some(name) => my_export_instance_sigs.set(name, expected)
                  None => ()
                }
              } else {
                raise AscribedExportTypeIncompatible
              }
            (_sort, Some(d)) =>
              if sort_of_externdesc(d) != e.sortidx.sort {
                raise AscribedExportTypeIncompatible
              }
            _ => ()
          }

          // Component exports can introduce an alias in the corresponding index
          // space, which later sections can reference by index.
          if e.sortidx.sort is @component.Sort::Type {
            let idx = e.sortidx.idx
            if idx >= 0 && idx < type_table.length() {
              type_table.push(type_table[idx])
              if idx >= 0 && idx < local_resource_types.length() {
                local_resource_types.push(local_resource_types[idx])
              } else {
                local_resource_types.push(false)
              }
              if idx >= 0 && idx < resource_ids.length() {
                resource_ids.push(resource_ids[idx])
              } else {
                resource_ids.push(None)
              }
              if idx >= 0 && idx < type_sizes.length() {
                type_sizes.push(type_sizes[idx])
              } else {
                type_sizes.push(1)
              }
              if idx >= 0 && idx < type_depths.length() {
                type_depths.push(type_depths[idx])
              } else {
                type_depths.push(1)
              }
            } else {
              type_table.push(None)
              local_resource_types.push(false)
              resource_ids.push(None)
              type_sizes.push(1)
              type_depths.push(1)
            }
            // The exported type alias is now a named type in the interface.
            named_types.set(type_table.length() - 1, 1)
          } else {
            count_alias(e.sortidx.sort, counts)
            match e.sortidx.sort {
              @component.Sort::Func =>
                if e.sortidx.idx >= 0 && e.sortidx.idx < func_types.length() {
                  func_types.push(func_types[e.sortidx.idx])
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < func_sig_shapes.length() {
                    func_sig_shapes.push(func_sig_shapes[e.sortidx.idx])
                  } else {
                    func_sig_shapes.push(None)
                  }
                } else {
                  func_types.push(None)
                  func_sig_shapes.push(None)
                }
              @component.Sort::Instance =>
                if e.sortidx.idx >= 0 && e.sortidx.idx < instance_sigs.length() {
                  instance_sigs.push(instance_sigs[e.sortidx.idx])
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_export_type_idxs.length() {
                    instance_export_type_idxs.push(
                      instance_export_type_idxs[e.sortidx.idx],
                    )
                  } else {
                    instance_export_type_idxs.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_export_func_idxs.length() {
                    instance_export_func_idxs.push(
                      instance_export_func_idxs[e.sortidx.idx],
                    )
                  } else {
                    instance_export_func_idxs.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_export_type_map.length() {
                    instance_export_type_map.push(
                      instance_export_type_map[e.sortidx.idx],
                    )
                  } else {
                    instance_export_type_map.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_export_type_sigs.length() {
                    instance_export_type_sigs.push(
                      instance_export_type_sigs[e.sortidx.idx],
                    )
                  } else {
                    instance_export_type_sigs.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_export_func_sigs.length() {
                    instance_export_func_sigs.push(
                      instance_export_func_sigs[e.sortidx.idx],
                    )
                  } else {
                    instance_export_func_sigs.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_nested_instance_type_sigs.length() {
                    instance_nested_instance_type_sigs.push(
                      instance_nested_instance_type_sigs[e.sortidx.idx],
                    )
                  } else {
                    instance_nested_instance_type_sigs.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_nested_instance_func_sigs.length() {
                    instance_nested_instance_func_sigs.push(
                      instance_nested_instance_func_sigs[e.sortidx.idx],
                    )
                  } else {
                    instance_nested_instance_func_sigs.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_sizes.length() {
                    instance_sizes.push(instance_sizes[e.sortidx.idx])
                  } else {
                    instance_sizes.push(1)
                  }
                  interface_instance_idxs.set(instance_sigs.length() - 1, 1)
                } else {
                  instance_sigs.push(None)
                  instance_export_type_idxs.push(None)
                  instance_export_func_idxs.push(None)
                  instance_export_type_map.push(None)
                  instance_export_type_sigs.push(None)
                  instance_export_func_sigs.push(None)
                  instance_nested_instance_type_sigs.push(None)
                  instance_nested_instance_func_sigs.push(None)
                  instance_sizes.push(1)
                  interface_instance_idxs.set(instance_sigs.length() - 1, 1)
                }
              @component.Sort::Component => {
                let src = e.sortidx.idx
                if src >= 0 && src < component_import_sorts.length() {
                  component_import_sorts.push(component_import_sorts[src])
                  component_import_instance_sigs.push(
                    component_import_instance_sigs[src],
                  )
                  component_import_func_sigs.push(
                    component_import_func_sigs[src],
                  )
                  component_import_instance_resource_exports.push(
                    component_import_instance_resource_exports[src],
                  )
                  component_import_core_module_exports.push(
                    component_import_core_module_exports[src],
                  )
                  component_import_core_module_import_sigs.push(
                    component_import_core_module_import_sigs[src],
                  )
                  component_import_type_bounds.push(
                    component_import_type_bounds[src],
                  )
                  component_import_type_sigs.push(
                    component_import_type_sigs[src],
                  )
                  component_export_sorts.push(component_export_sorts[src])
                  component_export_instance_sigs.push(
                    component_export_instance_sigs[src],
                  )
                  component_export_instance_type_sigs.push(
                    component_export_instance_type_sigs[src],
                  )
                  component_export_instance_func_sigs.push(
                    component_export_instance_func_sigs[src],
                  )
                  component_export_type_sigs.push(
                    component_export_type_sigs[src],
                  )
                  component_export_func_sigs.push(
                    component_export_func_sigs[src],
                  )
                } else {
                  component_import_sorts.push(None)
                  component_import_instance_sigs.push(None)
                  component_import_func_sigs.push(None)
                  component_import_instance_resource_exports.push(None)
                  component_import_core_module_exports.push(None)
                  component_import_core_module_import_sigs.push(None)
                  component_import_type_bounds.push(None)
                  component_import_type_sigs.push(None)
                  component_export_sorts.push(None)
                  component_export_instance_sigs.push(None)
                  component_export_instance_type_sigs.push(None)
                  component_export_instance_func_sigs.push(None)
                  component_export_type_sigs.push(None)
                  component_export_func_sigs.push(None)
                }
                if src >= 0 && src < component_sizes.length() {
                  component_sizes.push(component_sizes[src])
                } else {
                  component_sizes.push(1)
                }
              }
              @component.Sort::Core(core_sort) =>
                if core_sort == 0x00 {
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_func_types.length() {
                    core_func_types.push(core_func_types[e.sortidx.idx])
                  } else {
                    core_func_types.push(None)
                  }
                } else if core_sort == 0x02 {
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_memory_types.length() {
                    core_memory_types.push(core_memory_types[e.sortidx.idx])
                  } else {
                    core_memory_types.push(None)
                  }
                } else if core_sort == 0x11 {
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_module_exports.length() {
                    core_module_exports.push(core_module_exports[e.sortidx.idx])
                  } else {
                    core_module_exports.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_module_export_types.length() {
                    core_module_export_types.push(
                      core_module_export_types[e.sortidx.idx],
                    )
                  } else {
                    core_module_export_types.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_module_type_imports.length() {
                    core_module_type_imports.push(
                      core_module_type_imports[e.sortidx.idx],
                    )
                  } else {
                    core_module_type_imports.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_module_defs.length() {
                    core_module_defs.push(core_module_defs[e.sortidx.idx])
                  } else {
                    core_module_defs.push(None)
                  }
                } else if core_sort == 0x12 {
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_instance_exports.length() {
                    core_instance_exports.push(
                      core_instance_exports[e.sortidx.idx],
                    )
                  } else {
                    core_instance_exports.push(None)
                  }
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_instance_export_types.length() {
                    core_instance_export_types.push(
                      core_instance_export_types[e.sortidx.idx],
                    )
                  } else {
                    core_instance_export_types.push(None)
                  }
                } else {
                  ()
                }
              _ => ()
            }
          }
          // These aliases can be referenced by later exports/sections, so
          // conservatively account for their contribution to the effective
          // signature size (wasm-tools' very-nested.wast).
          match e.sortidx.sort {
            @component.Sort::Instance => {
              let delta = if instance_sizes.length() > 0 {
                instance_sizes[instance_sizes.length() - 1]
              } else {
                1
              }
              export_size = add_type_size(export_size, delta)
            }
            @component.Sort::Type => {
              let delta = if type_sizes.length() > 0 {
                type_sizes[type_sizes.length() - 1]
              } else {
                1
              }
              export_size = add_type_size(export_size, delta)
            }
            @component.Sort::Component => {
              let delta = if component_sizes.length() > 0 {
                component_sizes[component_sizes.length() - 1]
              } else {
                1
              }
              export_size = add_type_size(export_size, delta)
            }
            _ => export_size = add_type_size(export_size, 1)
          }
        }
      }
      5 => {
        let instances = @component.parse_instance_section(s.payload) catch {
          e => raise SectionParseError(5, "\{e}")
        }
        for inst in instances {
          let mut inst_sig : InstanceSig? = None
          let mut inst_size = 1
          let mut inst_type_idxs : Array[Int]? = None
          let mut inst_func_idxs : Array[Int]? = None
          let mut inst_type_map : Map[String, ExportedTypeInfo]? = None
          let mut inst_type_sig_map : Map[String, TypeSig]? = None
          let mut inst_func_sig_map : Map[String, FuncSigShape]? = None
          let mut inst_nested_type_sigs : Map[String, Map[String, TypeSig]]? = None
          let mut inst_nested_func_sigs : Map[String, Map[String, FuncSigShape]]? = None
          match inst.expr {
            Instantiate(component_idx, args) => {
              if component_idx < 0 || component_idx >= counts.component {
                raise InvalidComponentIndex(component_idx)
              }
              if component_idx >= 0 && component_idx < component_sizes.length() {
                inst_size = component_sizes[component_idx]
              } else {
                inst_size = 1
              }
              // Validate instantiation args against the component's import
              // signature when available.
              let expected_imports = if component_idx >= 0 &&
                component_idx < component_import_sorts.length() {
                component_import_sorts[component_idx]
              } else {
                None
              }
              let expected_import_instance_sigs = if component_idx >= 0 &&
                component_idx < component_import_instance_sigs.length() {
                component_import_instance_sigs[component_idx]
              } else {
                None
              }
              let expected_import_func_sigs = if component_idx >= 0 &&
                component_idx < component_import_func_sigs.length() {
                component_import_func_sigs[component_idx]
              } else {
                None
              }
              let expected_import_core_modules = if component_idx >= 0 &&
                component_idx < component_import_core_module_exports.length() {
                component_import_core_module_exports[component_idx]
              } else {
                None
              }
              let expected_import_core_module_import_sigs = if component_idx >=
                0 &&
                component_idx <
                component_import_core_module_import_sigs.length() {
                component_import_core_module_import_sigs[component_idx]
              } else {
                None
              }
              let expected_import_type_sigs = if component_idx >= 0 &&
                component_idx < component_import_type_sigs.length() {
                component_import_type_sigs[component_idx]
              } else {
                None
              }
              let expected_import_type_bounds = if component_idx >= 0 &&
                component_idx < component_import_type_bounds.length() {
                component_import_type_bounds[component_idx]
              } else {
                None
              }
              let expected_import_instance_resource_exports = if component_idx >=
                0 &&
                component_idx <
                component_import_instance_resource_exports.length() {
                component_import_instance_resource_exports[component_idx]
              } else {
                None
              }
              let pending_type_args : Array[(String, Int)] = []
              let pending_func_args : Array[(String, Int)] = []
              let pending_instance_args : Array[(String, Int)] = []
              let seen_args : Map[String, Int] = {}
              for a in args {
                check_sortidx(a.sortidx, counts, type_table.length())
                if seen_args.get(a.name) is Some(_) {
                  raise DuplicateInstantiationArg(a.name)
                }
                seen_args.set(a.name, 1)
                match expected_imports {
                  Some(map) =>
                    match map.get(a.name) {
                      None => () // extra args are allowed (wasm-tools behavior)
                      Some(sort) =>
                        if sort != a.sortidx.sort {
                          raise ComponentImportTypeMismatch(a.name)
                        } else {
                          if sort is @component.Sort::Func {
                            pending_func_args.push((a.name, a.sortidx.idx))
                          }
                          if sort is @component.Sort::Instance {
                            pending_instance_args.push((a.name, a.sortidx.idx))
                          }
                          match (sort, expected_import_instance_sigs) {
                            (@component.Sort::Instance, Some(sig_map)) =>
                              match sig_map.get(a.name) {
                                Some(req) => {
                                  let actual = if a.sortidx.idx >= 0 &&
                                    a.sortidx.idx < instance_sigs.length() {
                                    instance_sigs[a.sortidx.idx]
                                  } else {
                                    None
                                  }
                                  check_instance_subtype(actual, req)
                                }
                                None => ()
                              }
                            _ => ()
                          }
                          match (sort, expected_import_core_modules) {
                            (@component.Sort::Core(0x11), Some(core_map)) =>
                              match core_map.get(a.name) {
                                Some(req) =>
                                  if a.sortidx.idx >= 0 &&
                                    a.sortidx.idx < core_module_exports.length() {
                                    check_core_module_subtype(
                                      core_module_exports[a.sortidx.idx],
                                      req,
                                    )
                                  } else {
                                    ()
                                  }
                                None => ()
                              }
                            _ => ()
                          }
                          match
                            (sort, expected_import_core_module_import_sigs) {
                            (@component.Sort::Core(0x11), Some(sig_map)) =>
                              match sig_map.get(a.name) {
                                Some(req) => {
                                  let actual_sig = core_module_import_sig_of_idx(
                                    a.sortidx.idx,
                                    core_module_defs,
                                    core_module_type_imports,
                                  )
                                  check_core_module_import_subtype(
                                    actual_sig, req,
                                  )
                                }
                                None => ()
                              }
                            _ => ()
                          }
                          if sort is @component.Sort::Type {
                            pending_type_args.push((a.name, a.sortidx.idx))
                          }
                        }
                    }
                  None => ()
                }
              }
              match expected_imports {
                Some(map) =>
                  for kv in map.iter() {
                    let (name, _sort) = kv
                    if seen_args.get(name) is None {
                      raise MissingComponentImport(name)
                    }
                  }
                None => ()
              }

              // Validate type/function arguments that may depend on type-argument
              // substitution (notably for nominal resource types).
              let rid_subst : Map[Int, Int] = {}
              match expected_import_instance_resource_exports {
                Some(inst_map) =>
                  for kv in pending_instance_args {
                    let (name, inst_idx) = kv
                    match inst_map.get(name) {
                      Some(exports) =>
                        for kv2 in exports.iter() {
                          let (tname, expected_rid) = kv2
                          let tmap = if inst_idx >= 0 &&
                            inst_idx < instance_export_type_map.length() {
                            instance_export_type_map[inst_idx]
                          } else {
                            None
                          }
                          match tmap {
                            Some(map) =>
                              match map.get(tname) {
                                Some(ExportedTypeInfo::Resource(actual_rid)) =>
                                  rid_subst.set(expected_rid, actual_rid)
                                Some(ExportedTypeInfo::Existing(tidx)) =>
                                  match
                                    type_sig_of_typeidx(
                                      tidx, type_table, resource_ids,
                                    ) {
                                    TypeSig::Resource(actual_rid) =>
                                      rid_subst.set(expected_rid, actual_rid)
                                    _ =>
                                      raise SectionParseError(
                                        5, "expected resource, found defined type",
                                      )
                                  }
                                _ =>
                                  raise SectionParseError(
                                    5, "expected resource, found defined type",
                                  )
                              }
                            None =>
                              raise SectionParseError(
                                5, "expected resource, found defined type",
                              )
                          }
                        }
                      None => ()
                    }
                  }
                None => ()
              }
              match (expected_import_type_bounds, expected_import_type_sigs) {
                (Some(bounds), Some(sigs)) => {
                  // First, map `sub resource` imports to the actual provided resource ids.
                  for kv in pending_type_args {
                    let (name, idx) = kv
                    match bounds.get(name) {
                      Some(@component.TypeBound::SubResource) =>
                        match sigs.get(name) {
                          Some(TypeSig::Resource(expected_rid)) => {
                            let actual_sig = type_sig_of_typeidx(
                              idx, type_table, resource_ids,
                            )
                            match actual_sig {
                              TypeSig::Resource(actual_rid) =>
                                rid_subst.set(expected_rid, actual_rid)
                              _ =>
                                raise SectionParseError(
                                  5, "expected resource, found defined type",
                                )
                            }
                          }
                          _ => ()
                        }
                      _ => ()
                    }
                  }
                  // Then validate `eq` type imports with resource substitution applied.
                  for kv in pending_type_args {
                    let (name, idx) = kv
                    match bounds.get(name) {
                      Some(@component.TypeBound::Eq(_)) =>
                        match sigs.get(name) {
                          Some(req0) => {
                            let req = type_sig_subst_resources(req0, rid_subst)
                            let actual = type_sig_of_typeidx(
                              idx, type_table, resource_ids,
                            )
                            if actual != req {
                              match (req, actual) {
                                (TypeSig::Resource(_), TypeSig::Resource(_)) =>
                                  raise SectionParseError(
                                    5, "resource types are not the same",
                                  )
                                (TypeSig::Resource(_), _) =>
                                  raise SectionParseError(
                                    5, "expected resource, found defined type",
                                  )
                                (_, TypeSig::Resource(_)) =>
                                  raise SectionParseError(
                                    5, "expected defined type, found resource",
                                  )
                                _ =>
                                  if type_sig_has_resource_mismatch(req, actual) {
                                    raise SectionParseError(
                                      5, "resource types are not the same",
                                    )
                                  } else {
                                    raise ComponentImportTypeMismatch(
                                      "type \{name}",
                                    )
                                  }
                              }
                            }
                          }
                          None => ()
                        }
                      _ => ()
                    }
                  }
                }
                _ => ()
              }
              // Finally validate function imports with the same resource substitution.
              match expected_import_func_sigs {
                Some(func_map) =>
                  for kv in pending_func_args {
                    let (name, idx) = kv
                    match func_map.get(name) {
                      Some(expected0) => {
                        let expected = funcsig_subst_resources(
                          expected0, rid_subst,
                        )
                        let sig_from_map = if idx >= 0 &&
                          idx < func_sig_shapes.length() {
                          func_sig_shapes[idx]
                        } else {
                          None
                        }
                        let actual_sig = match sig_from_map {
                          Some(sig) => Some(sig)
                          None =>
                            if idx >= 0 && idx < func_types.length() {
                              match func_types[idx] {
                                Some(actual) =>
                                  Some(
                                    funcsig_of_functype(
                                      actual, type_table, resource_ids,
                                    ),
                                  )
                                None => None
                              }
                            } else {
                              None
                            }
                        }
                        match actual_sig {
                          Some(actual_sig) =>
                            if actual_sig != expected {
                              if funcsig_has_resource_mismatch(
                                  expected, actual_sig,
                                ) {
                                raise SectionParseError(
                                  5, "resource types are not the same",
                                )
                              } else {
                                raise ComponentImportTypeMismatch("function")
                              }
                            }
                          None => ()
                        }
                      }
                      None => ()
                    }
                  }
                None => ()
              }

              // Propagate the component's export signature to the instantiated
              // instance so later aliasing/instantiations can validate exports.
              if component_idx >= 0 &&
                component_idx < component_export_sorts.length() {
                match component_export_sorts[component_idx] {
                  Some(exports) => {
                    let nested = if component_idx >= 0 &&
                      component_idx < component_export_instance_sigs.length() {
                      match component_export_instance_sigs[component_idx] {
                        Some(m) => m
                        None => {}
                      }
                    } else {
                      {}
                    }
                    inst_sig = Some({ exports, nested })
                  }
                  None => ()
                }
              }

              // Track exported types so `(alias export $inst "t" (type $x))` can
              // resolve resource identities (wasm-tools/resources.wast).
              if component_idx >= 0 &&
                component_idx < component_export_type_sigs.length() {
                match component_export_type_sigs[component_idx] {
                  Some(sig_map) => {
                    let out : Map[String, ExportedTypeInfo] = {}
                    let sig_out : Map[String, TypeSig] = {}
                    for kv in sig_map.iter() {
                      let (name, sig0) = kv
                      sig_out.set(
                        name,
                        type_sig_subst_resources(sig0, rid_subst),
                      )
                      match sig0 {
                        TypeSig::Resource(rid0) =>
                          match rid_subst.get(rid0) {
                            Some(actual_rid) => {
                              let mut found : Int? = None
                              for i in 0..<type_table.length() {
                                if type_sig_of_typeidx(
                                    i, type_table, resource_ids,
                                  ) ==
                                  TypeSig::Resource(actual_rid) {
                                  found = Some(i)
                                  break
                                }
                              }
                              match found {
                                Some(idx) =>
                                  out.set(name, ExportedTypeInfo::Existing(idx))
                                None =>
                                  out.set(
                                    name,
                                    ExportedTypeInfo::Resource(actual_rid),
                                  )
                              }
                            }
                            None => {
                              let rid = next_resource_id
                              next_resource_id += 1
                              rid_subst.set(rid0, rid)
                              out.set(name, ExportedTypeInfo::Resource(rid))
                            }
                          }
                        _ => {
                          let sig = type_sig_subst_resources(sig0, rid_subst)
                          let mut found : Int? = None
                          for i in 0..<type_table.length() {
                            if type_sig_of_typeidx(i, type_table, resource_ids) ==
                              sig {
                              found = Some(i)
                              break
                            }
                          }
                          match found {
                            Some(idx) =>
                              out.set(name, ExportedTypeInfo::Existing(idx))
                            None => out.set(name, ExportedTypeInfo::Opaque)
                          }
                        }
                      }
                    }
                    inst_type_map = Some(out)
                    inst_type_sig_map = Some(sig_out)
                  }
                  None => ()
                }
              }
              if component_idx >= 0 &&
                component_idx < component_export_func_sigs.length() {
                match component_export_func_sigs[component_idx] {
                  Some(sig_map) => {
                    let out : Map[String, FuncSigShape] = {}
                    for kv in sig_map.iter() {
                      let (name, sig0) = kv
                      out.set(name, funcsig_subst_resources(sig0, rid_subst))
                    }
                    inst_func_sig_map = Some(out)
                  }
                  None => ()
                }
              }
              if component_idx >= 0 &&
                component_idx < component_export_instance_type_sigs.length() {
                match component_export_instance_type_sigs[component_idx] {
                  Some(inst_map0) => {
                    let out : Map[String, Map[String, TypeSig]] = {}
                    for kv in inst_map0.iter() {
                      let (inst_name, types0) = kv
                      let types : Map[String, TypeSig] = {}
                      for kv2 in types0.iter() {
                        let (name, sig0) = kv2
                        types.set(
                          name,
                          type_sig_subst_resources(sig0, rid_subst),
                        )
                      }
                      out.set(inst_name, types)
                    }
                    inst_nested_type_sigs = Some(out)
                  }
                  None => ()
                }
              }
              if component_idx >= 0 &&
                component_idx < component_export_instance_func_sigs.length() {
                match component_export_instance_func_sigs[component_idx] {
                  Some(inst_map0) => {
                    let out : Map[String, Map[String, FuncSigShape]] = {}
                    for kv in inst_map0.iter() {
                      let (inst_name, funcs0) = kv
                      let funcs : Map[String, FuncSigShape] = {}
                      for kv2 in funcs0.iter() {
                        let (name, sig0) = kv2
                        funcs.set(
                          name,
                          funcsig_subst_resources(sig0, rid_subst),
                        )
                      }
                      out.set(inst_name, funcs)
                    }
                    inst_nested_func_sigs = Some(out)
                  }
                  None => ()
                }
              }
            }
            InlineExports(inline_exports) => {
              let map : Map[String, @component.Sort] = {}
              let mut size = 1
              let t_idxs : Array[Int] = []
              let f_idxs : Array[Int] = []
              let type_map : Map[String, ExportedTypeInfo] = {}
              let type_sig_map : Map[String, TypeSig] = {}
              let func_map : Map[String, FuncSigShape] = {}
              for ex in inline_exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
                if cfg.wit_names &&
                  parse_bracket_resource_name(ex.name) is Some(_) {
                  raise SectionParseError(
                    5, "resource used in function does not have a name in this context",
                  )
                }
                validate_extern_name_string(ex.name, cfg)
                if map.get(ex.name) is Some(_) {
                  raise DuplicateExportName(ex.name)
                }
                map.set(ex.name, ex.sortidx.sort)
                match ex.sortidx.sort {
                  @component.Sort::Type => {
                    t_idxs.push(ex.sortidx.idx)
                    type_map.set(
                      ex.name,
                      ExportedTypeInfo::Existing(ex.sortidx.idx),
                    )
                    type_sig_map.set(
                      ex.name,
                      type_sig_of_typeidx(
                        ex.sortidx.idx,
                        type_table,
                        resource_ids,
                      ),
                    )
                  }
                  @component.Sort::Func => {
                    f_idxs.push(ex.sortidx.idx)
                    let sig = if ex.sortidx.idx >= 0 &&
                      ex.sortidx.idx < func_sig_shapes.length() {
                      func_sig_shapes[ex.sortidx.idx]
                    } else {
                      None
                    }
                    match sig {
                      Some(s) => func_map.set(ex.name, s)
                      None =>
                        if ex.sortidx.idx >= 0 &&
                          ex.sortidx.idx < func_types.length() {
                          match func_types[ex.sortidx.idx] {
                            Some(ft) =>
                              func_map.set(
                                ex.name,
                                funcsig_of_functype(
                                  ft, type_table, resource_ids,
                                ),
                              )
                            None => ()
                          }
                        }
                    }
                  }
                  _ => ()
                }
                match ex.sortidx.sort {
                  @component.Sort::Instance => {
                    let delta = if ex.sortidx.idx >= 0 &&
                      ex.sortidx.idx < instance_sizes.length() {
                      instance_sizes[ex.sortidx.idx]
                    } else {
                      1
                    }
                    size = add_type_size(size, delta)
                  }
                  _ => size = add_type_size(size, 1)
                }
              }
              inst_sig = Some({ exports: map, nested: {} })
              inst_size = size
              inst_type_idxs = Some(t_idxs)
              inst_func_idxs = Some(f_idxs)
              inst_type_map = Some(type_map)
              inst_type_sig_map = Some(type_sig_map)
              inst_func_sig_map = Some(func_map)
            }
          }
          instance_sigs.push(inst_sig)
          instance_sizes.push(inst_size)
          instance_export_type_idxs.push(inst_type_idxs)
          instance_export_func_idxs.push(inst_func_idxs)
          instance_export_type_map.push(inst_type_map)
          instance_export_type_sigs.push(inst_type_sig_map)
          instance_export_func_sigs.push(inst_func_sig_map)
          instance_nested_instance_type_sigs.push(inst_nested_type_sigs)
          instance_nested_instance_func_sigs.push(inst_nested_func_sigs)
          counts.instance += 1
        }
      }
      6 => {
        let aliases = @component.parse_alias_section(s.payload) catch {
          e => raise SectionParseError(6, "\{e}")
        }
        for a in aliases {
          let mut new_core_func_ty : @types.FuncType? = None
          let mut new_core_memory_ty : @types.MemoryType? = None
          let mut new_instance_sig : InstanceSig? = None
          let mut new_instance_export_type_sigs : Map[String, TypeSig]? = None
          let mut new_instance_export_func_sigs : Map[String, FuncSigShape]? = None
          let new_instance_nested_type_sigs : Map[String, Map[String, TypeSig]]? = None
          let new_instance_nested_func_sigs : Map[
            String,
            Map[String, FuncSigShape],
          ]? = None
          let mut new_component_size = 1
          match a.target {
            Export(instance_idx, _name) =>
              if instance_idx < 0 || instance_idx >= counts.instance {
                raise InvalidInstanceIndex(instance_idx)
              }
            CoreExport(core_instance_idx, _name) =>
              if core_instance_idx < 0 ||
                core_instance_idx >= counts.core_instance {
                raise InvalidCoreInstanceIndex(core_instance_idx)
              }
            Outer(ct, idx) => {
              // `ct` is an outer depth: 0 = current component, 1 = parent, ...
              if ct < 0 || ct > type_outers.length() {
                raise SectionParseError(6, "invalid outer alias count of \{ct}")
              }
              // For aliases that target the current component, validate bounds
              // against the current in-progress index spaces.
              if ct == 0 {
                check_sortidx(
                  { sort: a.sort, idx },
                  counts,
                  type_table.length(),
                )
              }
            }
          }
          if a.sort is Component {
            match a.target {
              Outer(ct, idx) =>
                if ct == 0 {
                  if idx >= 0 && idx < component_sizes.length() {
                    new_component_size = component_sizes[idx]
                  }
                } else {
                  let depth = ct - 1
                  if depth >= 0 && depth < component_size_outers.length() {
                    let tbl = component_size_outers[depth]
                    if idx >= 0 && idx < tbl.length() {
                      new_component_size = tbl[idx]
                    }
                  }
                }
              _ => ()
            }
          }
          // If we are aliasing an instance export that has a known ascribed
          // instance type, propagate its export signature into the new
          // instance index-space entry.
          match (a.sort, a.target) {
            (@component.Sort::Instance, Export(instance_idx, name)) => {
              let parent = if instance_idx >= 0 &&
                instance_idx < instance_sigs.length() {
                instance_sigs[instance_idx]
              } else {
                None
              }
              match parent {
                Some(sig) =>
                  match sig.nested.get(name) {
                    Some(child) => new_instance_sig = Some(child)
                    None => ()
                  }
                None => ()
              }
              if instance_idx >= 0 &&
                instance_idx < instance_nested_instance_type_sigs.length() {
                match instance_nested_instance_type_sigs[instance_idx] {
                  Some(map) =>
                    match map.get(name) {
                      Some(m) => new_instance_export_type_sigs = Some(m)
                      None => ()
                    }
                  None => ()
                }
              }
              if instance_idx >= 0 &&
                instance_idx < instance_nested_instance_func_sigs.length() {
                match instance_nested_instance_func_sigs[instance_idx] {
                  Some(map) =>
                    match map.get(name) {
                      Some(m) => new_instance_export_func_sigs = Some(m)
                      None => ()
                    }
                  None => ()
                }
              }
            }
            _ => ()
          }
          match a.target {
            Export(instance_idx, name) => {
              // Keep validation robust even if our auxiliary tables lag behind
              // counts (e.g. for inline/aliased instances).
              let sig = if instance_idx >= 0 &&
                instance_idx < instance_sigs.length() {
                instance_sigs[instance_idx]
              } else {
                None
              }
              match sig {
                Some(s) =>
                  match s.exports.get(name) {
                    Some(sort) =>
                      if sort != a.sort {
                        raise AliasTargetMismatch("instance export \{name}")
                      }
                    None => raise MissingInstanceExport(instance_idx, name)
                  }
                None => ()
              }
            }
            CoreExport(core_instance_idx, name) => {
              let export_kinds = if core_instance_idx >= 0 &&
                core_instance_idx < core_instance_exports.length() {
                core_instance_exports[core_instance_idx]
              } else {
                None
              }
              match export_kinds {
                Some(map) =>
                  match map.get(name) {
                    Some(kind) =>
                      match a.sort {
                        @component.Sort::Core(core_sort) =>
                          if core_sort != kind {
                            raise AliasTargetMismatch("core export \{name}")
                          }
                        _ => raise AliasTargetMismatch("core export \{name}")
                      }
                    None =>
                      raise MissingCoreInstanceExport(core_instance_idx, name)
                  }
                None => ()
              }
            }
            Outer(_ct, _idx) => ()
          }
          // Capture core memory types for later canonical ABI checks.
          match (a.sort, a.target) {
            (@component.Sort::Core(0x00), CoreExport(core_instance_idx, name)) => {
              let export_types = if core_instance_idx >= 0 &&
                core_instance_idx < core_instance_export_types.length() {
                core_instance_export_types[core_instance_idx]
              } else {
                None
              }
              match export_types {
                Some(map) =>
                  match map.get(name) {
                    Some(CoreExternType::Func(ft)) =>
                      new_core_func_ty = Some(ft)
                    _ => ()
                  }
                None => ()
              }
            }
            (@component.Sort::Core(0x02), CoreExport(core_instance_idx, name)) => {
              let export_types = if core_instance_idx >= 0 &&
                core_instance_idx < core_instance_export_types.length() {
                core_instance_export_types[core_instance_idx]
              } else {
                None
              }
              match export_types {
                Some(map) =>
                  match map.get(name) {
                    Some(CoreExternType::Memory(mt)) =>
                      new_core_memory_ty = Some(mt)
                    _ => ()
                  }
                None => ()
              }
            }
            _ => ()
          }
          if a.sort is Type {
            let mut new_td : @component.TypeDef? = None
            let mut new_local_resource = false
            let mut new_rid : Int? = None
            let mut new_size = 1
            let mut new_depth = 1
            match a.target {
              Outer(ct, idx) =>
                if ct == 0 {
                  if idx >= 0 && idx < type_table.length() {
                    new_td = type_table[idx]
                  }
                  if idx >= 0 && idx < local_resource_types.length() {
                    new_local_resource = local_resource_types[idx]
                  }
                  if idx >= 0 && idx < resource_ids.length() {
                    new_rid = resource_ids[idx]
                  }
                  if idx >= 0 && idx < type_sizes.length() {
                    new_size = type_sizes[idx]
                  }
                  if idx >= 0 && idx < type_depths.length() {
                    new_depth = type_depths[idx]
                  }
                } else {
                  let outer_td = outer_type_of_alias(type_outers, ct, idx)
                  match outer_td {
                    Some(td) => {
                      let tbl = type_outers[ct - 1]
                      if typedef_refers_to_resource(td, tbl, {}) {
                        raise SectionParseError(
                          6, "refers to resources not defined in the current component",
                        )
                      }
                    }
                    None => ()
                  }
                  new_td = outer_td
                }
              Export(instance_idx, name) => {
                let tmap = if instance_idx >= 0 &&
                  instance_idx < instance_export_type_map.length() {
                  instance_export_type_map[instance_idx]
                } else {
                  None
                }
                match tmap {
                  Some(map) =>
                    match map.get(name) {
                      Some(ExportedTypeInfo::Existing(idx)) => {
                        if idx >= 0 && idx < type_table.length() {
                          new_td = type_table[idx]
                        }
                        if idx >= 0 && idx < local_resource_types.length() {
                          new_local_resource = local_resource_types[idx]
                        }
                        if idx >= 0 && idx < resource_ids.length() {
                          new_rid = resource_ids[idx]
                        }
                        if idx >= 0 && idx < type_sizes.length() {
                          new_size = type_sizes[idx]
                        }
                        if idx >= 0 && idx < type_depths.length() {
                          new_depth = type_depths[idx]
                        }
                      }
                      Some(ExportedTypeInfo::Resource(rid)) => {
                        new_td = Some(
                          @component.TypeDef::ResourceType(
                            -1,
                            0x7f,
                            None,
                            @component.ResourceKind::HostDefined,
                          ),
                        )
                        new_rid = Some(rid)
                      }
                      Some(ExportedTypeInfo::Opaque) => {
                        let sigmap = if instance_idx >= 0 &&
                          instance_idx < instance_export_type_sigs.length() {
                          instance_export_type_sigs[instance_idx]
                        } else {
                          None
                        }
                        match sigmap {
                          Some(sm) =>
                            match sm.get(name) {
                              Some(sig) =>
                                match
                                  typedef_of_typesig(
                                    sig, type_table, resource_ids,
                                  ) {
                                  Some(td) => new_td = Some(td)
                                  None => ()
                                }
                              None => ()
                            }
                          None => ()
                        }
                      }
                      None => ()
                    }
                  None => ()
                }
              }
              _ => ()
            }
            type_table.push(new_td)
            local_resource_types.push(new_local_resource)
            resource_ids.push(new_rid)
            type_sizes.push(new_size)
            type_depths.push(new_depth)
            match a.target {
              Export(instance_idx, _name) =>
                if interface_instance_idxs.get(instance_idx) is Some(_) {
                  named_types.set(type_table.length() - 1, 1)
                }
              _ => ()
            }
          } else {
            count_alias(a.sort, counts)
            match a.sort {
              @component.Sort::Func => {
                let mut new_ft : @component.FuncType? = None
                let mut new_sig : FuncSigShape? = None
                match a.target {
                  Outer(ct, idx) =>
                    if ct == 0 {
                      if idx >= 0 && idx < func_types.length() {
                        new_ft = func_types[idx]
                      }
                      if idx >= 0 && idx < func_sig_shapes.length() {
                        new_sig = func_sig_shapes[idx]
                      }
                    }
                  Export(instance_idx, name) => {
                    let fmap = if instance_idx >= 0 &&
                      instance_idx < instance_export_func_sigs.length() {
                      instance_export_func_sigs[instance_idx]
                    } else {
                      None
                    }
                    match fmap {
                      Some(map) =>
                        match map.get(name) {
                          Some(sig) => new_sig = Some(sig)
                          None => ()
                        }
                      None => ()
                    }
                  }
                  _ => ()
                }
                func_types.push(new_ft)
                func_sig_shapes.push(new_sig)
              }
              @component.Sort::Instance => {
                instance_sigs.push(new_instance_sig)
                instance_export_type_idxs.push(None)
                instance_export_func_idxs.push(None)
                instance_export_type_map.push(None)
                instance_export_type_sigs.push(new_instance_export_type_sigs)
                instance_export_func_sigs.push(new_instance_export_func_sigs)
                instance_nested_instance_type_sigs.push(
                  new_instance_nested_type_sigs,
                )
                instance_nested_instance_func_sigs.push(
                  new_instance_nested_func_sigs,
                )
                instance_sizes.push(1)
              }
              @component.Sort::Component => {
                component_import_sorts.push(None)
                component_import_instance_sigs.push(None)
                component_import_func_sigs.push(None)
                component_import_instance_resource_exports.push(None)
                component_import_core_module_exports.push(None)
                component_import_core_module_import_sigs.push(None)
                component_import_type_bounds.push(None)
                component_import_type_sigs.push(None)
                component_export_sorts.push(None)
                component_export_instance_sigs.push(None)
                component_export_instance_type_sigs.push(None)
                component_export_instance_func_sigs.push(None)
                component_export_type_sigs.push(None)
                component_export_func_sigs.push(None)
                component_sizes.push(new_component_size)
              }
              @component.Sort::Core(core_sort) =>
                if core_sort == 0x11 {
                  core_module_exports.push(None)
                  core_module_export_types.push(None)
                  core_module_type_imports.push(None)
                  core_module_defs.push(None)
                } else if core_sort == 0x12 {
                  core_instance_exports.push(None)
                } else if core_sort == 0x00 {
                  core_func_types.push(new_core_func_ty)
                } else if core_sort == 0x02 {
                  core_memory_types.push(new_core_memory_ty)
                } else {
                  ()
                }
              _ => ()
            }
          }
        }
      }
      8 => {
        let canons = @component.parse_canon_section(s.payload) catch {
          e => raise SectionParseError(8, "\{e}")
        }
        for c in canons {
          validate_canon(
            c,
            type_table,
            local_resource_types,
            type_table.length(),
            core_memory_types,
            core_func_types,
            func_types,
          )
          count_canon(c, counts)
          match c {
            @component.Canon::Lift(_, _, tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::FuncType(ft)) => {
                  func_types.push(Some(ft))
                  func_sig_shapes.push(
                    Some(funcsig_of_functype(ft, type_table, resource_ids)),
                  )
                }
                _ => {
                  func_types.push(None)
                  func_sig_shapes.push(None)
                }
              }
            // All non-lift canonical items append a core function to the core-func
            // index space, but we don't (yet) model their signatures here.
            _ => core_func_types.push(None)
          }
        }
      }
      9 => {
        let start = @component.parse_start_section(s.payload) catch {
          e => raise SectionParseError(9, "\{e}")
        }
        if start.func_idx < 0 || start.func_idx >= counts.func {
          raise InvalidFuncIndex(start.func_idx)
        }
      }
      _ => ()
    }
  }
  if export_size > 100000 {
    raise SectionParseError(11, "effective type size exceeds the limit")
  }
  {
    size: export_size,
    import_sorts: my_import_sorts,
    import_instance_sigs: my_import_instance_sigs,
    import_func_sigs: my_import_func_sigs,
    import_instance_resource_exports: my_import_instance_resource_exports,
    import_type_bounds: my_import_type_bounds,
    import_type_sigs: my_import_type_sigs,
    import_core_module_exports: component_import_core_module_exports_of(
      component,
    ),
    import_core_module_import_sigs: component_import_core_module_import_sigs_of(
      component,
    ),
    export_sorts: my_export_sorts,
    export_instance_sigs: my_export_instance_sigs,
    export_instance_type_sigs: my_export_instance_type_sigs,
    export_instance_func_sigs: my_export_instance_func_sigs,
    export_type_sigs: my_export_type_sigs,
    export_func_sigs: my_export_func_sigs,
  }
}

///|
pub fn validate_component(
  component : @component.Component,
) -> Unit raise ComponentValidationError {
  validate_component_with_config(
    component,
    ComponentValidationConfig::default(),
  )
}

///|
pub fn validate_component_with_config(
  component : @component.Component,
  cfg : ComponentValidationConfig,
) -> Unit raise ComponentValidationError {
  validate_component_inner(component, true, cfg, 0, [], [], []) |> ignore
}
