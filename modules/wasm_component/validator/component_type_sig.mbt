///|
priv struct ComponentTypeSignatures {
  import_functions : Map[String, FuncSigShape]
  export_functions : Map[String, FuncSigShape]
  import_types : Map[String, TypeSig]
  import_bounds : Map[String, @component.TypeBound]
  export_types : Map[String, TypeSig]
}

///|
fn componenttype_signatures_of_decls(
  decls : Array[@component.ComponentDecl],
  global_types : Array[@component.TypeDef?],
  global_resource_ids : Array[Int32?],
) -> ComponentTypeSignatures {
  let signatures : ComponentTypeSignatures = {
    import_functions: Map([]),
    export_functions: Map([]),
    import_types: Map([]),
    import_bounds: Map([]),
    export_types: Map([]),
  }
  let local_types : Array[@component.TypeDef] = []
  let local_ids : Array[Int32?] = []
  // Export type signatures carry definitions through eq slots. Function and
  // import type signatures use placeholder slots for the same declarations.
  let export_types : Array[@component.TypeDef] = []
  let export_ids : Array[Int32?] = []
  let global_resolver : TypeSigResolver = {
    locals: None,
    global_types,
    global_resource_ids,
    known_sigs: None,
    visiting: Map([]),
  }
  let local_resolver = {
    ..global_resolver,
    locals: Some((local_types, local_ids)),
  }
  let export_resolver = {
    ..global_resolver,
    locals: Some((export_types, export_ids)),
  }
  let mut next_rid = 0
  for rid in global_resource_ids {
    if rid is Some(value) && value >= next_rid {
      next_rid = value + 1
    }
  }

  fn push_type(t : @component.TypeDef) -> Unit {
    let rid = if t is ResourceType(_, _, _, _) {
      let rid = next_rid
      next_rid += 1
      Some(rid)
    } else {
      None
    }
    local_types.push(t)
    local_ids.push(rid)
    export_types.push(t)
    export_ids.push(rid)
  }

  fn record_extern(
    name : String,
    desc : @component.ExternDesc,
    imported : Bool,
  ) -> Unit {
    match desc {
      Type(bound) => {
        let resolver = if imported { local_resolver } else { export_resolver }
        let out = if imported {
          signatures.import_types
        } else {
          signatures.export_types
        }
        if imported {
          signatures.import_bounds.set(name, bound)
        }
        match bound {
          SubResource => {
            let idx = local_types.length()
            push_type(ResourceType(-1, 0x7f, None, HostDefined))
            out.set(name, resolver.resolve(TypeIdx(idx)))
          }
          Eq(idx) => {
            out.set(name, resolver.resolve(TypeIdx(idx)))
            local_types.push(InstanceTypeEmpty)
            local_ids.push(None)
            if idx >= 0 && idx < export_types.length() {
              export_types.push(export_types[idx])
              export_ids.push(export_ids[idx])
            } else {
              export_types.push(InstanceTypeEmpty)
              export_ids.push(None)
            }
          }
        }
      }
      FuncType(idx) => {
        let (definition, resolver) = if idx >= 0 && idx < local_types.length() {
          (Some(local_types[idx]), local_resolver)
        } else {
          (global_types.get(idx).bind(value => value), global_resolver)
        }
        if definition is Some(FuncType(ft)) {
          let out = if imported {
            signatures.import_functions
          } else {
            signatures.export_functions
          }
          out.set(name, resolver.resolve_function(ft))
        }
      }
      _ => ()
    }
  }

  for decl in decls {
    match decl {
      Type(t) => push_type(t)
      AliasOuter(0x03, _, _) | AliasInstanceExport(0x03, _, _) =>
        push_type(InstanceTypeEmpty)
      Import(name, _, desc) => record_extern(name, desc, true)
      Export(name, _, desc) => record_extern(name, desc, false)
      _ => ()
    }
  }
  signatures
}

///|
priv struct CoreModuleRequirement {
  imports : Map[String, CoreExternType]
  exports : Map[String, Int32]
}

///|
fn CoreModuleTypeSignature::requirement(
  self : CoreModuleTypeSignature,
) -> CoreModuleRequirement {
  {
    imports: core_module_import_sig_of_type(self.imports),
    exports: self.export_kinds,
  }
}

///|
fn componenttype_import_core_modules(
  decls : Array[@component.ComponentDecl],
) -> Map[String, CoreModuleRequirement] raise ComponentValidationError {
  let core_types : Array[CoreModuleTypeSignature?] = []
  for decl in decls {
    match decl {
      CoreType(bytes) =>
        core_types.push(
          parse_single_component_core_type(
            bytes,
            -1,
            core_types.length(),
            [],
            SignaturesOnly,
            allow_prefixed=false,
          ),
        )
      AliasOuter(kind, _, _) | AliasInstanceExport(kind, _, _) =>
        if kind != 0x03 {
          // Keep the index of the alias even when its signature is unavailable.
          core_types.push(None)
        }
      _ => ()
    }
  }
  let requirements : Map[String, CoreModuleRequirement] = Map([])
  for decl in decls {
    if decl is Import(name, _, CoreModuleType(index)) &&
      core_types.get(index) is Some(Some(signature)) {
      requirements.set(name, signature.requirement())
    }
  }
  requirements
}

