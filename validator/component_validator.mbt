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
  InvalidFuncIndex(Int)
  InvalidValueIndex(Int)
  InvalidComponentIndex(Int)
  InvalidInstanceIndex(Int)
  InvalidCoreFuncIndex(Int)
  InvalidCoreModuleIndex(Int)
  InvalidCoreInstanceIndex(Int)
  InvalidCoreTypeIndex(Int)
  InvalidCoreTableIndex(Int)
  InvalidCoreMemoryIndex(Int)
  InvalidCoreGlobalIndex(Int)
  InvalidCoreTagIndex(Int)
  DuplicateName(String)
  DuplicateCanonOption(String)
  MissingCanonOption(String)
  CanonExpectedFuncType(Int)
  CanonAsyncTypeMismatch(Int)
  UnsupportedCoreSort(Int)
  UnsupportedComponentImport
  UnsupportedComponentExport
  ExportedImportedFunc(Int)
  InvalidKebabName(String)
  SectionParseError(Int, String)
  CoreModuleError(String)
} derive(Show, Eq)

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
fn validate_name_bytes(name : Bytes) -> Unit raise ComponentValidationError {
  // NOTE: `Bytes::to_string()` prints a debug representation like `b"..."`.
  // For validation we operate on raw ASCII bytes instead.

  fn is_ascii_digit(cu : Int) -> Bool {
    cu >= 0x30 && cu <= 0x39
  }

  fn is_ascii_lower(cu : Int) -> Bool {
    cu >= 0x61 && cu <= 0x7A
  }

  fn is_ascii_upper(cu : Int) -> Bool {
    cu >= 0x41 && cu <= 0x5A
  }

  fn is_ascii_letter(cu : Int) -> Bool {
    is_ascii_lower(cu) || is_ascii_upper(cu)
  }

  fn kebab_range(
    bytes : Bytes,
    start : Int,
    end : Int,
    lower_only : Bool,
  ) -> Bool {
    if end <= start {
      return false
    }
    let mut prev_dash = false
    for i in start..<end {
      let cu = bytes[i].to_int()
      if cu >= 0x80 {
        return false
      }
      if i == start {
        if lower_only {
          if !is_ascii_lower(cu) {
            return false
          }
        } else if !is_ascii_letter(cu) {
          return false
        }
        continue
      }
      if cu == 0x2D { // '-'
        if prev_dash {
          return false
        }
        prev_dash = true
      } else if (lower_only && (is_ascii_lower(cu) || is_ascii_digit(cu))) ||
        (!lower_only && (is_ascii_letter(cu) || is_ascii_digit(cu))) {
        prev_dash = false
      } else {
        return false
      }
    }
    !prev_dash
  }

  fn find_byte(bytes : Bytes, needle : Int, start : Int, end : Int) -> Int? {
    for i in start..<end {
      if bytes[i].to_int() == needle {
        return Some(i)
      }
    }
    None
  }

  fn semver_range(bytes : Bytes, start : Int, end : Int) -> Bool {
    if end <= start {
      return false
    }
    fn scan_digits(bytes : Bytes, i : Int, end : Int) -> Int? {
      let mut j = i
      while j < end && is_ascii_digit(bytes[j].to_int()) {
        j += 1
      }
      if j == i {
        None
      } else {
        Some(j)
      }
    }

    let mut i = start
    let major_end = match scan_digits(bytes, i, end) {
      Some(j) => j
      None => return false
    }
    i = major_end
    if i >= end || bytes[i].to_int() != 0x2E { // '.'
      return false
    }
    i += 1
    let minor_end = match scan_digits(bytes, i, end) {
      Some(j) => j
      None => return false
    }
    i = minor_end
    if i >= end || bytes[i].to_int() != 0x2E {
      return false
    }
    i += 1
    let patch_end = match scan_digits(bytes, i, end) {
      Some(j) => j
      None => return false
    }
    i = patch_end
    fn ident_seg(bytes : Bytes, i : Int, end : Int) -> Int? {
      let mut j = i
      while j < end {
        let cu = bytes[j].to_int()
        if cu >= 0x80 {
          break
        }
        if is_ascii_letter(cu) || is_ascii_digit(cu) || cu == 0x2D {
          j += 1
        } else {
          break
        }
      }
      if j == i {
        None
      } else {
        Some(j)
      }
    }

    // prerelease
    if i < end && bytes[i].to_int() == 0x2D { // '-'
      i += 1
      if i >= end {
        return false
      }
      while true {
        let next = match ident_seg(bytes, i, end) {
          Some(j) => j
          None => return false
        }
        i = next
        if i < end && bytes[i].to_int() == 0x2E { // '.'
          i += 1
          if i >= end {
            return false
          }
          continue
        }
        break
      }
    }

    // build metadata
    if i < end && bytes[i].to_int() == 0x2B { // '+'
      i += 1
      if i >= end {
        return false
      }
      while true {
        let next = match ident_seg(bytes, i, end) {
          Some(j) => j
          None => return false
        }
        i = next
        if i < end && bytes[i].to_int() == 0x2E { // '.'
          i += 1
          if i >= end {
            return false
          }
          continue
        }
        break
      }
    }
    i == end
  }

  fn validate_plain(bytes : Bytes) -> Bool {
    kebab_range(bytes, 0, bytes.length(), false)
  }

  fn validate_pkg_interface(bytes : Bytes) -> Bool {
    // namespace:package/interface[@semver]
    let len = bytes.length()
    let base_end = match find_byte(bytes, 0x40, 0, len) { // '@'
      Some(i) => i
      None => len
    }
    let colon = match find_byte(bytes, 0x3A, 0, base_end) { // ':'
      Some(i) => i
      None => return false
    }
    if find_byte(bytes, 0x3A, colon + 1, base_end) is Some(_) {
      return false
    }
    let slash = match find_byte(bytes, 0x2F, colon + 1, base_end) { // '/'
      Some(i) => i
      None => return false
    }
    if find_byte(bytes, 0x2F, slash + 1, base_end) is Some(_) {
      return false
    }
    if !kebab_range(bytes, 0, colon, true) ||
      !kebab_range(bytes, colon + 1, slash, true) ||
      !kebab_range(bytes, slash + 1, base_end, true) {
      return false
    }
    if base_end != len {
      let vs_start = base_end + 1
      if vs_start >= len {
        return false
      }
      semver_range(bytes, vs_start, len)
    } else {
      true
    }
  }

  fn match_prefix(bytes : Bytes, prefix : String) -> Int? {
    let n = prefix.length()
    if bytes.length() < n {
      return None
    }
    for i in 0..<n {
      if bytes[i].to_int() != prefix.code_unit_at(i).to_int() {
        return None
      }
    }
    Some(n)
  }

  fn validate_dep_string(bytes : Bytes) -> Bool {
    let start = match match_prefix(bytes, "unlocked-dep=<") {
      Some(n) => n
      None =>
        match match_prefix(bytes, "locked-dep=<") {
          Some(n) => n
          None => return false
        }
    }
    let len = bytes.length()
    fn find_subseq(
      bytes : Bytes,
      needle : String,
      start : Int,
      end : Int,
    ) -> Int? {
      let n = needle.length()
      if n == 0 || start + n > end {
        return None
      }
      for i in start..<(end - n + 1) {
        let mut ok = true
        for j in 0..<n {
          if bytes[i + j].to_int() != needle.code_unit_at(j).to_int() {
            ok = false
            break
          }
        }
        if ok {
          return Some(i)
        }
      }
      None
    }

    // `>=` constraints in unlocked-dep include `>` bytes, so we cannot just
    // take the first `>` after the prefix. Instead:
    // - if there's an integrity suffix, the dep-spec ends at the `>` right
    //   before the comma.
    // - otherwise, it must end at the final `>` byte.
    let integrity_prefix = ",integrity=<"
    let end = match find_subseq(bytes, integrity_prefix, start, len) {
      Some(idx) => {
        if idx == 0 || bytes[idx - 1].to_int() != 0x3E { // '>'
          return false
        }
        // Validate integrity suffix.
        let p_len = integrity_prefix.length()
        if idx + p_len + 1 >= len {
          return false
        }
        if bytes[len - 1].to_int() != 0x3E { // '>'
          return false
        }
        idx - 1
      }
      None => {
        if len == 0 || bytes[len - 1].to_int() != 0x3E {
          return false
        }
        len - 1
      }
    }
    // Parse inside `namespace:package` with optional `@...`.
    let inside_start = start
    let inside_end = end
    let at = find_byte(bytes, 0x40, inside_start, inside_end) // '@'
    let np_end = match at {
      Some(i) => i
      None => inside_end
    }
    let colon = match find_byte(bytes, 0x3A, inside_start, np_end) {
      Some(i) => i
      None => return false
    }
    if find_byte(bytes, 0x3A, colon + 1, np_end) is Some(_) {
      return false
    }
    if !kebab_range(bytes, inside_start, colon, true) ||
      !kebab_range(bytes, colon + 1, np_end, true) {
      return false
    }
    match at {
      None => true
      Some(at_pos) => {
        let vs_start = at_pos + 1
        if vs_start >= inside_end {
          return false
        }
        // `*` or `{...}` ranges or plain semver.
        if vs_start + 1 == inside_end && bytes[vs_start].to_int() == 0x2A { // '*'
          true
        } else if bytes[vs_start].to_int() == 0x7B && // '{'
          bytes[inside_end - 1].to_int() == 0x7D { // '}'
          let mut i = vs_start + 1
          let mut saw = false
          while i < inside_end - 1 {
            while i < inside_end - 1 && bytes[i].to_int() == 0x20 {
              i += 1
            }
            if i >= inside_end - 1 {
              break
            }
            saw = true
            let op_ge = i + 1 < inside_end - 1 &&
              bytes[i].to_int() == 0x3E && // '>'
              bytes[i + 1].to_int() == 0x3D // '='
            let op_lt = bytes[i].to_int() == 0x3C // '<'
            if op_ge {
              i += 2
            } else if op_lt {
              i += 1
            } else {
              return false
            }
            let ver_start = i
            while i < inside_end - 1 && bytes[i].to_int() != 0x20 {
              i += 1
            }
            if !semver_range(bytes, ver_start, i) {
              return false
            }
          }
          saw
        } else {
          semver_range(bytes, vs_start, inside_end)
        }
      }
    }
  }

  let ok = validate_plain(name) ||
    validate_pkg_interface(name) ||
    validate_dep_string(name)
  if !ok {
    raise InvalidKebabName(name.to_string())
  }
}

