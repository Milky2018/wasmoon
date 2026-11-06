///|
/// Handle component import section (id 10).
fn validate_component_section_import(
  payload : Bytes,
  cfg : ComponentValidationConfig,
  is_root : Bool,
  counts : Counts,
  type_table : Array[@component.TypeDef?],
  local_resource_types : Array[Bool],
  resource_ids : Array[Int32?],
  type_sizes : Array[Int32],
  type_depths : Array[Int32],
  components : Array[ComponentIndexEntry],
  instances : Array[InstanceIndexEntry],
  named_types : Map[Int32, Int32],
  import_named_types : Map[Int32, Int32],
  core_types : Array[CoreModuleTypeSignature?],
  core_modules : Array[CoreModuleIndexEntry],
  func_types : Array[@component.FuncType?],
  func_sig_shapes : Array[FuncSigShape?],
  seen_import_names : Map[String, String],
  import_resource_names : Map[String, Int32],
  my_import_sorts : Map[String, @component.Sort],
  my_import_core_modules : Map[String, CoreModuleRequirement],
  my_import_instance_sigs : Map[String, InstanceSig],
  my_import_func_sigs : Map[String, FuncSigShape],
  my_import_instance_resource_exports : Map[String, Map[String, Int32]],
  my_import_type_bounds : Map[String, @component.TypeBound],
  my_import_type_sigs : Map[String, TypeSig],
  type_outers : Array[Array[@component.TypeDef?]],
  next_resource_id : Int32,
  imported_funcs : Int32,
) -> (Int32, Int32) raise ComponentValidationError {
  let mut next_resource_id = next_resource_id
  let mut imported_funcs = imported_funcs
  let imports = @component.parse_import_section(payload) catch {
    e => raise SectionParseError(10, "\{e}")
  }
  for i in imports {
    validate_import_name(i.name, cfg)
    validate_name_attributes(
      10,
      importname_to_bytes(i.name),
      i.attributes,
      sort_of_externdesc(i.desc),
      cfg,
    )
    if is_root && i.desc is ComponentType(_) {
      raise SectionParseError(
        10, "root-level component imports are not supported",
      )
    }
    if importname_to_string(i.name) is Some(name) {
      let key = if cfg.wit_names { wit_conflict_key(name) } else { name }
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
    if importname_to_string(i.name) is Some(name) {
      my_import_sorts.set(name, sort_of_externdesc(i.desc))
    }
    if importname_to_string(i.name) is Some(name) &&
      parse_bracket_resource_name(name) is Some(_) &&
      !(i.desc is FuncType(_)) {
      raise SectionParseError(10, "is not a func")
    }
    // Import type references must be in-bounds at the point they appear.
    validate_externdesc(i.desc, type_table, counts.core_type)
    match i.desc {
      FuncType(tyidx) =>
        match type_table[tyidx] {
          Some(FuncType(_)) => ()
          Some(_) => raise CanonExpectedFuncType(tyidx)
          None => ()
        }
      ComponentType(tyidx) =>
        match type_table[tyidx] {
          Some(ComponentType(_)) => ()
          Some(_) => raise InvalidTypeIndex(tyidx)
          None => ()
        }
      InstanceType(tyidx) =>
        match type_table[tyidx] {
          Some(InstanceType(_)) => ()
          Some(InstanceTypeEmpty) => ()
          Some(_) => raise InvalidTypeIndex(tyidx)
          None => ()
        }
      _ => ()
    }
    if i.desc is FuncType(tyidx) {
      match type_table[tyidx] {
        Some(FuncType(ft)) => {
          let sig = funcsig_of_functype(ft, type_table, resource_ids)
          if importname_to_string(i.name) is Some(name) {
            validate_bracketed_func_name(
              10, name, ft, type_table, resource_ids, import_resource_names,
            )
          }
          if !functype_valid_in_interface(
              ft, type_table, resource_ids, import_named_types,
            ) {
            raise SectionParseError(10, "func not valid to be used as import")
          }
          func_types.push(Some(ft))
          func_sig_shapes.push(Some(sig))
          if importname_to_string(i.name) is Some(name) {
            my_import_func_sigs.set(name, sig)
          }
        }
        _ => {
          func_types.push(None)
          func_sig_shapes.push(None)
        }
      }
    }
    match i.desc {
      CoreModuleType(tyidx) => {
        guard core_types[tyidx] is Some(signature) else {
          raise CoreTypeIndexNotModuleType(tyidx)
        }
        core_modules.push({
          definition: None,
          export_kinds: Some(signature.export_kinds),
          export_types: Some(signature.export_types),
          import_types: Some(signature.imports),
        })
        if importname_to_string(i.name) is Some(name) {
          my_import_core_modules.set(name, signature.requirement())
        }
      }
      InstanceType(tyidx) => {
        let mut instance_signature = None
        let mut type_map : Map[String, ExportedTypeInfo]? = None
        let mut type_sig_map : Map[String, TypeSig]? = None
        let mut resource_exports : Map[String, Int32]? = None
        let mut func_export_sigs : Map[String, FuncSigShape]? = None
        match type_table[tyidx] {
          Some(td) => {
            let sig = instancetype_sig_of_typedef(td, type_table, Map([]))
            instance_signature = Some(sig)
            if importname_to_string(i.name) is Some(name) {
              my_import_instance_sigs.set(name, sig)
            }
            match td {
              InstanceType(decls) => {
                let local_types : Array[@component.TypeDef] = []
                let local_resource_ids : Array[Int32?] = []
                let out : Map[String, ExportedTypeInfo] = Map([])
                let type_sigs : Map[String, TypeSig] = Map([])
                let res : Map[String, Int32] = Map([])
                let fns : Map[String, FuncSigShape] = Map([])
                let mut any_types = false
                let mut any_fns = false
                let visiting : Map[Int32, Int32] = Map([])
                fn record_type_slot() -> Unit {
                  local_types.push(InstanceTypeEmpty)
                  local_resource_ids.push(None)
                }

                for d in decls {
                  match d {
                    Type(t) => {
                      local_types.push(t)
                      local_resource_ids.push(None)
                    }
                    AliasOuter(kind, _count, _idx) =>
                      if kind == 0x03 {
                        record_type_slot()
                      }
                    AliasInstanceExport(kind, _inst, _name) =>
                      if kind == 0x03 {
                        record_type_slot()
                      }
                    Export(name, _attributes, desc) =>
                      match desc {
                        Type(b) =>
                          match b {
                            SubResource => {
                              let rid = next_resource_id
                              next_resource_id += 1
                              local_types.push(
                                ResourceType(-1, 0x7f, None, HostDefined),
                              )
                              local_resource_ids.push(Some(rid))
                              out.set(name, Resource(rid))
                              type_sigs.set(name, Resource(rid))
                              res.set(name, rid)
                              any_types = true
                            }
                            Eq(idx) => {
                              let new_idx = local_types.length()
                              if idx >= 0 && idx < local_types.length() {
                                local_types.push(local_types[idx])
                                local_resource_ids.push(local_resource_ids[idx])
                              } else {
                                record_type_slot()
                              }
                              let sig = type_sig_of_valtype_lg(
                                TypeIdx(new_idx),
                                local_types,
                                local_resource_ids,
                                type_table,
                                resource_ids,
                                visiting,
                              )
                              out.set(name, Opaque)
                              type_sigs.set(name, sig)
                              any_types = true
                            }
                          }
                        FuncType(ft_idx) => {
                          let sig = if ft_idx >= 0 &&
                            ft_idx < local_types.length() {
                            match local_types[ft_idx] {
                              FuncType(ft) =>
                                Some(
                                  funcsig_of_functype_lg(
                                    ft, local_types, local_resource_ids, type_table,
                                    resource_ids,
                                  ),
                                )
                              _ => None
                            }
                          } else if ft_idx >= 0 && ft_idx < type_table.length() {
                            match type_table[ft_idx] {
                              Some(FuncType(ft)) =>
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
          None => ()
        }
        // An imported instance has unknown effective size.
        instances.push({
          ..InstanceIndexEntry::unknown(),
          signature: instance_signature,
          exported_types: type_map,
          type_signatures: type_sig_map,
          function_signatures: func_export_sigs,
          in_interface: true,
        })
      }
      _ => ()
    }
    if i.desc is FuncType(_) {
      imported_funcs += 1
    }
    if i.desc is ComponentType(tyidx) {
      let entry = ComponentIndexEntry::unknown(1)
      if type_table.get(tyidx) is Some(Some(ComponentType(decls))) {
        let (import_sorts, import_instances, export_sorts, export_instances) = componenttype_signature_of_decls(
          decls, type_table,
        )
        let signatures = componenttype_signatures_of_decls(
          decls, type_table, resource_ids,
        )
        let core_requirements = componenttype_import_core_modules(decls)
        components.push({
          ..entry,
          import_sorts: Some(import_sorts),
          import_instance_sigs: Some(import_instances),
          import_func_sigs: Some(signatures.import_functions),
          import_core_modules: Some(core_requirements),
          import_type_bounds: Some(signatures.import_bounds),
          import_type_sigs: Some(signatures.import_types),
          export_sorts: Some(export_sorts),
          export_instance_sigs: Some(export_instances),
          export_type_sigs: Some(signatures.export_types),
          export_func_sigs: Some(signatures.export_functions),
        })
      } else {
        components.push(entry)
      }
    }
    if i.desc is Type(b) {
      // Type imports extend the type index space.
      //
      // `eq` imports are aliases to an existing type, so we can propagate
      // the underlying definition/size/depth. `sub resource` is treated
      // as abstract for now.
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
          type_table.push(Some(ResourceType(-1, 0x7f, None, HostDefined)))
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
      if importname_to_string(i.name) is Some(name) {
        match b {
          Eq(tyidx) => {
            my_import_type_bounds.set(name, Eq(tyidx))
            my_import_type_sigs.set(
              name,
              type_sig_of_typeidx(tyidx, type_table, resource_ids),
            )
          }
          SubResource => {
            import_resource_names.set(name, new_idx)
            my_import_type_bounds.set(name, SubResource)
            my_import_type_sigs.set(
              name,
              type_sig_of_typeidx(new_idx, type_table, resource_ids),
            )
          }
        }
      }
      if !valtype_valid_for_type_import_export(
          TypeIdx(new_idx),
          type_table,
          resource_ids,
          import_named_types,
          Map([]),
        ) {
        raise SectionParseError(10, "type not valid to be used as import")
      }
      if type_table[new_idx] is Some(InstanceType(_)) ||
        type_table[new_idx] is Some(InstanceTypeEmpty) {
        if !instancetype_valid_for_use_as_interface(
            new_idx, type_table, type_outers,
          ) {
          raise SectionParseError(10, "type not valid to be used as import")
        }
      }
    }
    count_import(i.desc, counts)
  }
  (next_resource_id, imported_funcs)
}
