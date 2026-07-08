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
      Func(idx) => funcs.set(exp.name, { instance, func_idx: idx })
      Table(idx) => tables.set(exp.name, instance.table_addrs[idx])
      Memory(idx) => memories.set(exp.name, instance.mem_addrs[idx])
      Global(idx) => globals.set(exp.name, instance.global_addrs[idx])
      Tag(idx) => tags.set(exp.name, instance.tag_addrs[idx])
    }
  }
  { funcs, tables, memories, globals, tags }
}

///|
fn core_func_ref_type(
  f : CoreFuncRef,
) -> @types.FuncType raise ComponentRuntimeError {
  if f.func_idx < 0 || f.func_idx >= f.instance.func_type_indices.length() {
    raise InvalidCoreFuncIndex(f.func_idx)
  }
  let tyidx = f.instance.func_type_indices[f.func_idx]
  f.instance.get_func_type(tyidx)
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
    0x7f => I32
    0x7e => I64
    0x7d => F32
    0x7c => F64
    0x7b => V128
    0x70 => FuncRef
    0x6f => ExternRef
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
      Func(func_types[idx])
    }
    0x01 => {
      let elem = parse_core_valtype(reader)
      let limits = parse_limits_u32(reader)
      Table({ elem_type: elem, limits, is_table64: false })
    }
    0x02 => {
      let limits = parse_limits_u32(reader)
      Memory({ limits, is_memory64: false, page_size_log2: 16 })
    }
    0x03 => {
      let vt = parse_core_valtype(reader)
      let mutability = reader.read_u8() catch {
        e => raise ComponentParseError(e.to_string())
      }
      Global({ value_type: vt, mutable: mutability != 0 })
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
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
    FuncRef => "funcref"
    ExternRef => "externref"
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
        Func(func_idx) => {
          // `Module.funcs` only contains defined functions. Exported function
          // indices are in the combined (imports + defs) index space.
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              Func(tyidx) =>
                if imported == func_idx {
                  return Some(Func(m.get_func_type(tyidx)))
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
          return Some(Func(m.get_func_type(tyidx)))
        }
        Table(table_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              Table(tt) =>
                if imported == table_idx {
                  return Some(Table(tt))
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
          return Some(Table(m.tables[defined_idx].type_))
        }
        Memory(mem_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              Memory(mt) =>
                if imported == mem_idx {
                  return Some(Memory(mt))
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
          return Some(Memory(m.memories[defined_idx]))
        }
        Global(global_idx) => {
          let mut imported = 0
          for imp in m.imports {
            match imp.desc {
              Global(gt) =>
                if imported == global_idx {
                  return Some(Global(gt))
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
          return Some(Global(m.globals[defined_idx].type_))
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
        Func(tyidx) => return Some(Func(m.get_func_type(tyidx)))
        Table(tt) => return Some(Table(tt))
        Memory(mt) => return Some(Memory(mt))
        Global(gt) => return Some(Global(gt))
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
          (Func(ft1), Func(ft2)) =>
            if ft1 != ft2 {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (Global(gt1), Global(gt2)) =>
            if gt1 != gt2 {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (Table(tt1), Table(tt2)) =>
            if !table_import_compatible(tt2, tt1) {
              raise ImportTypeMismatch(
                "module import `\{key}` has the wrong type",
              )
            }
          (Memory(mt1), Memory(mt2)) =>
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
          (Func(ft1), Func(ft2)) =>
            if ft1 != ft2 {
              raise ImportTypeMismatch(
                "export `\{name}` has the wrong type (expected type `\{fmt_functype(ft1)}`, found type `\{fmt_functype(ft2)}`)",
              )
            }
          (Global(gt1), Global(gt2)) =>
            if gt1 != gt2 {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          (Table(tt1), Table(tt2)) =>
            if !table_export_compatible(tt2, tt1) {
              raise ImportTypeMismatch("export `\{name}` has the wrong type")
            }
          (Memory(mt1), Memory(mt2)) =>
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