///|
fn validate_name_string_ascii(
  name : String,
) -> Unit raise ComponentValidationError {
  let bytes : Array[Byte] = []
  for i in 0..<name.length() {
    bytes.push(name.code_unit_at(i).to_byte())
  }
  validate_name_bytes(Bytes::from_array(bytes))
}

///|
fn validate_versionsuffix_bytes(vs : Bytes) -> Bool {
  fn is_ascii_digit(cu : Int) -> Bool {
    cu >= 0x30 && cu <= 0x39
  }

  fn is_ascii_lower(cu : Int) -> Bool {
    cu >= 0x61 && cu <= 0x7A
  }

  fn is_ascii_upper(cu : Int) -> Bool {
    cu >= 0x41 && cu <= 0x5A
  }

  fn is_ascii_letter(cu : Int) -> Bool {
    is_ascii_lower(cu) || is_ascii_upper(cu)
  }

  fn scan_digits(bytes : Bytes, i : Int, end : Int) -> Int? {
    let mut j = i
    while j < end && is_ascii_digit(bytes[j].to_int()) {
      j += 1
    }
    if j == i {
      None
    } else {
      Some(j)
    }
  }

  fn ident_seg(bytes : Bytes, i : Int, end : Int) -> Int? {
    let mut j = i
    while j < end {
      let cu = bytes[j].to_int()
      if cu >= 0x80 {
        break
      }
      if is_ascii_letter(cu) || is_ascii_digit(cu) || cu == 0x2D {
        j += 1
      } else {
        break
      }
    }
    if j == i {
      None
    } else {
      Some(j)
    }
  }

  let start = 0
  let end = vs.length()
  if end <= start {
    return false
  }
  let mut i = start
  let major_end = match scan_digits(vs, i, end) {
    Some(j) => j
    None => return false
  }
  i = major_end
  if i >= end || vs[i].to_int() != 0x2E {
    return false
  }
  i += 1
  let minor_end = match scan_digits(vs, i, end) {
    Some(j) => j
    None => return false
  }
  i = minor_end
  if i >= end || vs[i].to_int() != 0x2E {
    return false
  }
  i += 1
  let patch_end = match scan_digits(vs, i, end) {
    Some(j) => j
    None => return false
  }
  i = patch_end
  if i < end && vs[i].to_int() == 0x2D {
    i += 1
    if i >= end {
      return false
    }
    while true {
      let next = match ident_seg(vs, i, end) {
        Some(j) => j
        None => return false
      }
      i = next
      if i < end && vs[i].to_int() == 0x2E {
        i += 1
        if i >= end {
          return false
        }
        continue
      }
      break
    }
  }
  if i < end && vs[i].to_int() == 0x2B {
    i += 1
    if i >= end {
      return false
    }
    while true {
      let next = match ident_seg(vs, i, end) {
        Some(j) => j
        None => return false
      }
      i = next
      if i < end && vs[i].to_int() == 0x2E {
        i += 1
        if i >= end {
          return false
        }
        continue
      }
      break
    }
  }
  i == end
}

