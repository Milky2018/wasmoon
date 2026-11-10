///|
/// Minimal decoder for wasm-encoded WIT packages.
///
/// This is intended to support `wasmoon-tools wit <component.wasm>` by extracting a
/// best-effort WIT document from a component binary produced by `wasm-tools component wit`
/// or `wasmoon-tools wit --wasm`.
///
/// This currently focuses on the "type-only" shape of WIT package components:
/// top-level type exports for interfaces/worlds where each exported type is a
/// wrapper `componenttype` exporting either:
/// - an `instance` under the full interface name, or
/// - a `component` under the full world name.

///|
priv enum TypeSlot {
  Def(@component.TypeDef)
  AliasOuter(Int32, Int32) // (count, idx)
  ExportedType(String, @component.TypeBound)
}

///|
fn primitive_type_name(p : @component.PrimValType) -> String {
  match p {
    Bool => "bool"
    S8 => "s8"
    U8 => "u8"
    S16 => "s16"
    U16 => "u16"
    S32 => "s32"
    U32 => "u32"
    S64 => "s64"
    U64 => "u64"
    F32 => "f32"
    F64 => "f64"
    Char => "char"
    String => "string"
    ErrorContext => "error-context"
  }
}

///|
fn typeexpr_of_valtype(
  slots : Array[TypeSlot],
  v : @component.ValType,
  export_name_by_idx : Map[Int32, String],
  resource_by_idx : Map[Int32, String],
) -> TypeExpr raise WitError {
  match v {
    Prim(p) => Id(primitive_type_name(p))
    TypeIdx(i) =>
      match export_name_by_idx.get(i) {
        Some(n) => Id(n)
        None =>
          match slots[i] {
            Def(td) =>
              typeexpr_of_typedef(
                slots, td, export_name_by_idx, resource_by_idx,
              )
            AliasOuter(_c, _idx) =>
              // Best-effort: keep as opaque.
              Id("other")
            ExportedType(n, bound) =>
              match bound {
                SubResource => Id(n) // resources are value-level via own/borrow, see below
                Eq(_ti) => Id(n)
              }
          }
      }
  }
}

///|
fn typeexpr_of_typedef(
  slots : Array[TypeSlot],
  td : @component.TypeDef,
  export_name_by_idx : Map[Int32, String],
  resource_by_idx : Map[Int32, String],
) -> TypeExpr raise WitError {
  match td {
    DefValType(p) => Id(primitive_type_name(p))
    List(t) =>
      Apply("list", [
        typeexpr_of_valtype(slots, t, export_name_by_idx, resource_by_idx),
      ])
    FixedList(_, _) =>
      raise Error("fixed-length lists cannot be represented by the WIT AST")
    MapType(key, value) =>
      Apply("map", [
        typeexpr_of_valtype(slots, key, export_name_by_idx, resource_by_idx),
        typeexpr_of_valtype(slots, value, export_name_by_idx, resource_by_idx),
      ])
    Tuple(ts) => {
      let args : Array[TypeExpr] = []
      for t in ts {
        args.push(
          typeexpr_of_valtype(slots, t, export_name_by_idx, resource_by_idx),
        )
      }
      Apply("tuple", args)
    }
    Option(t) =>
      Apply("option", [
        typeexpr_of_valtype(slots, t, export_name_by_idx, resource_by_idx),
      ])
    Result(ok, err) => {
      let args : Array[TypeExpr] = []
      match ok {
        None => ()
        Some(v) =>
          args.push(
            typeexpr_of_valtype(slots, v, export_name_by_idx, resource_by_idx),
          )
      }
      match err {
        None => ()
        Some(v) =>
          args.push(
            typeexpr_of_valtype(slots, v, export_name_by_idx, resource_by_idx),
          )
      }
      Apply("result", args)
    }
    Own(ti) =>
      match resource_by_idx.get(ti) {
        Some(name) => Id(name)
        None => Apply("own", [Id("other")])
      }
    Borrow(ti) =>
      match resource_by_idx.get(ti) {
        Some(name) => Apply("borrow", [Id(name)])
        None => Apply("borrow", [Id("other")])
      }
    Future(t) =>
      match t {
        None => Apply("future", [])
        Some(v) =>
          Apply("future", [
            typeexpr_of_valtype(slots, v, export_name_by_idx, resource_by_idx),
          ])
      }
    Stream(t) =>
      match t {
        None => Apply("stream", [])
        Some(v) =>
          Apply("stream", [
            typeexpr_of_valtype(slots, v, export_name_by_idx, resource_by_idx),
          ])
      }
    Record(fields) => {
      let out : Array[(String, TypeExpr)] = []
      for f in fields {
        out.push(
          (
            f.label,
            typeexpr_of_valtype(
              slots,
              f.ty,
              export_name_by_idx,
              resource_by_idx,
            ),
          ),
        )
      }
      Record(out)
    }
    Variant(cases) => {
      // Represent as an inline variant using a best-effort `TypeAlias`.
      // Callers that want a top-level `variant` item will handle it based on exports.
      let out : Array[(String, TypeExpr)] = []
      for c in cases {
        match c.ty {
          None => out.push((c.label, Id("unit")))
          Some(v) =>
            out.push(
              (
                c.label,
                typeexpr_of_valtype(
                  slots, v, export_name_by_idx, resource_by_idx,
                ),
              ),
            )
        }
      }
      // No direct inline variant syntax in TypeExpr; fall back to opaque.
      Id("other")
    }
    Flags(_)
    | Enum(_)
    | FuncType(_)
    | ComponentType(_)
    | InstanceTypeEmpty
    | InstanceType(_)
    | ResourceType(_, _, _, _) =>
      // Not used as inline type expressions for our extraction output.
      Id("other")
  }
}

