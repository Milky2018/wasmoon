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
  DuplicateCanonOption(String)
  MissingCanonOption(String)
  CanonExpectedFuncType(Int)
  CanonAsyncTypeMismatch(Int)
  UnsupportedCoreSort(Int)
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
        0x05 =>
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
        0x05 => counts.core_type += 1
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
) -> Unit raise ComponentValidationError {
  match td {
    DefValType(_) => ()
    ComponentTypeEmpty => ()
    InstanceTypeEmpty => ()
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
) -> Unit raise ComponentValidationError {
  match desc {
    CoreModuleType(tyidx) => check_typeidx(tyidx, type_bound)
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
      let ft = match td {
        Some(@component.TypeDef::FuncType(ft)) => ft
        _ => raise CanonExpectedFuncType(tyidx)
      }
      if canon_has_async(opts) && !ft.is_async {
        raise CanonAsyncTypeMismatch(tyidx)
      }
      if functype_needs_memory(ft) {
        if !canon_has_memory(opts) {
          raise MissingCanonOption("memory")
        }
        if !canon_has_realloc(opts) {
          raise MissingCanonOption("realloc")
        }
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
pub fn validate_component(
  component : @component.Component,
) -> Unit raise ComponentValidationError {
  let counts = Counts::new()
  let type_table : Array[@component.TypeDef?] = []
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
      2 => counts.core_instance += 1
      3 => counts.core_type += 1
      4 => {
        // Nested component payloads are also component binaries.
        let nested = @component.parse_component(s.payload) catch {
          e => raise SectionParseError(4, "parse nested component: \{e}")
        }
        validate_component(nested)
        counts.component += 1
      }
      7 => {
        // Definitions extend the type index space.
        let defs = @component.parse_type_section(s.payload) catch {
          e => raise SectionParseError(7, "\{e}")
        }
        for d in defs {
          // This is still a subset: we only allow referencing earlier types.
          validate_typedef(d, type_table.length())
          type_table.push(Some(d))
        }
      }
      10 => {
        let imports = @component.parse_import_section(s.payload) catch {
          e => raise SectionParseError(10, "\{e}")
        }
        for i in imports {
          // Import type references must be in-bounds at the point they appear.
          validate_externdesc(i.desc, type_table.length())
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
          check_sortidx(e.sortidx, counts, type_table.length())
          match e.desc {
            Some(d) => validate_externdesc(d, type_table.length())
            None => ()
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