///|
fn validate_import_name(
  name : @component.ImportName,
) -> Unit raise ComponentValidationError {
  match name {
    Plain(bytes) => validate_name_bytes(bytes)
    WithVersion(bytes, vs) => {
      validate_name_bytes(bytes)
      if !validate_versionsuffix_bytes(vs) {
        raise InvalidKebabName(vs.to_string())
      }
    }
  }
}

///|
fn validate_export_name(
  name : @component.ExportName,
) -> Unit raise ComponentValidationError {
  match name {
    Plain(bytes) => validate_name_bytes(bytes)
    WithVersion(bytes, vs) => {
      validate_name_bytes(bytes)
      if !validate_versionsuffix_bytes(vs) {
        raise InvalidKebabName(vs.to_string())
      }
    }
  }
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
  type_bound : Int,
) -> Unit raise ComponentValidationError {
  match ty {
    TypeIdx(idx) => check_typeidx(idx, type_bound)
    Prim(_) => ()
  }
}

///|
fn validate_typedef(
  td : @component.TypeDef,
  type_bound : Int,
  core_type_bound : Int,
) -> Unit raise ComponentValidationError {
  match td {
    DefValType(_) => ()
    ComponentType(decls) => {
      // Component type declarations define a local type index space, similar to
      // instance types. Keep this minimal: bounds checks + name validity +
      // duplicate name rejection.
      let mut local_type_bound = 0
      let seen : Map[String, Unit] = {}
      for d in decls {
        match d {
          @component.ComponentDecl::Type(t) => {
            validate_typedef(t, local_type_bound, core_type_bound)
            local_type_bound += 1
          }
          @component.ComponentDecl::Import(name, desc)
          | @component.ComponentDecl::Export(name, desc) => {
            validate_name_string_ascii(name)
            if seen.contains(name) {
              raise DuplicateName(name)
            }
            seen.set(name, ())
            validate_externdesc(desc, local_type_bound, core_type_bound)
            // Like the component import/export sections, importing/exporting a
            // type introduces a new local type index.
            if desc is Type(_) {
              local_type_bound += 1
            }
          }
        }
      }
    }
    InstanceTypeEmpty => ()
    InstanceType(decls) => {
      // Instance type declarations define their own internal type index space
      // which is referenced by later exports within the same instance type.
      let mut local_type_bound = 0
      let seen : Map[String, Unit] = {}
      for d in decls {
        match d {
          @component.InstanceDecl::Type(t) => {
            validate_typedef(t, local_type_bound, core_type_bound)
            local_type_bound += 1
          }
          @component.InstanceDecl::Export(name, desc) => {
            validate_name_string_ascii(name)
            if seen.contains(name) {
              raise DuplicateName(name)
            }
            seen.set(name, ())
            validate_externdesc(desc, local_type_bound, core_type_bound)
            // Like the component export section, exporting a type introduces
            // a fresh type index in this instance type's local type space.
            if desc is Type(_) {
              local_type_bound += 1
            }
          }
        }
      }
    }
    FuncType(ft) => {
      for p in ft.params {
        validate_valtype(p.ty, type_bound)
      }
      match ft.result {
        Some(r) => validate_valtype(r, type_bound)
        None => ()
      }
    }
  }
}