///|
fn decode_full_name(full : String) -> (String, String, String?) {
  // full = pkg/name[@ver]
  let mut ver : String? = None
  let mut base = full
  if find_last_code_unit(full, 64) // '@'
    is Some(i) &&
    i > 0 &&
    i + 1 < full.length() {
    ver = Some(slice_ascii(full, i + 1, full.length()))
    base = slice_ascii(full, 0, i)
  }
  match find_last_code_unit(base, 47) { // '/'
    Some(i) => {
      let pkg = slice_ascii(base, 0, i)
      let name = slice_ascii(base, i + 1, base.length())
      (pkg, name, ver)
    }
    None => ("", base, ver)
  }
}

///|
fn build_componenttype_type_space(
  decls : Array[@component.ComponentDecl],
) -> Array[@component.TypeDef?] {
  let out : Array[@component.TypeDef?] = []
  for d in decls {
    match d {
      Type(td) => out.push(Some(td))
      AliasOuter(kind, _count, _idx) => if kind == 0x03 { out.push(None) }
      AliasInstanceExport(kind, _inst, _name) =>
        if kind == 0x03 {
          out.push(None)
        }
      _ => ()
    }
  }
  out
}

///|
fn build_instancetype_type_slots(
  decls : Array[@component.InstanceDecl],
) -> (
  Array[TypeSlot],
  Map[String, Int32],
  Map[Int32, String],
  Map[Int32, String],
) {
  let slots : Array[TypeSlot] = []
  let exported_idx_by_name : Map[String, Int32] = Map([])
  let export_name_by_idx : Map[Int32, String] = Map([])
  let resource_by_idx : Map[Int32, String] = Map([])
  for d in decls {
    match d {
      Type(td) => slots.push(Def(td))
      AliasOuter(kind, count, idx) =>
        if kind == 0x03 {
          slots.push(AliasOuter(count, idx))
        }
      Export(name, _attributes, desc) =>
        match desc {
          Type(bound) => {
            let idx = slots.length()
            slots.push(ExportedType(name, bound))
            exported_idx_by_name.set(name, idx)
            export_name_by_idx.set(idx, name)
            match bound {
              SubResource => resource_by_idx.set(idx, name)
              _ => ()
            }
          }
          _ => ()
        }
      _ => ()
    }
  }
  (slots, exported_idx_by_name, export_name_by_idx, resource_by_idx)
}

