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
fn validate_name_bytes(name : Bytes) -> Unit raise ComponentValidationError {
  if !is_kebab_case(name) && !is_package_name(name) {
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
fn validate_extern_name_string(
  name : String,
) -> Unit raise ComponentValidationError {
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
    Lower(_, _) => counts.core_func += 1
    ResourceNew(_) => ()
    ResourceDrop(_) => ()
    ResourceRep(_) => ()
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
        Some(@component.TypeDef::DefValType(_)) => ()
        Some(@component.TypeDef::ResourceType(_, _, _)) => ()
        Some(_) => raise TypeIndexNotDefinedType(idx)
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
fn validate_typedef(
  td : @component.TypeDef,
  type_outers : Array[Array[@component.TypeDef?]],
  core_type_outers : Array[Array[Map[String, Int]?]],
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
    ResourceType(_, _, _) => ()
    ComponentType(decls) => {
      // Component type declarations define their own internal type/core-type
      // index spaces referenced by later imports/exports within the same type.
      let local_type_table : Array[@component.TypeDef?] = []
      let mut local_core_type_bound = 0
      let seen_imports : Map[String, String] = {}
      let seen_exports : Map[String, String] = {}
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
            } else {
              local_core_type_exports.push(None)
              local_core_type_bound += 1
            }
          @component.ComponentDecl::Type(t) => {
            validate_typedef(
              t,
              [local_type_table] + type_outers,
              [local_core_type_exports] + core_type_outers,
            )
            local_type_table.push(Some(t))
          }
          @component.ComponentDecl::Import(name, desc) => {
            validate_extern_name_string(name)
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
            if desc is Type(_) {
              local_type_table.push(None)
            }
          }
          @component.ComponentDecl::Export(name, desc) => {
            validate_extern_name_string(name)
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
            if desc is Type(_) {
              local_type_table.push(None)
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
              [local_type_table] + type_outers,
              [local_core_type_exports] + core_type_outers,
            )
            local_type_table.push(Some(t))
          }
          @component.InstanceDecl::Export(name, desc) => {
            validate_extern_name_string(name)
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
        validate_extern_name_string(p.label)
        let key = ascii_lower_key(p.label)
        match seen_params.get(key) {
          Some(prev) => raise FuncParamNameConflict(p.label, prev)
          None => seen_params.set(key, p.label)
        }
        validate_valtype(p.ty, type_table)
      }
      match ft.result {
        Some(r) => validate_valtype(r, type_table)
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
fn valtype_needs_memory(ty : @component.ValType) -> Bool {
  match ty {
    Prim(p) =>
      match p {
        @component.PrimValType::String | @component.PrimValType::ErrorContext =>
          true
        _ => false
      }
    TypeIdx(_) => false
  }
}

///|
fn functype_needs_memory(ft : @component.FuncType) -> Bool {
  for p in ft.params {
    if valtype_needs_memory(p.ty) {
      return true
    }
  }
  match ft.result {
    Some(r) => valtype_needs_memory(r)
    None => false
  }
}

///|
fn functype_needs_realloc_for_lift(ft : @component.FuncType) -> Bool {
  // For canon lift, `realloc` is required when the wrapper must write a
  // component value (like `string`) into core linear memory to pass as a param.
  for p in ft.params {
    if valtype_needs_memory(p.ty) {
      return true
    }
  }
  false
}

///|
fn functype_needs_realloc_for_lower(ft : @component.FuncType) -> Bool {
  // For canon lower, `realloc` is required when the wrapper must write a
  // component value into core linear memory as a result.
  match ft.result {
    Some(r) => valtype_needs_memory(r)
    None => false
  }
}

///|
fn core_valtypes_for_component_valtype(
  ty : @component.ValType,
) -> Array[@types.ValueType]? {
  match ty {
    @component.ValType::TypeIdx(_) => None
    @component.ValType::Prim(p) =>
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
        // Strings/results need canonical ABI lowering/lifting rules (ptr/len,
        // return pointers, etc). We'll validate these once the full ABI
        // machinery is implemented.
        @component.PrimValType::String | @component.PrimValType::ErrorContext =>
          None
      }
  }
}

///|
fn core_functype_for_component_functype(
  ft : @component.FuncType,
) -> @types.FuncType? {
  let params : Array[@types.ValueType] = []
  for p in ft.params {
    match core_valtypes_for_component_valtype(p.ty) {
      Some(ts) =>
        for t in ts {
          params.push(t)
        }
      None => return None
    }
  }
  let results : Array[@types.ValueType] = []
  match ft.result {
    None => ()
    Some(r) =>
      match core_valtypes_for_component_valtype(r) {
        Some(ts) =>
          for t in ts {
            results.push(t)
          }
        None => return None
      }
  }
  Some({ params, results })
}

///|
fn validate_canon(
  c : @component.Canon,
  type_table : Array[@component.TypeDef?],
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
      if core_func_idx < 0 || core_func_idx >= core_func_types.length() {
        raise InvalidCoreFuncIndex(core_func_idx)
      }
      check_typeidx(tyidx, type_bound)
      let td = type_table[tyidx]
      match td {
        Some(@component.TypeDef::FuncType(ft)) => {
          if canon_has_async(opts) && !ft.is_async {
            raise CanonAsyncTypeMismatch(tyidx)
          }
          if functype_needs_memory(ft) {
            if !canon_has_memory(opts) {
              raise MissingCanonOption("memory")
            }
          }
          if functype_needs_realloc_for_lift(ft) {
            if !canon_has_realloc(opts) {
              raise MissingCanonOption("realloc")
            }
          }
          match
            (
              core_func_types[core_func_idx],
              core_functype_for_component_functype(ft),
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
      if func_idx < 0 || func_idx >= func_types.length() {
        raise InvalidFuncIndex(func_idx)
      }
      match func_types[func_idx] {
        Some(ft) => {
          if functype_needs_memory(ft) && !canon_has_memory(opts) {
            raise MissingCanonOption("memory")
          }
          if functype_needs_realloc_for_lower(ft) && !canon_has_realloc(opts) {
            raise MissingCanonOption("realloc")
          }
        }
        None => ()
      }
    }
    ResourceNew(tyidx) => check_typeidx(tyidx, type_bound)
    ResourceDrop(tyidx) => check_typeidx(tyidx, type_bound)
    ResourceRep(tyidx) => check_typeidx(tyidx, type_bound)
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
    _ => 1
  }
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
) -> Int raise ComponentValidationError {
  let counts = Counts::new()
  let type_table : Array[@component.TypeDef?] = []
  let type_sizes : Array[Int] = []
  // Approximate export-signature size (used for wasm-tools' very-nested.wast).
  let component_sizes : Array[Int] = []
  let instance_sizes : Array[Int] = []
  let mut export_size = 1
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
  let component_import_core_module_exports : Array[
    Map[String, Map[String, Int]]?,
  ] = []
  let component_export_sorts : Array[Map[String, @component.Sort]?] = []
  let component_export_instance_sigs : Array[Map[String, InstanceSig]?] = []
  let instance_sigs : Array[InstanceSig?] = []
  let func_types : Array[@component.FuncType?] = []
  let mut imported_funcs = 0
  let seen_import_names : Map[String, Int] = {}
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
        let nested_size = validate_component_inner(
          nested,
          false,
          cfg,
          depth + 1,
          [type_table] + type_outers,
          [counts.core_type] + core_type_bound_outers,
          [component_sizes] + component_size_outers,
        )
        let (imp_sorts, imp_inst_sigs, exp_sorts, exp_inst_sigs) = component_signature(
          nested,
        )
        component_import_sorts.push(Some(imp_sorts))
        component_import_instance_sigs.push(Some(imp_inst_sigs))
        component_import_core_module_exports.push(
          Some(component_import_core_module_exports_of(nested)),
        )
        component_export_sorts.push(Some(exp_sorts))
        component_export_instance_sigs.push(Some(exp_inst_sigs))
        component_sizes.push(nested_size)
        counts.component += 1
      }
      7 => {
        // Definitions extend the type index space.
        let defs = @component.parse_type_section(s.payload) catch {
          e => raise SectionParseError(7, "\{e}")
        }
        for d in defs {
          // This is still a subset: we only allow referencing earlier types.
          validate_typedef(d, [type_table], [core_type_exports])
          let size = effective_typedef_size(d, type_sizes)
          if size > 100000 {
            raise SectionParseError(7, "effective type size exceeds the limit")
          }
          type_table.push(Some(d))
          type_sizes.push(size)
        }
      }
      10 => {
        let imports = @component.parse_import_section(s.payload) catch {
          e => raise SectionParseError(10, "\{e}")
        }
        for i in imports {
          validate_import_name(i.name, cfg)
          match importname_to_string(i.name) {
            Some(name) =>
              if seen_import_names.get(name) is Some(_) {
                raise DuplicateImportName(name)
              } else {
                seen_import_names.set(name, 1)
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
                Some(@component.TypeDef::FuncType(ft)) =>
                  func_types.push(Some(ft))
                _ => func_types.push(None)
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
              match type_table[tyidx] {
                Some(td) =>
                  instance_sigs.push(
                    Some(instancetype_sig_of_typedef(td, type_table, {})),
                  )
                None => instance_sigs.push(None)
              }
              // Imported instances contribute an entry to the instance index space.
              // We don't have a precise effective-size model here; treat as 1.
              instance_sizes.push(1)
            }
            _ => ()
          }
          if is_root && i.desc is ComponentType(_) {
            raise UnsupportedComponentImport
          }
          if i.desc is FuncType(_) {
            imported_funcs += 1
          }
          if i.desc is ComponentType(_) {
            component_import_sorts.push(None)
            component_import_instance_sigs.push(None)
            component_import_core_module_exports.push(None)
            component_export_sorts.push(None)
            component_export_instance_sigs.push(None)
            // Imported component size is unknown; treat as 1.
            component_sizes.push(1)
          }
          if i.desc is Type(_) {
            type_table.push(None)
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
          if is_root && e.sortidx.sort is Component {
            raise UnsupportedComponentExport
          }
          if is_root && e.sortidx.sort is Func && e.sortidx.idx < imported_funcs {
            raise ExportedImportedFunc(e.sortidx.idx)
          }
          check_sortidx(e.sortidx, counts, type_table.length())
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
              } else {
                raise AscribedExportTypeIncompatible
              }
            (_sort, Some(d)) =>
              if sort_of_externdesc(d) != e.sortidx.sort {
                raise AscribedExportTypeIncompatible
              }
            _ => ()
          }
          if e.sortidx.sort is Type {
            type_table.push(None)
          } else {
            count_alias(e.sortidx.sort, counts)
            match e.sortidx.sort {
              @component.Sort::Func =>
                if e.sortidx.idx >= 0 && e.sortidx.idx < func_types.length() {
                  func_types.push(func_types[e.sortidx.idx])
                } else {
                  func_types.push(None)
                }
              @component.Sort::Instance =>
                if e.sortidx.idx >= 0 && e.sortidx.idx < instance_sigs.length() {
                  instance_sigs.push(instance_sigs[e.sortidx.idx])
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < instance_sizes.length() {
                    instance_sizes.push(instance_sizes[e.sortidx.idx])
                  } else {
                    instance_sizes.push(1)
                  }
                } else {
                  instance_sigs.push(None)
                  instance_sizes.push(1)
                }
              @component.Sort::Component => {
                component_import_sorts.push(None)
                component_import_instance_sigs.push(None)
                component_import_core_module_exports.push(None)
                component_export_sorts.push(None)
                component_export_instance_sigs.push(None)
                component_sizes.push(1)
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
                  core_module_defs.push(None)
                } else if core_sort == 0x12 {
                  if e.sortidx.idx >= 0 &&
                    e.sortidx.idx < core_instance_exports.length() {
                    core_instance_exports.push(
                      core_instance_exports[e.sortidx.idx],
                    )
                  } else {
                    core_instance_exports.push(None)
                  }
                } else {
                  ()
                }
              _ => ()
            }
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
              let expected_import_core_modules = if component_idx >= 0 &&
                component_idx < component_import_core_module_exports.length() {
                component_import_core_module_exports[component_idx]
              } else {
                None
              }
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
                        }
                    }
                  None => ()
                }
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
            }
            InlineExports(inline_exports) => {
              let map : Map[String, @component.Sort] = {}
              let mut size = 1
              for ex in inline_exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
                validate_extern_name_string(ex.name)
                if map.get(ex.name) is Some(_) {
                  raise DuplicateExportName(ex.name)
                }
                map.set(ex.name, ex.sortidx.sort)
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
            }
          }
          instance_sigs.push(inst_sig)
          instance_sizes.push(inst_size)
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
            match a.target {
              Outer(ct, idx) =>
                type_table.push(
                  component_outer_type_of_alias(
                    type_table, type_outers, ct, idx,
                  ),
                )
              _ => type_table.push(None)
            }
          } else {
            count_alias(a.sort, counts)
            match a.sort {
              @component.Sort::Func => func_types.push(None)
              @component.Sort::Instance => {
                instance_sigs.push(new_instance_sig)
                instance_sizes.push(1)
              }
              @component.Sort::Component => {
                component_import_sorts.push(None)
                component_import_instance_sigs.push(None)
                component_import_core_module_exports.push(None)
                component_export_sorts.push(None)
                component_export_instance_sigs.push(None)
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
            type_table.length(),
            core_memory_types,
            core_func_types,
            func_types,
          )
          count_canon(c, counts)
          match c {
            @component.Canon::Lower(_, _) => core_func_types.push(None)
            @component.Canon::Lift(_, _, tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::FuncType(ft)) =>
                  func_types.push(Some(ft))
                _ => func_types.push(None)
              }
            _ => ()
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
  export_size
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