///|
fn check_typeidx(
  idx : Int32,
  bound : Int32,
) -> Unit raise ComponentValidationError {
  if idx < 0 || idx >= bound {
    raise InvalidTypeIndex(idx)
  }
}

///|
fn check_sortidx(
  sortidx : @component.SortIdx,
  counts : Counts,
  type_bound : Int32,
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
  idx : Int32,
  bound : Int32,
) -> Unit raise ComponentValidationError {
  if idx < 0 || idx >= bound {
    raise InvalidCoreTypeIndex(idx)
  }
}

///|
fn outer_type_of_alias(
  type_outers : Array[Array[@component.TypeDef?]],
  count : Int32,
  idx : Int32,
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
  core_type_outers : Array[Array[CoreModuleTypeSignature?]],
  count : Int32,
  idx : Int32,
) -> CoreModuleTypeSignature? raise ComponentValidationError {
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
  visiting : Map[Int32, Int32],
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
          Some(List(v)) | Some(FixedList(v, _)) =>
            valtype_contains_borrow(v, type_table, visiting)
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
fn is_map_key_type(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int32, Int32],
) -> Bool {
  match ty {
    Prim(Bool)
    | Prim(S8)
    | Prim(U8)
    | Prim(S16)
    | Prim(U16)
    | Prim(S32)
    | Prim(U32)
    | Prim(S64)
    | Prim(U64)
    | Prim(Char)
    | Prim(String) => true
    Prim(_) => false
    TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() || visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, 1)
        let valid = match type_table[idx] {
          Some(DefValType(p)) => is_map_key_type(Prim(p), type_table, visiting)
          _ => false
        }
        visiting.remove(idx) |> ignore
        valid
      }
  }
}

///|
priv struct TypeValidationScope {
  cfg : ComponentValidationConfig
  type_outers : Array[Array[@component.TypeDef?]]
  type_outer_depths : Array[Int32]
  component_depth : Int32
  core_type_outers : Array[Array[CoreModuleTypeSignature?]]
}