///|
fn decode_interface_from_componenttype(
  decls : Array[@component.ComponentDecl],
  export_short_name : String,
) -> (String, String?, Interface) raise WitError {
  // Find the exported instance under the full interface name.
  let mut exported : (String, Int32)? = None
  for d in decls {
    if d is Export(name, _attributes, InstanceType(ti)) {
      exported = Some((name, ti))
    }
  }
  let (full, inst_tyidx) = exported.unwrap_or_else(() => {
    raise WitError::Error(
      "not an interface wrapper: `" + export_short_name + "`",
    )
  })
  let (pkg, name, ver) = decode_full_name(full)
  let type_space = build_componenttype_type_space(decls)

  // Build a small amount of context for resolving `(alias outer 1 <idx>)` in the
  // exported instancetype back to the imported instance's type export.
  let alias_export_by_typeidx : Map[Int32, (Int32, String)] = Map([]) // typeidx -> (inst_idx, export_name)
  let inst_sig_typeidx_by_inst : Map[Int32, Int32] = Map([]) // inst_idx -> instancetype typeidx (in componenttype space)
  let mut cur_typeidx = 0
  let mut cur_instidx = 0
  for d in decls {
    match d {
      Type(_td) => cur_typeidx = cur_typeidx + 1
      Import(_n, _attributes, InstanceType(ti)) => {
        inst_sig_typeidx_by_inst.set(cur_instidx, ti)
        cur_instidx = cur_instidx + 1
      }
      AliasInstanceExport(kind, inst, n) =>
        if kind == 0x03 {
          alias_export_by_typeidx.set(cur_typeidx, (inst, n))
          cur_typeidx = cur_typeidx + 1
        }
      AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          cur_typeidx = cur_typeidx + 1
        }
      _ => ()
    }
  }
  let inst_td = type_space[inst_tyidx].unwrap_or_else(() => {
    raise WitError::Error("missing instancetype for `" + full + "`")
  })
  let inst_decls = match inst_td {
    InstanceType(xs) => xs
    InstanceTypeEmpty => []
    _ => raise Error("expected instancetype for `" + full + "`")
  }
  let (slots, idx_by_name, export_name_by_idx, resource_by_idx0) = build_instancetype_type_slots(
    inst_decls,
  )

  // Augment resource_by_idx: treat exported types that are eq to an outer resource as resources.
  let resource_by_idx : Map[Int32, String] = Map([])
  for kv in resource_by_idx0.iter() {
    let (i, n) = kv
    resource_by_idx.set(i, n)
  }
  fn resolve_outer_export_typedef(
    type_space : Array[@component.TypeDef?],
    inst_sig_typeidx_by_inst : Map[Int32, Int32],
    alias_export_by_typeidx : Map[Int32, (Int32, String)],
    outer_typeidx : Int32,
  ) -> (@component.TypeDef?, @component.TypeBound?)? raise WitError {
    match alias_export_by_typeidx.get(outer_typeidx) {
      None => None
      Some(pair) => {
        let (inst_idx, export_name) = pair
        let sig_ti = inst_sig_typeidx_by_inst
          .get(inst_idx)
          .unwrap_or_else(() => raise WitError::Error("missing import sig"))
        let sig_td = match type_space[sig_ti] {
          Some(td) => td
          None => raise Error("missing instancetype signature")
        }
        let sig_decls = match sig_td {
          InstanceType(xs) => xs
          InstanceTypeEmpty => []
          _ => raise Error("expected instancetype signature")
        }
        let (slots2, idx_by_name2, _export_name_by_idx2, _resource_by_idx2) = build_instancetype_type_slots(
          sig_decls,
        )
        match idx_by_name2.get(export_name) {
          None => None
          Some(exp_idx) =>
            match slots2[exp_idx] {
              ExportedType(_n, bound) =>
                match bound {
                  SubResource => Some((None, Some(bound)))
                  Eq(ti) =>
                    match slots2[ti] {
                      Def(td2) => Some((Some(td2), Some(bound)))
                      _ => Some((None, Some(bound)))
                    }
                }
              _ => None
            }
        }
      }
    }
  }

  // Collect resources (from exported types).
  let resources : Map[String, ResourceDecl] = Map([])
  for kv in resource_by_idx.iter() {
    let (_i, rname) = kv
    resources.set(rname, { name: rname, methods: [], })
  }

  // Resolve local definitions and outer aliases before decoding their shared shape.
  let type_items : Array[InterfaceItem] = []
  for d in inst_decls {
    if d is Export(tname, _attributes, Type(Eq(ti))) {
      let definition : @component.TypeDef? = match slots[ti] {
        AliasOuter(1, outer_idx) =>
          match
            resolve_outer_export_typedef(
              type_space, inst_sig_typeidx_by_inst, alias_export_by_typeidx, outer_idx,
            ) {
            Some((None, Some(SubResource))) => {
              resources.set(tname, { name: tname, methods: [], })
              if idx_by_name.get(tname) is Some(exp_idx) {
                resource_by_idx.set(exp_idx, tname)
              }
              continue
            }
            Some((definition, _)) => definition
            None => None
          }
        Def(definition) => Some(definition)
        _ => None
      }
      type_items.push(
        match definition {
          Some(Record(fields)) => {
            let decoded : Array[(String, TypeExpr)] = []
            for field in fields {
              decoded.push(
                (
                  field.label,
                  typeexpr_of_valtype(
                    slots,
                    field.ty,
                    export_name_by_idx,
                    resource_by_idx,
                  ),
                ),
              )
            }
            Record({ name: tname, fields: decoded, })
          }
          Some(Flags(flags)) => Flags({ name: tname, flags, })
          Some(Enum(cases)) => Enum({ name: tname, cases, })
          Some(Variant(cases)) => {
            let decoded : Array[VariantCase] = []
            for case_ in cases {
              let payload = match case_.ty {
                Some(ty) =>
                  Some(
                    typeexpr_of_valtype(
                      slots, ty, export_name_by_idx, resource_by_idx,
                    ),
                  )
                None => None
              }
              decoded.push({ name: case_.label, payload, })
            }
            Variant({ name: tname, cases: decoded, })
          }
          Some(definition) =>
            TypeAlias({
              name: tname,
              ty: typeexpr_of_typedef(
                slots, definition, export_name_by_idx, resource_by_idx,
              ),
            })
          None => TypeAlias({ name: tname, ty: Id("other"), })
        },
      )
    }
  }

  fn decode_function(
    name : String,
    ft : @component.FuncType,
    start : Int32,
  ) -> FuncDecl raise WitError {
    let params : Array[(String, TypeExpr)] = []
    for i in start..<ft.params.length() {
      let param = ft.params[i]
      params.push(
        (
          param.label,
          typeexpr_of_valtype(
            slots,
            param.ty,
            export_name_by_idx,
            resource_by_idx,
          ),
        ),
      )
    }
    let results : Array[(String?, TypeExpr)] = []
    if ft.result is Some(ty) {
      results.push(
        (
          None,
          typeexpr_of_valtype(slots, ty, export_name_by_idx, resource_by_idx),
        ),
      )
    }
    { name, is_async: ft.is_async, params, results, }
  }

  // Collect exported funcs and resource methods.
  let func_items : Array[InterfaceItem] = []
  for d in inst_decls {
    if d is Export(fname, _attributes, FuncType(ti)) &&
      slots[ti] is Def(FuncType(ft)) {
      if fname.has_prefix("[method]") {
        let rest = slice_ascii(fname, 8, fname.length())
        if find_last_code_unit(rest, 46) is Some(dot) { // '.'
          let rname = slice_ascii(rest, 0, dot)
          let mname = slice_ascii(rest, dot + 1, rest.length())
          if resources.get(rname) is Some(resource) {
            let start = if ft.params.length() > 0 &&
              ft.params[0].label == "self" {
              1
            } else {
              0
            }
            resource.methods.push(decode_function(mname, ft, start))
          }
        }
      } else {
        func_items.push(Func(decode_function(fname, ft, 0)))
      }
    }
  }

  // Assemble interface items: types, resources, funcs.
  let items = type_items
  for kv in resources.iter() {
    let (_k, r) = kv
    items.push(Resource(r))
  }
  items.append(func_items)
  (pkg, ver, { name, items, })
}

