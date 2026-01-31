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
  AliasOuter(Int, Int) // (count, idx)
  ExportedType(String, @component.TypeBound)
}

///|
fn prim_name_of(p : @component.PrimValType) -> String {
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
  export_name_by_idx : Map[Int, String],
  resource_by_idx : Map[Int, String],
) -> TypeExpr raise WitError {
  match v {
    Prim(p) => Id(prim_name_of(p))
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
                @component.TypeBound::SubResource => Id(n) // resources are value-level via own/borrow, see below
                @component.TypeBound::Eq(_ti) => Id(n)
              }
          }
      }
  }
}

///|
fn typeexpr_of_typedef(
  slots : Array[TypeSlot],
  td : @component.TypeDef,
  export_name_by_idx : Map[Int, String],
  resource_by_idx : Map[Int, String],
) -> TypeExpr raise WitError {
  match td {
    DefValType(p) => Id(prim_name_of(p))
    List(t) =>
      Apply("list", [
        typeexpr_of_valtype(slots, t, export_name_by_idx, resource_by_idx),
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
  match find_last_code_unit(full, 64) { // '@'
    Some(i) =>
      if i > 0 && i + 1 < full.length() {
        ver = Some(slice_ascii(full, i + 1, full.length()))
        base = slice_ascii(full, 0, i)
      }
    None => ()
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
) -> (Array[TypeSlot], Map[String, Int], Map[Int, String], Map[Int, String]) {
  let slots : Array[TypeSlot] = []
  let exported_idx_by_name : Map[String, Int] = {}
  let export_name_by_idx : Map[Int, String] = {}
  let resource_by_idx : Map[Int, String] = {}
  for d in decls {
    match d {
      Type(td) => slots.push(Def(td))
      AliasOuter(kind, count, idx) =>
        if kind == 0x03 {
          slots.push(AliasOuter(count, idx))
        }
      Export(name, desc) =>
        match desc {
          @component.ExternDesc::Type(bound) => {
            let idx = slots.length()
            slots.push(ExportedType(name, bound))
            exported_idx_by_name.set(name, idx)
            export_name_by_idx.set(idx, name)
            match bound {
              @component.TypeBound::SubResource =>
                resource_by_idx.set(idx, name)
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
  let mut full_name : String? = None
  let mut inst_tyidx : Int? = None
  for d in decls {
    match d {
      Export(name, @component.ExternDesc::InstanceType(ti)) => {
        full_name = Some(name)
        inst_tyidx = Some(ti)
      }
      _ => ()
    }
  }
  let full = full_name.unwrap_or_else(fn() {
    raise WitError::Error(
      "not an interface wrapper: `" + export_short_name + "`",
    )
  })
  let (pkg, name, ver) = decode_full_name(full)
  let type_space = build_componenttype_type_space(decls)

  // Build a small amount of context for resolving `(alias outer 1 <idx>)` in the
  // exported instancetype back to the imported instance's type export.
  let alias_export_by_typeidx : Map[Int, (Int, String)] = {} // typeidx -> (inst_idx, export_name)
  let inst_sig_typeidx_by_inst : Map[Int, Int] = {} // inst_idx -> instancetype typeidx (in componenttype space)
  let mut cur_typeidx = 0
  let mut cur_instidx = 0
  for d in decls {
    match d {
      @component.ComponentDecl::Type(_td) => cur_typeidx = cur_typeidx + 1
      @component.ComponentDecl::Import(
        _n,
        @component.ExternDesc::InstanceType(ti)
      ) => {
        inst_sig_typeidx_by_inst.set(cur_instidx, ti)
        cur_instidx = cur_instidx + 1
      }
      @component.ComponentDecl::AliasInstanceExport(kind, inst, n) =>
        if kind == 0x03 {
          alias_export_by_typeidx.set(cur_typeidx, (inst, n))
          cur_typeidx = cur_typeidx + 1
        }
      @component.ComponentDecl::AliasOuter(kind, _count, _idx) =>
        if kind == 0x03 {
          cur_typeidx = cur_typeidx + 1
        }
      _ => ()
    }
  }
  let inst_td = match inst_tyidx {
    Some(i) =>
      match type_space[i] {
        Some(td) => td
        None => raise WitError::Error("missing instancetype for `" + full + "`")
      }
    None =>
      raise WitError::Error("missing instancetype export for `" + full + "`")
  }
  let inst_decls = match inst_td {
    @component.TypeDef::InstanceType(xs) => xs
    @component.TypeDef::InstanceTypeEmpty => []
    _ => raise WitError::Error("expected instancetype for `" + full + "`")
  }
  let (slots, idx_by_name, export_name_by_idx, resource_by_idx0) = build_instancetype_type_slots(
    inst_decls,
  )

  // Augment resource_by_idx: treat exported types that are eq to an outer resource as resources.
  let resource_by_idx : Map[Int, String] = {}
  for kv in resource_by_idx0.iter() {
    let (i, n) = kv
    resource_by_idx.set(i, n)
  }
  fn resolve_outer_export_typedef(
    type_space : Array[@component.TypeDef?],
    inst_sig_typeidx_by_inst : Map[Int, Int],
    alias_export_by_typeidx : Map[Int, (Int, String)],
    outer_typeidx : Int,
  ) -> (@component.TypeDef?, @component.TypeBound?)? raise WitError {
    match alias_export_by_typeidx.get(outer_typeidx) {
      None => None
      Some(pair) => {
        let (inst_idx, export_name) = pair
        let sig_ti = inst_sig_typeidx_by_inst
          .get(inst_idx)
          .unwrap_or_else(fn() { raise WitError::Error("missing import sig") })
        let sig_td = match type_space[sig_ti] {
          Some(td) => td
          None => raise WitError::Error("missing instancetype signature")
        }
        let sig_decls = match sig_td {
          @component.TypeDef::InstanceType(xs) => xs
          @component.TypeDef::InstanceTypeEmpty => []
          _ => raise WitError::Error("expected instancetype signature")
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
                  @component.TypeBound::SubResource => Some((None, Some(bound)))
                  @component.TypeBound::Eq(ti) =>
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
  let resources : Map[String, ResourceDecl] = {}
  for kv in resource_by_idx.iter() {
    let (_i, rname) = kv
    resources.set(rname, { name: rname, methods: [] })
  }

  // Collect named types.
  let type_items : Array[InterfaceItem] = []
  for d in inst_decls {
    match d {
      Export(tname, @component.ExternDesc::Type(bound)) =>
        match bound {
          @component.TypeBound::SubResource => ()
          @component.TypeBound::Eq(ti) =>
            // If this is an alias to an outer type, try to resolve it through
            // the imported instance signature.
            match slots[ti] {
              AliasOuter(count, outer_idx) =>
                if count == 1 {
                  match
                    resolve_outer_export_typedef(
                      type_space, inst_sig_typeidx_by_inst, alias_export_by_typeidx,
                      outer_idx,
                    ) {
                    Some((None, Some(@component.TypeBound::SubResource))) => {
                      // Treat as a re-exported resource.
                      resources.set(tname, { name: tname, methods: [] })
                      // Also treat this exported nominal type index as a resource for own/borrow decoding.
                      match idx_by_name.get(tname) {
                        Some(exp_idx) => resource_by_idx.set(exp_idx, tname)
                        None => ()
                      }
                    }
                    Some((Some(td2), _b)) =>
                      match td2 {
                        @component.TypeDef::Record(fields) => {
                          let fs : Array[(String, TypeExpr)] = []
                          for f in fields {
                            fs.push(
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
                          type_items.push(Record({ name: tname, fields: fs }))
                        }
                        @component.TypeDef::Flags(xs) =>
                          type_items.push(Flags({ name: tname, flags: xs }))
                        @component.TypeDef::Enum(xs) =>
                          type_items.push(Enum({ name: tname, cases: xs }))
                        @component.TypeDef::Variant(cases) => {
                          let cs : Array[VariantCase] = []
                          for c in cases {
                            let payload = match c.ty {
                              None => None
                              Some(v) =>
                                Some(
                                  typeexpr_of_valtype(
                                    slots, v, export_name_by_idx, resource_by_idx,
                                  ),
                                )
                            }
                            cs.push({ name: c.label, payload })
                          }
                          type_items.push(Variant({ name: tname, cases: cs }))
                        }
                        _ => {
                          let ty = typeexpr_of_typedef(
                            slots, td2, export_name_by_idx, resource_by_idx,
                          )
                          type_items.push(TypeAlias({ name: tname, ty }))
                        }
                      }
                    _ =>
                      type_items.push(
                        TypeAlias({ name: tname, ty: Id("other") }),
                      )
                  }
                } else {
                  type_items.push(TypeAlias({ name: tname, ty: Id("other") }))
                }
              Def(td2) =>
                match td2 {
                  @component.TypeDef::Record(fields) => {
                    let fs : Array[(String, TypeExpr)] = []
                    for f in fields {
                      fs.push(
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
                    type_items.push(Record({ name: tname, fields: fs }))
                  }
                  @component.TypeDef::Flags(xs) =>
                    type_items.push(Flags({ name: tname, flags: xs }))
                  @component.TypeDef::Enum(xs) =>
                    type_items.push(Enum({ name: tname, cases: xs }))
                  @component.TypeDef::Variant(cases) => {
                    let cs : Array[VariantCase] = []
                    for c in cases {
                      let payload = match c.ty {
                        None => None
                        Some(v) =>
                          Some(
                            typeexpr_of_valtype(
                              slots, v, export_name_by_idx, resource_by_idx,
                            ),
                          )
                      }
                      cs.push({ name: c.label, payload })
                    }
                    type_items.push(Variant({ name: tname, cases: cs }))
                  }
                  _ => {
                    let ty = typeexpr_of_typedef(
                      slots, td2, export_name_by_idx, resource_by_idx,
                    )
                    type_items.push(TypeAlias({ name: tname, ty }))
                  }
                }
              _ => type_items.push(TypeAlias({ name: tname, ty: Id("other") }))
            }
        }
      _ => ()
    }
  }

  // Collect exported funcs and resource methods.
  let func_items : Array[InterfaceItem] = []
  for d in inst_decls {
    match d {
      Export(fname, @component.ExternDesc::FuncType(ti)) =>
        match slots[ti] {
          Def(@component.TypeDef::FuncType(ft)) =>
            // Resource methods follow `[method]res.name`.
            if fname.has_prefix("[method]") {
              let rest = slice_ascii(fname, 8, fname.length())
              match find_last_code_unit(rest, 46) { // '.'
                Some(dot) => {
                  let rname = slice_ascii(rest, 0, dot)
                  let mname = slice_ascii(rest, dot + 1, rest.length())
                  match resources.get(rname) {
                    Some(r0) => {
                      let r = r0
                      let params : Array[(String, TypeExpr)] = []
                      // Drop implicit self param when present.
                      let mut start = 0
                      if ft.params.length() > 0 && ft.params[0].label == "self" {
                        start = 1
                      }
                      for i in start..<ft.params.length() {
                        let p = ft.params[i]
                        params.push(
                          (
                            p.label,
                            typeexpr_of_valtype(
                              slots,
                              p.ty,
                              export_name_by_idx,
                              resource_by_idx,
                            ),
                          ),
                        )
                      }
                      let results : Array[(String?, TypeExpr)] = []
                      match ft.result {
                        None => ()
                        Some(v) =>
                          results.push(
                            (
                              None,
                              typeexpr_of_valtype(
                                slots, v, export_name_by_idx, resource_by_idx,
                              ),
                            ),
                          )
                      }
                      r.methods.push({
                        name: mname,
                        is_async: ft.is_async,
                        params,
                        results,
                      })
                      resources.set(rname, r)
                    }
                    None => ()
                  }
                }
                None => ()
              }
            } else {
              let params : Array[(String, TypeExpr)] = []
              for p in ft.params {
                params.push(
                  (
                    p.label,
                    typeexpr_of_valtype(
                      slots,
                      p.ty,
                      export_name_by_idx,
                      resource_by_idx,
                    ),
                  ),
                )
              }
              let results : Array[(String?, TypeExpr)] = []
              match ft.result {
                None => ()
                Some(v) =>
                  results.push(
                    (
                      None,
                      typeexpr_of_valtype(
                        slots, v, export_name_by_idx, resource_by_idx,
                      ),
                    ),
                  )
              }
              func_items.push(
                Func({ name: fname, is_async: ft.is_async, params, results }),
              )
            }
          _ => ()
        }
      _ => ()
    }
  }

  // Assemble interface items: types, resources, funcs.
  let items : Array[InterfaceItem] = []
  for it in type_items {
    items.push(it)
  }
  for kv in resources.iter() {
    let (_k, r) = kv
    items.push(Resource(r))
  }
  for it in func_items {
    items.push(it)
  }
  (pkg, ver, { name, items })
}

///|
fn decode_world_from_componenttype(
  decls : Array[@component.ComponentDecl],
  export_short_name : String,
) -> (String, String?, World) raise WitError {
  let mut full_name : String? = None
  let mut comp_tyidx : Int? = None
  for d in decls {
    match d {
      Export(name, @component.ExternDesc::ComponentType(ti)) => {
        full_name = Some(name)
        comp_tyidx = Some(ti)
      }
      _ => ()
    }
  }
  let full = full_name.unwrap_or_else(fn() {
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

  let inner_td = match comp_tyidx {
    Some(i) =>
      match type_space[i] {
        Some(td) => td
        None =>
          raise WitError::Error("missing componenttype for `" + full + "`")
      }
    None =>
      raise WitError::Error("missing componenttype export for `" + full + "`")
  }
  let inner_decls = match inner_td {
    @component.TypeDef::ComponentType(xs) => xs
    _ => raise WitError::Error("expected componenttype for `" + full + "`")
  }
  let items : Array[WorldItem] = []
  for d in inner_decls {
    match d {
      Import(n, @component.ExternDesc::InstanceType(_ti)) =>
        items.push(Import({ raw: normalize_inst_name(n) }))
      Export(n, @component.ExternDesc::InstanceType(_ti)) =>
        items.push(Export({ raw: normalize_inst_name(n) }))
      _ => ()
    }
  }
  (pkg, ver, { name, items })
}

///|
pub fn decode_wit_package_from_component(
  bytes : Bytes,
) -> Package raise WitError {
  let c = @component.parse_component(bytes) catch {
    e => raise WitError::Error("parsing component: " + e.to_string())
  }
  let mut pkg_name : String? = None
  let mut pkg_ver : String? = None
  let items : Array[TopItem] = []
  for e in c.exports {
    if e.sortidx.sort != @component.Sort::Type {
      continue
    }
    let short = match e.name {
      @component.ExportName::Plain(b) => {
        // ASCII
        let sb = StringBuilder::new()
        for i in 0..<b.length() {
          sb.write_char(b[i].to_int().unsafe_to_char())
        }
        sb.to_string()
      }
      @component.ExportName::WithVersion(b, _vs) => {
        let sb = StringBuilder::new()
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
    match c.types[tdef_idx] {
      @component.TypeDef::ComponentType(decls) => {
        // Heuristic: interface wrappers export an instance; world wrappers export a component.
        let mut has_instance_export = false
        let mut has_component_export = false
        for d in decls {
          match d {
            @component.ComponentDecl::Export(
              _,
              @component.ExternDesc::InstanceType(_)
            ) => has_instance_export = true
            @component.ComponentDecl::Export(
              _,
              @component.ExternDesc::ComponentType(_)
            ) => has_component_export = true
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
      _ => ()
    }
  }
  { name: pkg_name, version: pkg_ver, items, nested: [] }
}
