///|
fn componenttype_import_func_sigs_of_decls(
  decls : Array[@component.ComponentDecl],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
) -> Map[String, FuncSigShape] {
  let out : Map[String, FuncSigShape] = Map([])
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  // Avoid collisions with the enclosing component's nominal resource ids.
  let mut next_rid = 0
  for rid in global_resource_ids {
    if rid is Some(v) && v >= next_rid {
      next_rid = v + 1
    }
  }
  fn record_type_slot() -> Unit {
    local_types.push(InstanceTypeEmpty)
    local_resource_ids.push(None)
  }

  fn record_type_slot_for_bound(b : @component.TypeBound) -> Unit {
    match b {
      SubResource => {
        local_types.push(ResourceType(-1, 0x7f, None, HostDefined))
        local_resource_ids.push(Some(next_rid))
        next_rid += 1
      }
      Eq(_idx) => record_type_slot()
    }
  }

  for d in decls {
    match d {
      Type(t) => {
        local_types.push(t)
        match t {
          ResourceType(_, _, _, _) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }
      AliasOuter(kind, _count, _idx) => if kind == 0x03 { record_type_slot() }
      AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot()
        }
      Import(name, _attributes, desc) => {
        match desc {
          FuncType(tyidx) =>
            if tyidx >= 0 && tyidx < local_types.length() {
              match local_types[tyidx] {
                FuncType(ft) =>
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
                Some(FuncType(ft)) =>
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
          Type(b) => record_type_slot_for_bound(b)
          _ => ()
        }
      }
      Export(_name, _attributes, desc) =>
        match desc {
          Type(b) => record_type_slot_for_bound(b)
          _ => ()
        }
      CoreType(_) => ()
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
  let out : Map[String, TypeSig] = Map([])
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  // Avoid collisions with the enclosing component's nominal resource ids.
  let mut next_rid = 0
  for rid in global_resource_ids {
    if rid is Some(v) && v >= next_rid {
      next_rid = v + 1
    }
  }
  fn record_type_slot(as_resource : Bool) -> Int {
    let idx = local_types.length()
    if as_resource {
      local_types.push(ResourceType(-1, 0x7f, None, HostDefined))
      local_resource_ids.push(Some(next_rid))
      next_rid += 1
    } else {
      local_types.push(InstanceTypeEmpty)
      local_resource_ids.push(None)
    }
    idx
  }

  for d in decls {
    match d {
      Type(t) => {
        local_types.push(t)
        match t {
          ResourceType(_, _, _, _) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }
      AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          record_type_slot(false) |> ignore
        }
      AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot(false) |> ignore
        }
      Import(name, _attributes, desc) =>
        match desc {
          Type(bound) =>
            match bound {
              Eq(tyidx) => {
                // Compute the bound signature in the current local/global environment.
                out.set(
                  name,
                  type_sig_of_valtype_lg(
                    TypeIdx(tyidx),
                    local_types,
                    local_resource_ids,
                    global_types,
                    global_resource_ids,
                    Map([]),
                  ),
                )
                record_type_slot(false) |> ignore
              }
              SubResource => {
                let new_idx = record_type_slot(true)
                out.set(
                  name,
                  type_sig_of_valtype_lg(
                    TypeIdx(new_idx),
                    local_types,
                    local_resource_ids,
                    global_types,
                    global_resource_ids,
                    Map([]),
                  ),
                )
              }
            }
          _ => if desc is Type(_) { record_type_slot(false) |> ignore }
        }
      Export(_name, _attributes, desc) =>
        match desc {
          Type(bound) =>
            match bound {
              SubResource => record_type_slot(true) |> ignore
              Eq(_tyidx) => record_type_slot(false) |> ignore
            }
          _ => ()
        }
      CoreType(_) => ()
    }
  }
  out
}

///|
fn componenttype_import_type_bounds_of_decls(
  decls : Array[@component.ComponentDecl],
) -> Map[String, @component.TypeBound] {
  let out : Map[String, @component.TypeBound] = Map([])
  for d in decls {
    if d is Import(name, _attributes, Type(b)) {
      out.set(name, b)
    }
  }
  out
}

///|
fn componenttype_export_type_sigs_of_decls(
  decls : Array[@component.ComponentDecl],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int?],
) -> Map[String, TypeSig] {
  let out : Map[String, TypeSig] = Map([])
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  let mut next_rid = 0
  for rid in global_resource_ids {
    if rid is Some(value) && value >= next_rid {
      next_rid = value + 1
    }
  }

  fn push_placeholder() -> Unit {
    local_types.push(InstanceTypeEmpty)
    local_resource_ids.push(None)
  }

  fn push_resource() -> Int {
    let idx = local_types.length()
    local_types.push(ResourceType(-1, 0x7f, None, HostDefined))
    local_resource_ids.push(Some(next_rid))
    next_rid += 1
    idx
  }

  fn push_eq(idx : Int) -> Unit {
    if idx >= 0 && idx < local_types.length() {
      local_types.push(local_types[idx])
      local_resource_ids.push(local_resource_ids[idx])
    } else {
      push_placeholder()
    }
  }

  for d in decls {
    match d {
      Type(t) => {
        local_types.push(t)
        if t is ResourceType(_, _, _, _) {
          local_resource_ids.push(Some(next_rid))
          next_rid += 1
        } else {
          local_resource_ids.push(None)
        }
      }
      AliasOuter(kind, _, _) | AliasInstanceExport(kind, _, _) =>
        if kind == 0x03 {
          push_placeholder()
        }
      Import(_name, _attributes, desc) =>
        match desc {
          Type(SubResource) => push_resource() |> ignore
          Type(Eq(idx)) => push_eq(idx)
          _ => ()
        }
      Export(name, _attributes, desc) =>
        match desc {
          Type(SubResource) => {
            let idx = push_resource()
            out.set(
              name,
              type_sig_of_valtype_lg(
                TypeIdx(idx),
                local_types,
                local_resource_ids,
                global_types,
                global_resource_ids,
                Map([]),
              ),
            )
          }
          Type(Eq(idx)) => {
            out.set(
              name,
              type_sig_of_valtype_lg(
                TypeIdx(idx),
                local_types,
                local_resource_ids,
                global_types,
                global_resource_ids,
                Map([]),
              ),
            )
            push_eq(idx)
          }
          _ => ()
        }
      CoreType(_) => ()
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
  let out : Map[String, FuncSigShape] = Map([])
  let local_types : Array[@component.TypeDef] = []
  let local_resource_ids : Array[Int?] = []
  // Avoid collisions with the enclosing component's nominal resource ids.
  let mut next_rid = 0
  for rid in global_resource_ids {
    if rid is Some(v) && v >= next_rid {
      next_rid = v + 1
    }
  }
  fn record_type_slot() -> Unit {
    local_types.push(InstanceTypeEmpty)
    local_resource_ids.push(None)
  }

  fn record_type_slot_for_bound(b : @component.TypeBound) -> Unit {
    match b {
      SubResource => {
        local_types.push(ResourceType(-1, 0x7f, None, HostDefined))
        local_resource_ids.push(Some(next_rid))
        next_rid += 1
      }
      Eq(_idx) => record_type_slot()
    }
  }

  fn record_type_slots_for_desc(desc : @component.ExternDesc) -> Unit {
    if desc is Type(b) {
      record_type_slot_for_bound(b)
    }
  }

  for d in decls {
    match d {
      Type(t) => {
        local_types.push(t)
        match t {
          ResourceType(_, _, _, _) => {
            local_resource_ids.push(Some(next_rid))
            next_rid += 1
          }
          _ => local_resource_ids.push(None)
        }
      }
      AliasOuter(kind, _count, _idx) => if kind == 0x03 { record_type_slot() }
      AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          record_type_slot()
        }
      Import(_name, _attributes, desc) => record_type_slots_for_desc(desc)
      Export(name, _attributes, desc) => {
        match desc {
          FuncType(tyidx) =>
            if tyidx >= 0 && tyidx < local_types.length() {
              match local_types[tyidx] {
                FuncType(ft) =>
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
                Some(FuncType(ft)) =>
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
      CoreType(_) => ()
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
  let result : Map[String, Map[String, Int]] = Map([])
  for i in c.imports {
    if (importname_to_string(i.name), i.desc)
      is (Some(name), CoreModuleType(tyidx)) &&
      tyidx >= 0 &&
      tyidx < core_type_exports.length() &&
      core_type_exports[tyidx] is Some(map) {
      result.set(name, map)
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
  let result : Map[String, Map[String, CoreExternType]] = Map([])
  for i in c.imports {
    if (importname_to_string(i.name), i.desc)
      is (Some(name), CoreModuleType(tyidx)) &&
      tyidx >= 0 &&
      tyidx < core_type_imports.length() &&
      core_type_imports[tyidx] is Some(imps) {
      let map : Map[String, CoreExternType] = Map([])
      for imp in imps {
        map.set("\{imp.mod_name}::\{imp.name}", imp.ty)
      }
      result.set(name, map)
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
      CoreType(bytes) => {
        let r = CoreTypeReader::CoreTypeReader(bytes)
        let op = r.read_u8()
        if op == 0x50 {
          let (imps, exps) = parse_core_type_module_sig(
            r,
            -1,
            core_type_bound,
            [],
          )
          let imp_map : Map[String, CoreExternType] = Map([])
          for imp in imps {
            imp_map.set("\{imp.mod_name}::\{imp.name}", imp.ty)
          }
          let exp_kinds : Map[String, Int] = Map([])
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
      AliasOuter(kind, _count, _idx) =>
        if kind != 0x03 {
          // Core-type aliases consume a core-type index.
          local_core_import_sigs.push(None)
          local_core_export_kinds.push(None)
          core_type_bound += 1
        }
      AliasInstanceExport(kind, _inst, _name) =>
        if kind != 0x03 {
          local_core_import_sigs.push(None)
          local_core_export_kinds.push(None)
          core_type_bound += 1
        }
      _ => ()
    }
  }
  let import_sigs : Map[String, Map[String, CoreExternType]] = Map([])
  let export_kinds : Map[String, Map[String, Int]] = Map([])
  for d in decls {
    if d is Import(name, _attributes, desc) &&
      desc is CoreModuleType(tyidx) &&
      tyidx >= 0 &&
      tyidx < local_core_import_sigs.length() {
      if local_core_import_sigs[tyidx] is Some(map) {
        import_sigs.set(name, map)
      }
      if local_core_export_kinds[tyidx] is Some(map) {
        export_kinds.set(name, map)
      }
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
    CoreModuleType(_) => Core(0x11)
    FuncType(_) => Func
    Value(_) => Value
    Type(_) => Type
    ComponentType(_) => Component
    InstanceType(_) => Instance
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
  if ty is TypeIdx(idx) {
    check_typeidx(idx, type_table.length())
    match type_table[idx] {
      // Component valtypes may reference any defined type (not function,
      // component, or instance types).
      Some(FuncType(_))
      | Some(ComponentType(_))
      | Some(InstanceTypeEmpty)
      | Some(InstanceType(_)) => raise TypeIndexNotDefinedType(idx)
      Some(_) => ()
      None => ()
    }
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
fn valtype_contains_borrow(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    Prim(_) => false
    TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        false
      } else if visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, 1)
        let any = match type_table[idx] {
          Some(Borrow(_)) => true
          Some(Tuple(xs)) => {
            let mut any = false
            for v in xs {
              if valtype_contains_borrow(v, type_table, visiting) {
                any = true
                break
              }
            }
            any
          }
          Some(Record(fields)) => {
            let mut any = false
            for f in fields {
              if valtype_contains_borrow(f.ty, type_table, visiting) {
                any = true
                break
              }
            }
            any
          }
          Some(Variant(cases)) => {
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
          Some(Option(v)) => valtype_contains_borrow(v, type_table, visiting)
          Some(Result(ok, err)) => {
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
          Some(List(v)) => valtype_contains_borrow(v, type_table, visiting)
          Some(Stream(v)) | Some(Future(v)) =>
            match v {
              None => false
              Some(inner) =>
                valtype_contains_borrow(inner, type_table, visiting)
            }
          Some(Own(idx2)) =>
            valtype_contains_borrow(TypeIdx(idx2), type_table, visiting)
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
  type_outer_depths : Array[Int],
  component_depth : Int,
  core_type_outers : Array[Array[Map[String, Int]?]],
  allow_resource_defs : Bool,
) -> Unit raise ComponentValidationError {
  if type_outers.length() == 0 ||
    type_outer_depths.length() != type_outers.length() ||
    core_type_outers.length() == 0 {
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
      let seen : Map[String, String] = Map([])
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
      let seen : Map[String, String] = Map([])
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
      let seen : Map[String, String] = Map([])
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
      let seen : Map[String, String] = Map([])
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
        Some(ResourceType(_, _, _, _)) => ()
        None => ()
        Some(_) => raise SectionParseError(7, "not a resource type")
      }
    }
    Stream(v) =>
      match v {
        Some(Prim(Char)) =>
          raise SectionParseError(7, "`stream<char>` is not valid")
        Some(t) => validate_valtype(t, type_table)
        None => ()
      }
    Future(v) =>
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
      let seen_imports : Map[String, String] = Map([])
      let seen_exports : Map[String, String] = Map([])
      let local_named_types : Map[Int, Int] = Map([])
      let local_import_resource_names : Map[String, Int] = Map([])
      let local_export_resource_names : Map[String, Int] = Map([])
      let local_import_resource_type_idxs : Map[Int, Int] = Map([])
      let local_export_resource_type_idxs : Map[Int, Int] = Map([])
      let local_core_type_exports : Array[Map[String, Int]?] = []
      for d in decls {
        match d {
          CoreType(bytes) => {
            local_core_type_exports.push(
              validate_single_core_type(
                bytes, local_core_type_bound, outer_core_type_bounds,
              ),
            )
            local_core_type_bound += 1
          }
          AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let outer = outer_type_of_alias(type_outers, count, idx)
              if type_outer_depths[count - 1] < component_depth {
                match outer {
                  Some(td) =>
                    if typedef_refers_to_resource(
                        td,
                        type_outers[count - 1],
                        Map([]),
                      ) {
                      raise SectionParseError(
                        7, "transitively refers to resources",
                      )
                    }
                  None => ()
                }
              }
              local_type_table.push(outer)
              local_resource_ids.push(None)
            } else if kind == 0x110 {
              local_core_type_exports.push(
                outer_core_type_of_alias(core_type_outers, count, idx),
              )
              local_core_type_bound += 1
            } else {
              raise SectionParseError(7, "outer alias may only refer to types")
            }
          AliasInstanceExport(kind, _instance_idx, _name) =>
            if kind == 0x03 {
              local_type_table.push(None)
              local_resource_ids.push(None)
            } else if kind != 0x05 {
              raise SectionParseError(
                7, "alias export may only refer to types or instances",
              )
            }
          Type(t) => {
            validate_typedef(
              t,
              cfg,
              [local_type_table] + type_outers,
              [component_depth] + type_outer_depths,
              component_depth,
              [local_core_type_exports] + core_type_outers,
              false,
            )
            local_type_table.push(Some(t))
            local_resource_ids.push(None)
          }
          Import(name, attributes, desc) => {
            validate_extern_name_string(name, cfg)
            validate_name_attributes_string(
              7,
              name,
              attributes,
              sort_of_externdesc(desc),
            )
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
              CoreModuleType(tyidx) =>
                if tyidx < 0 ||
                  tyidx >= local_core_type_exports.length() ||
                  local_core_type_exports[tyidx] is None {
                  raise CoreTypeIndexNotModuleType(tyidx)
                }
              _ => ()
            }
            match desc {
              Type(bound) => {
                let new_idx = local_type_table.length()
                match bound {
                  Eq(tyidx) =>
                    if tyidx >= 0 && tyidx < local_type_table.length() {
                      local_type_table.push(local_type_table[tyidx])
                      local_resource_ids.push(local_resource_ids[tyidx])
                    } else {
                      local_type_table.push(None)
                      local_resource_ids.push(None)
                    }
                  SubResource => {
                    local_type_table.push(
                      Some(ResourceType(-1, 0x7f, None, HostDefined)),
                    )
                    local_resource_ids.push(None)
                  }
                }
                local_named_types.set(new_idx, 1)
                match bound {
                  SubResource => {
                    local_import_resource_names.set(name, new_idx)
                    local_import_resource_type_idxs.set(new_idx, 1)
                  }
                  _ => ()
                }
                if !valtype_valid_for_type_import_export(
                    TypeIdx(new_idx),
                    local_type_table,
                    local_resource_ids,
                    local_named_types,
                    Map([]),
                  ) {
                  raise SectionParseError(
                    7, "type not valid to be used as import",
                  )
                }
              }
              FuncType(tyidx) =>
                if tyidx >= 0 && tyidx < local_type_table.length() {
                  match local_type_table[tyidx] {
                    Some(FuncType(ft)) => {
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
          Export(name, attributes, desc) => {
            validate_extern_name_string(name, cfg)
            validate_name_attributes_string(
              7,
              name,
              attributes,
              sort_of_externdesc(desc),
            )
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
              CoreModuleType(tyidx) =>
                if tyidx < 0 ||
                  tyidx >= local_core_type_exports.length() ||
                  local_core_type_exports[tyidx] is None {
                  raise CoreTypeIndexNotModuleType(tyidx)
                }
              _ => ()
            }
            match desc {
              Type(bound) => {
                let new_idx = local_type_table.length()
                match bound {
                  Eq(tyidx) =>
                    if tyidx >= 0 && tyidx < local_type_table.length() {
                      local_type_table.push(local_type_table[tyidx])
                      local_resource_ids.push(local_resource_ids[tyidx])
                    } else {
                      local_type_table.push(None)
                      local_resource_ids.push(None)
                    }
                  SubResource => {
                    local_type_table.push(
                      Some(ResourceType(-1, 0x7f, None, HostDefined)),
                    )
                    local_resource_ids.push(None)
                  }
                }
                local_named_types.set(new_idx, 1)
                match bound {
                  SubResource => {
                    local_export_resource_names.set(name, new_idx)
                    local_export_resource_type_idxs.set(new_idx, 1)
                  }
                  _ => ()
                }
                if !valtype_valid_for_type_import_export(
                    TypeIdx(new_idx),
                    local_type_table,
                    local_resource_ids,
                    local_named_types,
                    Map([]),
                  ) {
                  raise SectionParseError(
                    7, "type not valid to be used as export",
                  )
                }
              }
              FuncType(tyidx) =>
                if tyidx >= 0 && tyidx < local_type_table.length() {
                  match local_type_table[tyidx] {
                    Some(FuncType(ft)) => {
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
      let seen_exports : Map[String, String] = Map([])
      let local_core_type_exports : Array[Map[String, Int]?] = []
      for d in decls {
        match d {
          CoreType(bytes) => {
            let r = CoreTypeReader::CoreTypeReader(bytes)
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
          AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let outer = outer_type_of_alias(type_outers, count, idx)
              if type_outer_depths[count - 1] < component_depth {
                match outer {
                  Some(td) =>
                    if typedef_refers_to_resource(
                        td,
                        type_outers[count - 1],
                        Map([]),
                      ) {
                      raise SectionParseError(
                        7, "transitively refers to resources",
                      )
                    }
                  None => ()
                }
              }
              local_type_table.push(outer)
            } else if kind == 0x110 {
              local_core_type_exports.push(
                outer_core_type_of_alias(core_type_outers, count, idx),
              )
              local_core_type_bound += 1
            } else {
              raise SectionParseError(7, "outer alias may only refer to types")
            }
          AliasInstanceExport(kind, _instance_idx, _name) =>
            if kind == 0x03 {
              local_type_table.push(None)
            } else if kind != 0x05 {
              raise SectionParseError(
                7, "alias export may only refer to types or instances",
              )
            }
          Type(t) => {
            validate_typedef(
              t,
              cfg,
              [local_type_table] + type_outers,
              [component_depth] + type_outer_depths,
              component_depth,
              [local_core_type_exports] + core_type_outers,
              false,
            )
            local_type_table.push(Some(t))
          }
          Export(name, attributes, desc) => {
            validate_extern_name_string(name, cfg)
            validate_name_attributes_string(
              7,
              name,
              attributes,
              sort_of_externdesc(desc),
            )
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
              CoreModuleType(tyidx) =>
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
      let seen_params : Map[String, String] = Map([])
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
          if valtype_contains_borrow(r, type_table, Map([])) {
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
        Some(FuncType(_)) => ()
        Some(_) | None => raise TypeIndexNotFuncType(tyidx)
      }
    }
    ComponentType(tyidx) => {
      check_typeidx(tyidx, type_table.length())
      match type_table[tyidx] {
        Some(ComponentType(_)) => ()
        Some(_) | None => raise TypeIndexNotComponentType(tyidx)
      }
    }
    InstanceType(tyidx) => {
      check_typeidx(tyidx, type_table.length())
      match type_table[tyidx] {
        Some(InstanceType(_)) | Some(InstanceTypeEmpty) => ()
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
  let mut seen_core_type = false
  let mut seen_gc = false
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
      CoreType(_) =>
        if seen_core_type {
          raise DuplicateCanonOption("core-type")
        } else {
          seen_core_type = true
        }
      Gc =>
        if seen_gc {
          raise DuplicateCanonOption("gc")
        } else {
          seen_gc = true
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
    if o is Memory(idx) {
      return Some(idx)
    }
  }
  None
}

///|
fn canon_realloc_idx(opts : Array[@component.CanonOpt]) -> Int? {
  for o in opts {
    if o is Realloc(idx) {
      return Some(idx)
    }
  }
  None
}

///|
fn canon_post_return_idx(opts : Array[@component.CanonOpt]) -> Int? {
  for o in opts {
    if o is PostReturn(idx) {
      return Some(idx)
    }
  }
  None
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
fn functype_params_need_memory(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
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
fn functype_async_lift_needs_memory(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
  if functype_params_need_memory(ft, type_table) {
    return true
  }
  match ft.result {
    None => false
    Some(r) =>
      match core_valtypes_for_component_valtype(r, type_table) {
        None => true
        Some(ts) => ts.length() > 16
      }
  }
}

///|
fn valtype_contains_list_or_string(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Unit],
) -> Bool {
  match ty {
    Prim(String) => true
    Prim(_) => false
    TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() || visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, ())
        let found = match type_table[idx] {
          None => false
          Some(td) =>
            match td {
              DefValType(String) | List(_) => true
              DefValType(_)
              | Flags(_)
              | Enum(_)
              | Own(_)
              | Borrow(_)
              | ResourceType(_, _, _, _)
              | Stream(_)
              | Future(_)
              | InstanceTypeEmpty => false
              Record(fields) => {
                let mut any = false
                for field in fields {
                  if valtype_contains_list_or_string(
                      field.ty,
                      type_table,
                      visiting,
                    ) {
                    any = true
                    break
                  }
                }
                any
              }
              Variant(cases) => {
                let mut any = false
                for variant_case in cases {
                  if variant_case.ty is Some(case_ty) &&
                    valtype_contains_list_or_string(
                      case_ty, type_table, visiting,
                    ) {
                    any = true
                    break
                  }
                }
                any
              }
              Tuple(types) => {
                let mut any = false
                for element in types {
                  if valtype_contains_list_or_string(
                      element, type_table, visiting,
                    ) {
                    any = true
                    break
                  }
                }
                any
              }
              Option(inner) =>
                valtype_contains_list_or_string(inner, type_table, visiting)
              Result(ok, err) => {
                let ok_has = match ok {
                  Some(inner) =>
                    valtype_contains_list_or_string(inner, type_table, visiting)
                  None => false
                }
                let err_has = match err {
                  Some(inner) =>
                    valtype_contains_list_or_string(inner, type_table, visiting)
                  None => false
                }
                ok_has || err_has
              }
              FuncType(_) | ComponentType(_) | InstanceType(_) => false
            }
        }
        visiting.remove(idx) |> ignore
        found
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
    if valtype_contains_list_or_string(p.ty, type_table, Map([])) {
      return true
    }
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
  // Results are lifted from memory written by the core callee. Reading a
  // string/list result needs `memory`, but does not allocate through the
  // component's realloc function.
  false
}

///|
fn functype_needs_realloc_for_lower(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> Bool {
  // Canon lower reads parameters already written by the core caller, so
  // dynamic parameters only require `memory`. A dynamic result is written
  // back into that memory and therefore requires the supplied allocator.
  match ft.result {
    Some(result_ty) =>
      valtype_contains_list_or_string(result_ty, type_table, Map([]))
    None => false
  }
}