///|
fn TypeValidationScope::validate_typedef(
  self : TypeValidationScope,
  td : @component.TypeDef,
  allow_resource_defs~ : Bool,
) -> Unit raise ComponentValidationError {
  if self.type_outers.length() == 0 ||
    self.type_outer_depths.length() != self.type_outers.length() ||
    self.core_type_outers.length() == 0 {
    raise SectionParseError(
      7, "missing outer environment for typedef validation",
    )
  }
  let type_table = self.type_outers[0]
  let cfg = self.cfg
  match td {
    DefValType(_) => ()
    List(v) => validate_valtype(v, type_table)
    FixedList(v, len) => {
      if len <= 0 {
        raise SectionParseError(7, "fixed-length list must not be empty")
      }
      validate_valtype(v, type_table)
    }
    MapType(key, value) => {
      validate_valtype(key, type_table)
      validate_valtype(value, type_table)
      if !is_map_key_type(key, type_table, Map([])) {
        raise SectionParseError(7, "invalid map key type")
      }
    }
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
    ComponentType(decls) =>
      self.validate_declarations(decls.iter(), component=true)
    InstanceTypeEmpty => ()
    InstanceType(decls) =>
      self.validate_declarations(
        decls.iter().map(instance_declaration),
        component=false,
      )
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
fn instance_declaration(
  decl : @component.InstanceDecl,
) -> @component.ComponentDecl {
  match decl {
    CoreType(bytes) => CoreType(bytes)
    Type(td) => Type(td)
    AliasOuter(kind, count, idx) => AliasOuter(kind, count, idx)
    AliasInstanceExport(kind, idx, name) => AliasInstanceExport(kind, idx, name)
    Export(name, attributes, desc) => Export(name, attributes, desc)
  }
}

///|
priv struct TypeInterfaceNames {
  seen : Map[String, String]
  resources : Map[String, Int32]
  resource_types : Map[Int32, Int32]
}

///|
fn TypeInterfaceNames::TypeInterfaceNames() -> TypeInterfaceNames {
  { seen: Map([]), resources: Map([]), resource_types: Map([]), }
}

///|
fn TypeValidationScope::validate_declarations(
  self : TypeValidationScope,
  decls : Iter[@component.ComponentDecl],
  component~ : Bool,
) -> Unit raise ComponentValidationError {
  let types : Array[@component.TypeDef?] = []
  let core_types : Array[CoreModuleTypeSignature?] = []
  let nested_scope : TypeValidationScope = {
    cfg: self.cfg,
    type_outers: [types] + self.type_outers,
    type_outer_depths: [self.component_depth] + self.type_outer_depths,
    component_depth: self.component_depth,
    core_type_outers: [core_types] + self.core_type_outers,
  }
  let outer_core_type_bounds = self.core_type_outers.map(scope => scope.length())
  let resource_ids : Array[Int32?] = []
  let named_types : Map[Int32, Int32] = Map([])
  let imports = TypeInterfaceNames()
  let exports = TypeInterfaceNames()
  for decl in decls {
    match decl {
      CoreType(bytes) => {
        let bound = core_types.length()
        let kinds = if component {
          validate_single_core_type(bytes, bound, outer_core_type_bounds)
        } else {
          parse_single_component_core_type(
            bytes,
            -1,
            bound,
            [],
            KindsOnly,
            allow_prefixed=false,
          )
        }
        core_types.push(kinds)
      }
      AliasOuter(kind, count, idx) =>
        if kind == 0x03 {
          let outer = outer_type_of_alias(self.type_outers, count, idx)
          if self.type_outer_depths[count - 1] < self.component_depth &&
            outer is Some(td) &&
            typedef_refers_to_resource(td, self.type_outers[count - 1], Map([])) {
            raise SectionParseError(7, "transitively refers to resources")
          }
          types.push(outer)
          resource_ids.push(None)
        } else if kind == 0x110 {
          core_types.push(
            outer_core_type_of_alias(self.core_type_outers, count, idx),
          )
        } else {
          raise SectionParseError(7, "outer alias may only refer to types")
        }
      AliasInstanceExport(kind, _, _) =>
        if kind == 0x03 {
          types.push(None)
          resource_ids.push(None)
        } else if kind != 0x05 {
          raise SectionParseError(
            7, "alias export may only refer to types or instances",
          )
        }
      Type(td) => {
        nested_scope.validate_typedef(td, allow_resource_defs=false)
        types.push(Some(td))
        resource_ids.push(None)
      }
      Import(name, attributes, desc) | Export(name, attributes, desc) => {
        let importing = decl is Import(_, _, _)
        let direction = if importing { "import" } else { "export" }
        let names = if importing { imports } else { exports }
        validate_extern_name_string(name, self.cfg)
        validate_name_attributes_string(
          7,
          name,
          attributes,
          sort_of_externdesc(desc),
          self.cfg,
        )
        let key = ascii_lower_key(name)
        match names.seen.get(key) {
          Some(prev) =>
            if prev == name {
              if importing {
                raise DuplicateImportName(name)
              }
              raise DuplicateExportName(name)
            } else {
              raise SectionParseError(
                7,
                "\{direction} name `\{name}` conflicts with previous name `\{prev}`",
              )
            }
          None => names.seen.set(key, name)
        }
        validate_externdesc(desc, types, core_types.length())
        if desc is CoreModuleType(tyidx) && core_types[tyidx] is None {
          raise CoreTypeIndexNotModuleType(tyidx)
        }
        if !component {
          // An instance export introduces a fresh local type index.
          if desc is Type(_) {
            types.push(None)
            resource_ids.push(None)
          }
          continue
        }
        match desc {
          Type(bound) => {
            let new_idx = types.length()
            match bound {
              Eq(idx) => {
                types.push(types[idx])
                resource_ids.push(resource_ids[idx])
              }
              SubResource => {
                types.push(Some(ResourceType(-1, 0x7f, None, HostDefined)))
                resource_ids.push(None)
                names.resources.set(name, new_idx)
                names.resource_types.set(new_idx, 1)
              }
            }
            named_types.set(new_idx, 1)
            if !valtype_valid_for_type_import_export(
                TypeIdx(new_idx),
                types,
                resource_ids,
                named_types,
                Map([]),
              ) {
              raise SectionParseError(
                7,
                "type not valid to be used as \{direction}",
              )
            }
          }
          FuncType(idx) => {
            // The external descriptor check has already checked this type.
            guard types[idx] is Some(FuncType(ft)) else { continue }
            validate_bracketed_func_name(
              7,
              name,
              ft,
              types,
              resource_ids,
              names.resources,
            )
            if (
                importing &&
                functype_uses_disallowed_resources(
                  ft,
                  types,
                  names.resource_types,
                )
              ) ||
              !functype_valid_in_interface(ft, types, resource_ids, named_types) {
              raise SectionParseError(
                7,
                "func not valid to be used as \{direction}",
              )
            }
          }
          _ => ()
        }
      }
    }
  }
}

///|
fn validate_externdesc(
  desc : @component.ExternDesc,
  type_table : Array[@component.TypeDef?],
  core_type_bound : Int32,
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
  visiting : Map[Int32, Unit],
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
              DefValType(String) | List(_) | MapType(_, _) => true
              DefValType(_)
              | Flags(_)
              | Enum(_)
              | Own(_)
              | Borrow(_)
              | ResourceType(_, _, _, _)
              | Stream(_)
              | Future(_)
              | InstanceTypeEmpty => false
              FixedList(element, _) =>
                valtype_contains_list_or_string(element, type_table, visiting)
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