///|
fn validate_externdesc(
  desc : @component.ExternDesc,
  type_bound : Int,
  core_type_bound : Int,
) -> Unit raise ComponentValidationError {
  match desc {
    CoreModuleType(tyidx) => check_typeidx(tyidx, core_type_bound)
    FuncType(tyidx) => check_typeidx(tyidx, type_bound)
    ComponentType(tyidx) => check_typeidx(tyidx, type_bound)
    InstanceType(tyidx) => check_typeidx(tyidx, type_bound)
    Type(b) =>
      match b {
        Eq(tyidx) => check_typeidx(tyidx, type_bound)
        SubResource => ()
      }
    Value(b) =>
      match b {
        Eq(_v) => ()
        Type(vt) => validate_valtype(vt, type_bound)
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
/// For `canon lift`, `realloc` is only required when we need to allocate guest
/// memory to marshal component->core arguments (e.g. string/error-context params).
/// Returning strings/error-context can be handled by reading from memory without
/// allocation (the core function returns ptr/len or a pointer to a record).
fn functype_needs_realloc_for_lift(ft : @component.FuncType) -> Bool {
  for p in ft.params {
    if valtype_needs_memory(p.ty) {
      return true
    }
  }
  false
}

///|
fn validate_canon(
  c : @component.Canon,
  type_table : Array[@component.TypeDef?],
  type_bound : Int,
) -> Unit raise ComponentValidationError {
  match c {
    Lift(_core_func, opts, tyidx) => {
      validate_canon_opts(opts)
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
          if functype_needs_realloc_for_lift(ft) && !canon_has_realloc(opts) {
            raise MissingCanonOption("realloc")
          }
        }
        None => ()
        _ => raise CanonExpectedFuncType(tyidx)
      }
    }
    Lower(_func, opts) => validate_canon_opts(opts)
    ResourceNew(tyidx) => check_typeidx(tyidx, type_bound)
    ResourceDrop(tyidx) => check_typeidx(tyidx, type_bound)
    ResourceRep(tyidx) => check_typeidx(tyidx, type_bound)
  }
}

///|
/// Validate a parsed component (partial).
fn validate_component_inner(
  component : @component.Component,
  is_root : Bool,
) -> Unit raise ComponentValidationError {
  let counts = Counts::new()
  let type_table : Array[@component.TypeDef?] = []
  let mut imported_funcs = 0
  for s in component.binary.sections {
    match s.id {
      // Core module/instance/type sections each declare a single core item.
      1 => {
        // Validate embedded core modules using the existing core validator.
        let core_mod = @parser.parse_module(s.payload) catch {
          e => raise CoreModuleError("parse core module: \{e}")
        }
        validate_module(core_mod) catch {
          e => raise CoreModuleError("validate core module: \{e}")
        }
        counts.core_module += 1
      }
      2 => {
        let core_instances = @component.parse_core_instance_section(s.payload) catch {
          e => raise SectionParseError(2, "\{e}")
        }
        for inst in core_instances {
          match inst.expr {
            @component.CoreInstanceExpr::Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= counts.core_module {
                raise InvalidCoreModuleIndex(module_idx)
              }
              for a in args {
                check_sortidx(a.sortidx, counts, type_table.length())
              }
            }
            @component.CoreInstanceExpr::InlineExports(exports) =>
              for ex in exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
              }
          }
          counts.core_instance += 1
        }
      }
      3 => counts.core_type += 1
      4 => {
        // Nested component payloads are also component binaries.
        let nested = @component.parse_component(s.payload) catch {
          e => raise SectionParseError(4, "parse nested component: \{e}")
        }
        validate_component_inner(nested, false)
        counts.component += 1
      }
      7 => {
        // Definitions extend the type index space.
        let defs = @component.parse_type_section(s.payload) catch {
          e => raise SectionParseError(7, "\{e}")
        }
        for d in defs {
          // This is still a subset: we only allow referencing earlier types.
          validate_typedef(d, type_table.length(), counts.core_type)
          type_table.push(Some(d))
        }
      }
      10 => {
        let imports = @component.parse_import_section(s.payload) catch {
          e => raise SectionParseError(10, "\{e}")
        }
        for i in imports {
          validate_import_name(i.name)
          // Import type references must be in-bounds at the point they appear.
          validate_externdesc(i.desc, type_table.length(), counts.core_type)
          if is_root && i.desc is ComponentType(_) {
            raise UnsupportedComponentImport
          }
          if i.desc is FuncType(_) {
            imported_funcs += 1
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
          validate_export_name(e.name)
          if is_root && e.sortidx.sort is Component {
            raise UnsupportedComponentExport
          }
          if is_root && e.sortidx.sort is Func && e.sortidx.idx < imported_funcs {
            raise ExportedImportedFunc(e.sortidx.idx)
          }
          check_sortidx(e.sortidx, counts, type_table.length())
          match e.desc {
            Some(d) =>
              validate_externdesc(d, type_table.length(), counts.core_type)
            None => ()
          }
          if e.sortidx.sort is Type {
            type_table.push(None)
          } else {
            count_alias(e.sortidx.sort, counts)
          }
        }
      }
      5 => {
        let instances = @component.parse_instance_section(s.payload) catch {
          e => raise SectionParseError(5, "\{e}")
        }
        for inst in instances {
          match inst.expr {
            Instantiate(component_idx, args) => {
              if component_idx < 0 || component_idx >= counts.component {
                raise InvalidComponentIndex(component_idx)
              }
              for a in args {
                check_sortidx(a.sortidx, counts, type_table.length())
              }
            }
            InlineExports(exports) =>
              for ex in exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
              }
          }
          counts.instance += 1
        }
      }
      6 => {
        let aliases = @component.parse_alias_section(s.payload) catch {
          e => raise SectionParseError(6, "\{e}")
        }
        for a in aliases {
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
            Outer(_ct, _idx) => ()
          }
          if a.sort is Type {
            type_table.push(None)
          } else {
            count_alias(a.sort, counts)
          }
        }
      }
      8 => {
        let canons = @component.parse_canon_section(s.payload) catch {
          e => raise SectionParseError(8, "\{e}")
        }
        for c in canons {
          validate_canon(c, type_table, type_table.length())
          count_canon(c, counts)
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
}

///|
pub fn validate_component(
  component : @component.Component,
) -> Unit raise ComponentValidationError {
  validate_component_inner(component, true)
}