///|
fn decode_world_from_componenttype(
  decls : Array[@component.ComponentDecl],
  export_short_name : String,
) -> (String, String?, World) raise WitError {
  let mut exported : (String, Int32)? = None
  for d in decls {
    if d is Export(name, _attributes, ComponentType(ti)) {
      exported = Some((name, ti))
    }
  }
  let (full, comp_tyidx) = exported.unwrap_or_else(() => {
    raise WitError::Error("not a world wrapper: `" + export_short_name + "`")
  })
  let (pkg, name, ver) = decode_full_name(full)
  let type_space = build_componenttype_type_space(decls)
  fn normalize_inst_name(n : String) -> String {
    let (pkg2, name2, ver2) = decode_full_name(n)
    if pkg2 == pkg && ver2 == ver {
      name2
    } else {
      n
    }
  }

  let inner_td = type_space[comp_tyidx].unwrap_or_else(() => {
    raise WitError::Error("missing componenttype for `" + full + "`")
  })
  let inner_decls = match inner_td {
    ComponentType(xs) => xs
    _ => raise Error("expected componenttype for `" + full + "`")
  }
  let items : Array[WorldItem] = []
  for d in inner_decls {
    match d {
      Import(n, _attributes, InstanceType(_ti)) =>
        items.push(Import({ raw: normalize_inst_name(n), }))
      Export(n, _attributes, InstanceType(_ti)) =>
        items.push(Export({ raw: normalize_inst_name(n), }))
      _ => ()
    }
  }
  (pkg, ver, { name, items, })
}

