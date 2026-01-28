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
          // `Module.funcs` only contains defined functions. Exported function
          // indices are in the combined (imports + defs) index space.
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Func(tyidx) =>
                if imported == func_idx {
                  return Some(CoreExternType::Func(m.get_func_type(tyidx)))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = func_idx - imported
          if defined_idx < 0 || defined_idx >= m.funcs.length() {
            return None
          }
          let tyidx = m.funcs[defined_idx]
          return Some(CoreExternType::Func(m.get_func_type(tyidx)))
        }
        @types.ExportDesc::Table(table_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Table(tt) =>
                if imported == table_idx {
                  return Some(CoreExternType::Table(tt))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = table_idx - imported
          if defined_idx < 0 || defined_idx >= m.tables.length() {
            return None
          }
          return Some(CoreExternType::Table(m.tables[defined_idx].type_))
        }
        @types.ExportDesc::Memory(mem_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Memory(mt) =>
                if imported == mem_idx {
                  return Some(CoreExternType::Memory(mt))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = mem_idx - imported
          if defined_idx < 0 || defined_idx >= m.memories.length() {
            return None
          }
          return Some(CoreExternType::Memory(m.memories[defined_idx]))
        }
        @types.ExportDesc::Global(global_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              @types.ImportDesc::Global(gt) =>
                if imported == global_idx {
                  return Some(CoreExternType::Global(gt))
                } else {
                  imported += 1
                }
              _ => ()
            }
          }
          let defined_idx = global_idx - imported
          if defined_idx < 0 || defined_idx >= m.globals.length() {
            return None
          }
          return Some(CoreExternType::Global(m.globals[defined_idx].type_))
        }
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