///|
pub fn decode_wit_package_from_component(
  bytes : Bytes,
) -> Package raise WitError {
  let c = @component.parse_component(bytes) catch {
    e => raise Error("parsing component: " + e.to_string())
  }
  let mut pkg_name : String? = None
  let mut pkg_ver : String? = None
  let items : Array[TopItem] = []
  for e in c.exports {
    if e.sortidx.sort != Type {
      continue
    }
    let short = match e.name {
      Plain(b) | WithVersion(b, _) => {
        let sb = StringBuilder::StringBuilder()
        for i in 0..<b.length() {
          sb.write_char(b[i].to_int().unsafe_to_char())
        }
        sb.to_string()
      }
    }
    // WIT package components use even type indices (0,2,4,...) for the wrappers.
    if (e.sortidx.idx & 1) != 0 {
      continue
    }
    let tdef_idx = e.sortidx.idx / 2
    if tdef_idx < 0 || tdef_idx >= c.types.length() {
      continue
    }
    if c.types[tdef_idx] is ComponentType(decls) {
      // Heuristic: interface wrappers export an instance; world wrappers export a component.
      let mut has_instance_export = false
      let mut has_component_export = false
      for d in decls {
        match d {
          Export(_, _attributes, InstanceType(_)) => has_instance_export = true
          Export(_, _attributes, ComponentType(_)) =>
            has_component_export = true
          _ => ()
        }
      }
      if has_instance_export && !has_component_export {
        let (pkg, ver, iface) = decode_interface_from_componenttype(
          decls, short,
        )
        if pkg_name is None {
          pkg_name = Some(pkg)
        }
        if pkg_ver is None {
          pkg_ver = ver
        }
        items.push(Interface(iface))
      } else if has_component_export {
        let (pkg, ver, world) = decode_world_from_componenttype(decls, short)
        if pkg_name is None {
          pkg_name = Some(pkg)
        }
        if pkg_ver is None {
          pkg_ver = ver
        }
        items.push(World(world))
      } else {
        ()
      }
    }
  }
  { name: pkg_name, version: pkg_ver, items, nested: [], }
}
